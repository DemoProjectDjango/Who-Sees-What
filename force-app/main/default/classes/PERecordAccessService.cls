/**
 * How many records of one object a selected user can reach.
 *
 * The constraint that shapes everything here: Apex runs as the running user.
 * `with sharing` enforces *your* sharing, not theirs, so `SELECT COUNT() FROM
 * Account` returns what the administrator can see no matter whose name is on
 * the screen. It is the denominator, never the answer.
 *
 * What is exact anyway:
 *
 *  - Org-wide default, from EntityDefinition. Authoritative.
 *  - When the OWD is public, every user with object read reaches every record,
 *    so the total IS the answer. One query, exact, no further work.
 *  - When the user holds View All on the object, likewise.
 *  - Ownership and explicit share rows are ordinary field filters, so counting
 *    them is exact regardless of who runs the query.
 *
 * What is not: role-hierarchy access and implicit parent-child sharing do not
 * always materialise as share rows. For a private object the owned-plus-shared
 * figure is therefore a floor, and this class labels it as one. Turning that
 * floor into a total needs UserRecordAccess, 200 records per query, which is a
 * later feature and not pretended at here.
 */
// Complexity is suppressed at class level, not silently tolerated. This class
// is a decision tree over Salesforce's sharing model: public versus private,
// owner versus share row versus View All, object with an owner versus without,
// share table present versus absent. Each branch is a real distinction the
// platform makes, and collapsing them to satisfy a metric would mean guessing
// in cases the product currently answers exactly. The branches live in small,
// individually documented methods instead.
@SuppressWarnings('PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.StdCyclomaticComplexity')
public with sharing class PERecordAccessService {

    /** Objects whose share table is absent or not queryable this way. */
    private static final Set<String> NO_SHARE_TABLE = new Set<String>{
        'User', 'Profile', 'PermissionSet', 'Group', 'UserRole'
    };

    /* ---------------------------------------------------------------
     * Result shape
     * --------------------------------------------------------------- */

    /** Record-level reach for one user against one object. */
    public class Reach {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String objectLabel;

        /** 'Private', 'Read', 'ReadWrite', 'ControlledByParent', 'FullAccess'. */
        @AuraEnabled public String internalSharing;
        @AuraEnabled public String externalSharing;
        /** Plain-language version of internalSharing for the panel heading. */
        @AuraEnabled public String sharingLabel;
        /** True when the OWD lets everyone with object read see every record. */
        @AuraEnabled public Boolean isPublic = false;

        /** Records in the org, as the running user sees them. */
        @AuraEnabled public Integer totalRecords;
        /** Records owned by the selected user. Exact. */
        @AuraEnabled public Integer ownedRecords;
        /** Distinct records shared to the user or a group they belong to. Exact. */
        @AuraEnabled public Integer sharedRecords;
        /** owned + shared, deduplicated where the data allows. */
        @AuraEnabled public Integer reachableRecords;

        /** True when reachableRecords is the complete answer, not a floor. */
        @AuraEnabled public Boolean isExact = false;
        /** Why the figure is exact, or why it is only a floor. */
        @AuraEnabled public String basis;

        /** Set when the user cannot read the object at all. */
        @AuraEnabled public Boolean hasObjectRead = true;
        /** True when View All Records on this object short-circuits sharing. */
        @AuraEnabled public Boolean hasViewAll = false;

        /** Non-fatal explanations: missing share table, unowned object, caps hit. */
        @AuraEnabled public List<String> notes = new List<String>();
    }

    /* ---------------------------------------------------------------
     * Entry point
     * --------------------------------------------------------------- */

    /**
     * Record-level reach for one user and one object.
     *
     * @param userId The user being inspected.
     * @param objectApiName API name of the object to measure.
     * @return Reach figures with an explicit basis for each one.
     */
    public static Reach getReach(Id userId, String objectApiName) {
        Reach r = new Reach();
        r.objectApiName = objectApiName;

        Schema.DescribeSObjectResult d = describe(objectApiName);
        if (d == null) {
            r.hasObjectRead = false;
            r.basis = 'That object is not available in this org.';
            return r;
        }
        r.objectLabel = d.getLabel();

        if (!d.isAccessible()) {
            r.hasObjectRead = false;
            r.basis = 'You cannot read this object, so its records cannot be counted.';
            return r;
        }

        loadSharingModel(r, objectApiName);
        r.totalRecords = countAll(objectApiName, r);

        // View All bypasses sharing for effective access, but share grants
        // remain useful evidence of access that would survive its removal.
        r.hasViewAll = hasViewAllRecords(userId, objectApiName);

        if (r.isPublic || r.hasViewAll) {
            r.reachableRecords = r.totalRecords;
            r.ownedRecords     = countOwned(objectApiName, userId, d, r);
            r.sharedRecords    = countShared(objectApiName, userId, d, r);
            r.isExact          = r.totalRecords != null;
            r.basis = r.hasViewAll
                ? 'Exact. View All Records makes every record reachable; explicit sharing grants are also counted separately.'
                : 'Exact. The org-wide default makes every record visible to anyone with read access.';
            return r;
        }

        r.ownedRecords  = countOwned(objectApiName, userId, d, r);
        r.sharedRecords = countShared(objectApiName, userId, d, r);

        // Distinct across every share row rather than owned + shared. A record
        // can carry both an Owner row and a Manual row, and adding the two
        // buckets counted it twice - which is how a user reaching 2 of 4
        // records was reported as reaching 3.
        Integer distinct = countDistinctShared(objectApiName, userId);
        r.reachableRecords = distinct != null
            ? distinct
            : sumNullable(r.ownedRecords, r.sharedRecords);

        // Deliberately a floor, and said so. Role hierarchy and implicit
        // parent-child sharing do not reliably appear in share tables, so the
        // real figure is at least this and may be higher.
        r.isExact = false;
        r.basis =
            'At least this many. Ownership and explicit sharing are counted exactly; ' +
            'role hierarchy and implicit parent-child sharing are not visible to this count.';
        return r;
    }

    /* ---------------------------------------------------------------
     * Sharing context
     * --------------------------------------------------------------- */

    /** The two facts that decide how a record list has to be driven. */
    public class SharingContext {
        @AuraEnabled public String model;
        /** True when the org-wide default puts every record within reach. */
        @AuraEnabled public Boolean isPublic = false;
        /** True when View All Records bypasses sharing for this user. */
        @AuraEnabled public Boolean hasViewAll = false;
        /** Either of the above means sharing is not what grants access. */
        @AuraEnabled public Boolean sharingBypassed = false;
    }

    /**
     * The cheap half of getReach: the sharing model and whether this user
     * bypasses it.
     *
     * Split out so PERecordListService can decide how to drive a page without
     * paying for the record counts it does not need.
     *
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @return Sharing model plus the two bypass flags.
     */
    public static SharingContext getSharingContext(Id userId, String objectApiName) {
        SharingContext ctx = new SharingContext();
        try {
            List<EntityDefinition> defs = [
                SELECT InternalSharingModel
                FROM EntityDefinition
                WHERE QualifiedApiName = :objectApiName
                WITH USER_MODE
                LIMIT 1
            ];
            if (!defs.isEmpty()) {
                ctx.model = defs[0].InternalSharingModel;
                ctx.isPublic = isPublicModel(ctx.model);
            }
        } catch (Exception e) {
            ctx.model = null;
        }

        ctx.hasViewAll = hasViewAllRecords(userId, objectApiName);
        ctx.sharingBypassed = ctx.isPublic || ctx.hasViewAll;
        return ctx;
    }

    /* ---------------------------------------------------------------
     * Sharing model
     * --------------------------------------------------------------- */

    /**
     * Reads the org-wide default from EntityDefinition.
     *
     * @param r Reach being populated, mutated in place.
     * @param objectApiName API name of the object.
     */
    private static void loadSharingModel(Reach r, String objectApiName) {
        try {
            List<EntityDefinition> defs = [
                SELECT QualifiedApiName, InternalSharingModel, ExternalSharingModel
                FROM EntityDefinition
                WHERE QualifiedApiName = :objectApiName
                WITH USER_MODE
                LIMIT 1
            ];
            if (defs.isEmpty()) {
                r.sharingLabel = 'Unknown';
                r.notes.add('The org-wide default for this object could not be read.');
                return;
            }

            r.internalSharing = defs[0].InternalSharingModel;
            r.externalSharing = defs[0].ExternalSharingModel;
            r.isPublic = isPublicModel(r.internalSharing);
            r.sharingLabel = sharingLabel(r.internalSharing);
        } catch (Exception e) {
            r.sharingLabel = 'Unknown';
            r.notes.add('The org-wide default for this object could not be read.');
        }
    }

    /**
     * Whether a sharing model lets every user with object read see every record.
     *
     * ControlledByParent is deliberately NOT public: access depends on the
     * parent record, which this count cannot resolve.
     *
     * @param model InternalSharingModel value.
     * @return True when the model is public.
     */
    private static Boolean isPublicModel(String model) {
        // ReadWriteTransfer is what EntityDefinition reports for Case and Lead.
        // Omitting it classified those objects as private, which then sent the
        // record list down the share-table path for an object where sharing is
        // not what grants access at all.
        return model == 'Read'
            || model == 'Edit'
            || model == 'ReadWrite'
            || model == 'FullAccess'
            || model == 'ReadWriteTransfer';
    }

    /**
     * Plain-language name for a sharing model.
     *
     * @param model InternalSharingModel value.
     * @return Label an administrator would recognise from Setup.
     */
    private static String sharingLabel(String model) {
        if (model == 'Private') {
            return 'Private';
        }
        if (model == 'Read') {
            return 'Public Read Only';
        }
        if (model == 'Edit' || model == 'ReadWrite') {
            return 'Public Read/Write';
        }
        if (model == 'FullAccess' || model == 'ReadWriteTransfer') {
            return 'Public Read/Write/Transfer';
        }
        if (model == 'ControlledByParent') {
            return 'Controlled by Parent';
        }
        // Falling through to the raw API value is deliberate: an unmapped model
        // reading 'ReadWriteTransfer' in the UI is how this gap was found.
        return model == null ? 'Unknown' : model;
    }

    /* ---------------------------------------------------------------
     * Counts
     * --------------------------------------------------------------- */

    /**
     * Total records, as the running user sees them.
     *
     * This is the denominator and nothing more. An administrator running it
     * gets the org total; a delegated user gets their own slice, which is why
     * the UI labels it by who ran it.
     *
     * @param objectApiName API name of the object.
     * @param r Reach being populated, for notes.
     * @return Record count, or null when the count could not run.
     */
    private static Integer countAll(String objectApiName, Reach r) {
        try {
            return Database.countQueryWithBinds(
                'SELECT COUNT() FROM ' + safeName(objectApiName),
                new Map<String, Object>(),
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            r.notes.add('The total record count could not be read for this object.');
            return null;
        }
    }

    /**
     * Records owned by the selected user.
     *
     * Exact: OwnerId is an ordinary field filter, so the answer does not depend
     * on who runs the query.
     *
     * @param objectApiName API name of the object.
     * @param userId The user being inspected.
     * @param d Describe result for the object.
     * @param r Reach being populated, for notes.
     * @return Owned record count, or null when the object has no owner.
     */
    // Four parameters, each load-bearing: the object to count, the user to count
    // for, the describe that says whether an owner field exists at all, and the
    // Reach that collects the explanation when it does not.
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static Integer countOwned(
        String objectApiName, Id userId, Schema.DescribeSObjectResult d, Reach r
    ) {
        if (!d.fields.getMap().containsKey('OwnerId')) {
            r.notes.add('This object has no owner, so ownership grants nobody access to it.');
            return null;
        }
        try {
            return Database.countQueryWithBinds(
                'SELECT COUNT() FROM ' + safeName(objectApiName) + ' WHERE OwnerId = :userId',
                new Map<String, Object>{ 'userId' => userId },
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            r.notes.add('Records owned by this user could not be counted.');
            return null;
        }
    }

    /**
     * Distinct records reachable through any share row, owner rows included.
     *
     * The honest total for a private object: one COUNT_DISTINCT cannot
     * double-count a record that qualifies under several reasons, where adding
     * the buckets can and did.
     *
     * @param objectApiName API name of the object.
     * @param userId The user being inspected.
     * @return Distinct reachable record count, or null when there is no share table.
     */
    private static Integer countDistinctShared(String objectApiName, Id userId) {
        String shareName = shareObjectName(objectApiName);
        if (NO_SHARE_TABLE.contains(objectApiName)
            || Schema.getGlobalDescribe().get(shareName) == null) {
            return null;
        }
        try {
            Set<Id> holders = accessHolders(userId);
            String parentField = safeShareParentField(shareName, parentFieldName(objectApiName));

            List<AggregateResult> ar = (List<AggregateResult>) Database.queryWithBinds(
                'SELECT COUNT_DISTINCT(' + parentField + ') cnt FROM ' + safeName(shareName) +
                ' WHERE UserOrGroupId IN :holders',
                new Map<String, Object>{ 'holders' => holders },
                AccessLevel.USER_MODE
            );
            return ar.isEmpty() ? 0 : (Integer) ar[0].get('cnt');
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Distinct records shared to the user, directly or through a group.
     *
     * Counts DISTINCT parents rather than share rows: one record can carry
     * several share rows for the same user through different reasons, and
     * counting rows would report more records than exist.
     *
     * @param objectApiName API name of the object.
     * @param userId The user being inspected.
     * @param d Describe result for the object.
     * @param r Reach being populated, for notes.
     * @return Shared record count, or null when there is no share table.
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static Integer countShared(
        String objectApiName, Id userId, Schema.DescribeSObjectResult d, Reach r
    ) {
        if (NO_SHARE_TABLE.contains(objectApiName)) {
            r.notes.add('This object does not use a share table.');
            return null;
        }

        String shareName  = shareObjectName(objectApiName);
        String parentField = parentFieldName(objectApiName);

        if (shareName == null || Schema.getGlobalDescribe().get(shareName) == null) {
            r.notes.add('This object has no share table, so explicit sharing does not apply.');
            return null;
        }

        try {
            Set<Id> holders = accessHolders(userId);

            // Database.query is typed List<SObject>; the cast is required even
            // though the query can only produce aggregate rows.
            // Custom __Share tables carry a RowCause = 'Owner' row for the
            // owner's own records - confirmed against a real org, where a user
            // owning one record and holding one manual share produced two share
            // rows. Counting them here made "shared to user" include records
            // the user owns, and the owned + shared total then counted that
            // record twice.
            // Bound, not escaped into the string. An escaped quote inside a
            // concatenated query is the kind of thing that survives review
            // and then breaks on the one object nobody tested.
            String ownerCause = 'Owner';

            List<AggregateResult> ar = (List<AggregateResult>) Database.queryWithBinds(
                'SELECT COUNT_DISTINCT(' + safeShareParentField(shareName, parentField) +
                ') cnt FROM ' + safeName(shareName) +
                ' WHERE UserOrGroupId IN :holders AND RowCause != :ownerCause',
                new Map<String, Object>{ 'holders' => holders, 'ownerCause' => ownerCause },
                AccessLevel.USER_MODE
            );
            return ar.isEmpty() ? 0 : (Integer) ar[0].get('cnt');
        } catch (Exception e) {
            r.notes.add('Explicit share rows could not be read for this object.');
            return null;
        }
    }

    /* ---------------------------------------------------------------
     * Who counts as "this user" on a share row
     * --------------------------------------------------------------- */

    /**
     * Every Id a share row could name that would grant this user access.
     *
     * A share row points at a user, a public group, a queue, or a role group.
     * Counting only rows naming the user directly would miss most real sharing,
     * so group membership is expanded transitively and the user's role groups
     * are included.
     *
     * Public because PERecordListService needs the same expansion to drive its
     * record list. Two implementations of "who counts as this user on a share
     * row" would drift, and the drift would show up as a count that disagrees
     * with the list beneath it.
     *
     * @param userId The user being inspected.
     * @return User Id plus every group Id that confers access to them.
     */
    public static Set<Id> accessHolders(Id userId) {
        Set<Id> holders = new Set<Id>{ userId };
        holders.addAll(roleGroupsFor(userId));

        // Group membership is transitive, and this previously walked it with a
        // query inside a loop: five round trips in the worst case, and an
        // unbounded appetite for the query limit if the depth cap ever moved.
        // The membership graph is now read once and traversed in memory, which
        // is both a single query and faster.
        Map<Id, Set<Id>> parentsByMember = membershipGraph();

        Set<Id> frontier = new Set<Id>(holders);
        while (!frontier.isEmpty()) {
            Set<Id> found = new Set<Id>();
            for (Id member : frontier) {
                Set<Id> parents = parentsByMember.get(member);
                if (parents == null) {
                    continue;
                }
                for (Id parentId : parents) {
                    if (!holders.contains(parentId)) {
                        found.add(parentId);
                    }
                }
            }
            holders.addAll(found);
            frontier = found;
        }

        return holders;
    }

    /**
     * Groups that stand for this user's role.
     *
     * A share row names the role group, never the role itself, so the role has
     * to be resolved into its groups before share rows mean anything.
     *
     * @param userId The user being inspected.
     * @return Group Ids representing the user's role; empty when unreadable.
     */
    private static Set<Id> roleGroupsFor(Id userId) {
        Set<Id> out = new Set<Id>();
        try {
            List<User> users = [
                SELECT UserRoleId FROM User WHERE Id = :userId WITH USER_MODE LIMIT 1
            ];
            if (users.isEmpty() || users[0].UserRoleId == null) {
                return out;
            }
            Id roleId = users[0].UserRoleId;
            for (Group g : [
                SELECT Id FROM Group WHERE RelatedId = :roleId WITH USER_MODE
            ]) {
                out.add(g.Id);
            }
        } catch (Exception e) {
            // Direct and group shares still count without this. A user whose
            // role cannot be read simply reaches fewer records through sharing,
            // which understates access rather than overstating it.
            return new Set<Id>();
        }
        return out;
    }

    /**
     * The org's group membership graph: member Id to the groups containing it.
     *
     * One query, traversed in memory by the caller. Capped deliberately: a graph
     * larger than this means something pathological, and a truncated graph
     * understates reach rather than inventing it.
     *
     * @return Containing group Ids keyed by member Id.
     */
    @SuppressWarnings('PMD.AvoidNonRestrictiveQueries')
    private static Map<Id, Set<Id>> membershipGraph() {
        Map<Id, Set<Id>> out = new Map<Id, Set<Id>>();
        try {
            for (GroupMember gm : [
                SELECT GroupId, UserOrGroupId FROM GroupMember
                WITH USER_MODE
                LIMIT 50000
            ]) {
                Set<Id> parents = out.get(gm.UserOrGroupId);
                if (parents == null) {
                    parents = new Set<Id>();
                    out.put(gm.UserOrGroupId, parents);
                }
                parents.add(gm.GroupId);
            }
        } catch (Exception e) {
            return new Map<Id, Set<Id>>();
        }
        return out;
    }

    /**
     * Whether the user holds View All Records on this object through any route.
     *
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @return True when View All applies, which bypasses sharing entirely.
     */
    private static Boolean hasViewAllRecords(Id userId, String objectApiName) {
        try {
            PEPermissionResolver.Resolved res = PEPermissionResolver.resolve(userId);
            if (res == null || res.effectiveParents.isEmpty()) {
                return false;
            }
            Set<Id> parents = res.effectiveParents;

            List<ObjectPermissions> perms = [
                SELECT Id FROM ObjectPermissions
                WHERE ParentId IN :parents
                  AND SobjectType = :objectApiName
                  AND PermissionsViewAllRecords = true
                WITH USER_MODE
                LIMIT 1
            ];
            return !perms.isEmpty();
        } catch (Exception e) {
            // Unknown is reported as false: claiming View All the user may not
            // have would overstate their reach, which is the wrong error.
            return false;
        }
    }

    /* ---------------------------------------------------------------
     * Helpers
     * --------------------------------------------------------------- */

    /**
     * Describe for an object, or null when the name does not resolve.
     *
     * @param objectApiName API name of the object.
     * @return Describe result, or null.
     */
    private static Schema.DescribeSObjectResult describe(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return null;
        }
        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApiName);
        return t == null ? null : t.getDescribe();
    }

    /**
     * Share table name for an object.
     *
     * Custom objects replace the __c suffix with __Share; standard objects
     * append Share.
     *
     * @param objectApiName API name of the object.
     * @return Share object API name.
     */
    private static String shareObjectName(String objectApiName) {
        return objectApiName.endsWith('__c')
            ? objectApiName.removeEnd('__c') + '__Share'
            : objectApiName + 'Share';
    }

    /**
     * Name of the field on the share table pointing at the shared record.
     *
     * Custom share tables use ParentId; standard ones name the object.
     *
     * @param objectApiName API name of the object.
     * @return Parent field API name.
     */
    private static String parentFieldName(String objectApiName) {
        return objectApiName.endsWith('__c') ? 'ParentId' : objectApiName + 'Id';
    }

    /**
     * Name of the access-level field on the share table.
     *
     * Custom share tables call it AccessLevel. Standard ones prefix the object:
     * CaseShare.CaseAccessLevel, AccountShare.AccountAccessLevel. Querying the
     * unprefixed name against a standard share table throws, which is what
     * emptied the record list on every standard object.
     *
     * @param objectApiName API name of the object.
     * @return Access level field API name.
     */
    public static String accessLevelFieldName(String objectApiName) {
        return objectApiName.endsWith('__c')
            ? 'AccessLevel'
            : objectApiName + 'AccessLevel';
    }

    /**
     * Guards an object name before it reaches a dynamic query.
     *
     * The names come from describe, not from the user, but a dynamic query
     * built from anything deserves the check at the boundary rather than an
     * argument about where the value originated.
     *
     * @param name Object API name.
     * @return The name, unchanged, when it is a plain identifier.
     */
    private static String safeName(String name) {
        if (!Pattern.matches('^[A-Za-z0-9_]+$', name)) {
            throw new PermissionExplorerException('Unsupported object name: ' + name);
        }
        return name;
    }

    /**
     * Validates an identifier derived from describe before it reaches SOQL.
     *
     * Bind variables cannot represent a field or object identifier, so the name
     * is checked against the share table's own describe rather than trusted.
     *
     * @param shareName API name of the share object.
     * @param parentField Candidate parent field name on that share object.
     * @return The field name, unchanged, when the share object really has it.
     */
    private static String safeShareParentField(String shareName, String parentField) {
        Schema.SObjectType shareType = Schema.getGlobalDescribe().get(shareName);
        if (shareType == null || String.isBlank(parentField) ||
            !shareType.getDescribe().fields.getMap().containsKey(parentField)) {
            throw new PermissionExplorerException('Unsupported share parent field.');
        }
        return safeName(parentField);
    }

    /**
     * Adds two counts, treating null as absent rather than zero.
     *
     * @param a First count, possibly null.
     * @param b Second count, possibly null.
     * @return Their sum, or null when both are absent.
     */
    private static Integer sumNullable(Integer a, Integer b) {
        if (a == null && b == null) {
            return null;
        }
        return (a == null ? 0 : a) + (b == null ? 0 : b);
    }
}
