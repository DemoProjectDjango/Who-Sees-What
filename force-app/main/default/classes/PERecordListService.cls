/**
 * The record list behind Data Visibility: which records a user reaches, why,
 * and what they can do to each one.
 *
 * One list with a filter, not two modes. The earlier two-mode design existed
 * because I thought a filtered list could not report a true total - that if you
 * fetched 200 records and found 12 reachable, the footer could only honestly
 * say "12 on this page". That was wrong. The total comes from its own query and
 * has nothing to do with which page is on screen, so the footer can always say
 * something true: "Showing 200 of 3,412 reachable".
 *
 * How a page is driven depends on where the access comes from:
 *
 *  - Sharing bypassed (public org-wide default, or the user holds View All):
 *    the page is driven from the object and the total is a COUNT() less the
 *    carve-outs a public default does not cover. Search and sort work. Under
 *    the filter, rows the user cannot read are dropped using the per-record
 *    access this page already fetches - the checkbox used to be a no-op here,
 *    which is how a record with three greyed access chips sat inside a list
 *    headed "only records this user can reach".
 *  - Private, reachable-only: driven from the share table, so every row
 *    returned is genuinely reachable and the total is an exact COUNT_DISTINCT.
 *    The record's own name cannot be searched, because the driving query is
 *    over share rows.
 *  - Private, showing everything: driven from the object, each row annotated
 *    with the user's real access. Search and sort work.
 *
 * The one gap that remains, and the only place the phrase "at least" belongs:
 * a private record reachable solely through role hierarchy has no share row, so
 * it is absent from the share-based total. Per record the ladder still catches
 * it - UserRecordAccess sees hierarchy - which is why the Reason column can say
 * so even when the count cannot.
 */
// Complexity suppressed at class level with the same reasoning as
// PERecordAccessService: this is a decision tree over how a page can be driven
// (share table versus object), what the object supports (name field, owner
// field, share table), and where each row's access comes from. Every branch is
// a real distinction, and the alternative to branching is guessing.
@SuppressWarnings('PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.StdCyclomaticComplexity,PMD.NcssTypeCount')
public with sharing class PERecordListService {

    /** UserRecordAccess accepts at most 200 record Ids per query, so the page
     *  size is set by the platform rather than chosen. */
    private static final Integer PAGE_SIZE = 200;

    /** Share rows read per page before de-duplication. A record can carry
     *  several share rows, so this is deliberately larger than PAGE_SIZE. */
    private static final Integer SHARE_SCAN = 1000;

    private static final Set<String> SORTABLE =
        new Set<String>{ 'Name', 'CreatedDate', 'LastModifiedDate', 'Id' };

    /* Reason codes. The first four come from RowCause; the last two are this
       class's own, and are labelled as derived rather than reported. */
    private static final String REASON_OWD       = 'OrgWideDefault';
    private static final String REASON_VIEW_ALL  = 'ViewAllRecords';
    private static final String REASON_INFERRED  = 'HierarchyOrImplicit';

    /* ---------------------------------------------------------------
     * Result shape
     * --------------------------------------------------------------- */

    /** One record, with the selected user's access to it. */
    public class RecordRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String label;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Boolean ownedByUser = false;
        /** Owner, Manual, Rule, Team, Territory, OrgWideDefault,
         *  ViewAllRecords, or HierarchyOrImplicit. */
        @AuraEnabled public String reason;
        /** True when the reason was deduced rather than read from a share row. */
        @AuraEnabled public Boolean reasonInferred = false;
        @AuraEnabled public Boolean canRead = false;
        @AuraEnabled public Boolean canEdit = false;
        @AuraEnabled public Boolean canDelete = false;
        /** True when object permissions allow delete but the record does not. */
        @AuraEnabled public Boolean deleteBlockedByRecord = false;
        @AuraEnabled public Datetime createdDate;
    }

    /** One page of records. */
    public class RecordPage {
        @AuraEnabled public List<RecordRow> rows = new List<RecordRow>();
        @AuraEnabled public String nextCursor;
        @AuraEnabled public Boolean hasMore = false;

        /** Records this user reaches. Exact, from its own query. */
        @AuraEnabled public Integer totalReachable;
        /** Records in the object the running user can see. */
        @AuraEnabled public Integer totalRecords;
        /** True when totalReachable counts share rows only, so hierarchy access
         *  is missing from it and the figure is a floor. */
        @AuraEnabled public Boolean totalIsFloor = false;

        @AuraEnabled public Boolean reachableOnly = true;
        @AuraEnabled public Boolean sharingBypassed = false;
        @AuraEnabled public Boolean hasNameField = true;
        @AuraEnabled public Boolean searchSupported = true;
        /** False when every row would carry the same reason, so the column is
         *  noise rather than information. */
        @AuraEnabled public Boolean showReason = true;
        /** Set when the whole object shares one reason, for the line above the table. */
        @AuraEnabled public String uniformReason;
        @AuraEnabled public List<String> notes = new List<String>();
    }

    /** One bucket of the share breakdown. */
    public class ReasonBucket {
        @AuraEnabled public String reason;
        @AuraEnabled public String accessLevel;
        @AuraEnabled public Integer total;
    }

    /* ---------------------------------------------------------------
     * Record page
     * --------------------------------------------------------------- */

    /**
     * One page of records with the selected user's access to each.
     *
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @param reachableOnly True to list only records the user reaches.
     * @param searchTerm Free text; ignored when the page is share-driven.
     * @param sortField Name, CreatedDate, LastModifiedDate or Id.
     * @param cursor Opaque cursor from the previous page, or null to start.
     * @return A page of rows plus the cursor for the next one.
     */
    // The parameter list mirrors the controls the panel exposes; folding it into
    // a wrapper would hide which knobs exist from the caller. reachableOnly is a
    // Boolean because it is one checkbox with two states, and an enum of two
    // values would be ceremony around a switch.
    @SuppressWarnings('PMD.ExcessiveParameterList,PMD.AvoidBooleanMethodParameters')
    public static RecordPage getPage(
        Id userId,
        String objectApiName,
        Boolean reachableOnly,
        String searchTerm,
        String sortField,
        String cursor
    ) {
        RecordPage page = new RecordPage();
        page.reachableOnly = reachableOnly != false;

        Schema.DescribeSObjectResult d = describe(objectApiName);
        if (d == null || !d.isAccessible()) {
            page.notes.add('This object cannot be read by your user.');
            return page;
        }

        page.hasNameField = nameFieldOf(d) != null;
        if (!page.hasNameField) {
            page.notes.add('This object has no name field, so records are listed by Id.');
        }

        PERecordAccessService.SharingContext ctx =
            PERecordAccessService.getSharingContext(userId, objectApiName);
        page.sharingBypassed = ctx.sharingBypassed;

        fillTotals(page, userId, objectApiName, ctx);
        decideReasonColumn(page, ctx);

        // Share-driven only when sharing is actually what grants access AND the
        // caller wants the reachable set. Everywhere else the object drives, so
        // search and sort keep working.
        Boolean shareDriven = page.reachableOnly && !ctx.sharingBypassed;

        return shareDriven
            ? sharePage(page, userId, objectApiName, d, cursor)
            : objectPage(page, userId, objectApiName, d, ctx, searchTerm, sortField, cursor);
    }

    /**
     * The two totals, each from its own query and neither derived from a page.
     *
     * @param page Page under construction.
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @param ctx Sharing context for the object.
     */
    // Four parameters: the page to fill, the user and object the totals are
    // about, and the sharing context that decides which of the two totals is
    // even meaningful. Re-deriving the context here would mean a second
    // EntityDefinition query per page.
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static void fillTotals(
        RecordPage page, Id userId, String objectApiName,
        PERecordAccessService.SharingContext ctx
    ) {
        page.totalRecords = countAll(objectApiName, page);

        if (ctx.sharingBypassed) {
            // Everyone with object read reaches everything the platform does
            // not carve out, so the reachable total is the record total less
            // the carve-out, and is still exact.
            page.totalReachable = page.totalRecords;
            page.totalIsFloor = false;

            if (page.totalRecords != null && ctx.owdUnreachable != null) {
                page.totalReachable = page.totalRecords - ctx.owdUnreachable;
            } else if (ctx.owdCarveOutApplies == true && ctx.owdUnreachable == null) {
                page.notes.add(
                    'Some records here stay out of reach despite the public org-wide ' +
                    'default, and how many could not be read, so the reachable total ' +
                    'may be lower than shown.'
                );
            }
            return;
        }

        Integer viaShares = countDistinctShares(objectApiName, userId);
        page.totalReachable = viaShares;
        // Hierarchy and implicit sharing leave no share row, so this is a floor.
        // It is the only figure in the product that carries that caveat.
        page.totalIsFloor = viaShares != null;
    }

    /**
     * Decides whether the Reason column says anything worth a column.
     *
     * On a public object every row would read "Org-wide default", which is a
     * fact about the object, not about the record. It belongs in one line above
     * the table rather than fifty thousand times inside it.
     *
     * @param page Page under construction.
     * @param ctx Sharing context for the object.
     */
    private static void decideReasonColumn(
        RecordPage page, PERecordAccessService.SharingContext ctx
    ) {
        // With View All, record-specific sharing remains relevant: a manual
        // share can keep granting access after View All is removed.
        if (ctx.hasViewAll) {
            page.showReason = true;
            page.uniformReason = 'Every record is reachable through View All Records. ' +
                'The Reason column also shows existing ownership or sharing grants.';
            return;
        }
        if (!ctx.sharingBypassed) {
            page.showReason = true;
            return;
        }
        page.showReason = false;
        page.uniformReason = String.isNotBlank(ctx.owdCarveOutNote)
            ? ctx.owdCarveOutNote
            : 'Every record is reachable through the org-wide default.';
    }

    /* ---------------------------------------------------------------
     * Share-driven page
     * --------------------------------------------------------------- */

    /**
     * Driven from the share table, so every row is genuinely reachable.
     *
     * @param page Page under construction.
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @param d Describe result for the object.
     * @param cursor Last record Id from the previous page, or null.
     * @return The populated page.
     */
    @SuppressWarnings('PMD.ExcessiveParameterList,PMD.NcssMethodCount,PMD.CyclomaticComplexity,PMD.StdCyclomaticComplexity,PMD.NcssCount')
    private static RecordPage sharePage(
        RecordPage page, Id userId, String objectApiName,
        Schema.DescribeSObjectResult d, String cursor
    ) {
        page.searchSupported = false;

        String shareName = shareObjectName(objectApiName);
        if (!objectExists(shareName)) {
            page.notes.add(
                'This object has no share table, so there is no per-record sharing to list.'
            );
            return page;
        }

        try {
            Set<Id> holders = PERecordAccessService.accessHolders(userId);
            String parentField = parentFieldName(objectApiName);
            String lvlField = PERecordAccessService.accessLevelFieldName(objectApiName);
            Id after = String.isBlank(cursor) ? null : (Id) cursor;
            Integer scan = SHARE_SCAN;

            String q =
                'SELECT ' + parentField + ', RowCause, ' + lvlField + ' ' +
                'FROM ' + shareName + ' WHERE UserOrGroupId IN :holders ';
            if (after != null) {
                q += 'AND ' + parentField + ' > :after ';
            }
            q += 'ORDER BY ' + parentField + ' ASC LIMIT :scan';

            Map<Id, ReasonBucket> best = new Map<Id, ReasonBucket>();
            for (SObject sh : Database.queryWithBinds(q, new Map<String, Object>{
                'holders' => holders, 'after' => after, 'scan' => scan
            }, AccessLevel.USER_MODE)) {
                Id pid = (Id) sh.get(parentField);
                ReasonBucket b = new ReasonBucket();
                b.reason      = (String) sh.get('RowCause');
                b.accessLevel = (String) sh.get(lvlField);

                // A record can carry several share rows. Keep the strongest, so
                // the row shows what the user can actually do rather than
                // whichever reason happened to sort first.
                ReasonBucket existing = best.get(pid);
                if (existing == null || rank(b.accessLevel) > rank(existing.accessLevel)) {
                    best.put(pid, b);
                }
            }

            List<Id> ids = new List<Id>(best.keySet());
            ids.sort();

            Boolean more = ids.size() > PAGE_SIZE;
            if (more) {
                List<Id> trimmed = new List<Id>();
                for (Integer i = 0; i < PAGE_SIZE; i++) {
                    trimmed.add(ids[i]);
                }
                ids = trimmed;
            }
            page.hasMore = more;
            page.nextCursor = ids.isEmpty() || !more
                ? null
                : String.valueOf(ids[ids.size() - 1]);

            Map<Id, SObject> byId = fetchRecords(objectApiName, d, ids);
            buildRows(page, userId, d, ids, byId, nameFieldOf(d), best, null);
        } catch (Exception e) {
            page.notes.add('Shared records could not be listed for this object.');
        }
        return page;
    }

    /* ---------------------------------------------------------------
     * Object-driven page
     * --------------------------------------------------------------- */

    /**
     * Driven from the object, so search and sort are native and fast.
     *
     * @param page Page under construction.
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @param d Describe result for the object.
     * @param ctx Sharing context for the object.
     * @param searchTerm Free text to match against the name field.
     * @param sortField Field to order by.
     * @param cursor Last record Id from the previous page, or null.
     * @return The populated page.
     */
    @SuppressWarnings('PMD.ExcessiveParameterList,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.StdCyclomaticComplexity')
    private static RecordPage objectPage(
        RecordPage page, Id userId, String objectApiName,
        Schema.DescribeSObjectResult d, PERecordAccessService.SharingContext ctx,
        String searchTerm, String sortField, String cursor
    ) {
        String nameField = nameFieldOf(d);
        String sortBy = SORTABLE.contains(sortField) ? sortField : 'Id';
        if (sortBy == 'Name' && nameField == null) {
            sortBy = 'Id';
        }
        page.searchSupported = nameField != null;

        try {
            Id after = String.isBlank(cursor) ? null : (Id) cursor;
            String term = String.isBlank(searchTerm) ? null : '%' + searchTerm.trim() + '%';
            Integer lim = PAGE_SIZE + 1;

            String q = 'SELECT ' + String.join(selectFields(d, nameField), ', ') +
                       ' FROM ' + safeName(objectApiName) + ' WHERE Id != null';
            if (term != null && nameField != null) {
                q += ' AND ' + nameField + ' LIKE :term';
            }
            if (after != null) {
                q += ' AND Id > :after';
            }
            // Id is the tiebreaker on every sort, so the keyset cursor is always
            // unambiguous even when the sorted field repeats.
            q += ' ORDER BY ' + sortBy + (sortBy == 'Id' ? '' : ', Id') + ' ASC LIMIT :lim';

            List<SObject> records = Database.queryWithBinds(q, new Map<String, Object>{
                'term' => term, 'after' => after, 'lim' => lim
            }, AccessLevel.USER_MODE);

            page.hasMore = records.size() > PAGE_SIZE;
            if (page.hasMore) {
                records.remove(PAGE_SIZE);
            }
            page.nextCursor = records.isEmpty() || !page.hasMore
                ? null
                : String.valueOf(records[records.size() - 1].Id);

            List<Id> ids = new List<Id>();
            Map<Id, SObject> byId = new Map<Id, SObject>();
            for (SObject s : records) {
                ids.add((Id) s.get('Id'));
                byId.put((Id) s.get('Id'), s);
            }

            // One extra query per page fills the Reason column for records that
            // have a share row. Bounded at 200 ids, same as the access query.
            Map<Id, ReasonBucket> shares = ctx.sharingBypassed && !ctx.hasViewAll
                ? new Map<Id, ReasonBucket>()
                : sharesFor(objectApiName, userId, ids);

            buildRows(page, userId, d, ids, byId, nameField, shares, ctx);
        } catch (Exception e) {
            page.notes.add('Records could not be listed for this object.');
        }
        return page;
    }

    /* ---------------------------------------------------------------
     * Row assembly
     * --------------------------------------------------------------- */

    /**
     * Turns fetched records into rows and annotates each with the user's access.
     *
     * One UserRecordAccess query covers the whole page, because the page size
     * and the UserRecordAccess cap are the same number by design.
     *
     * @param page Page under construction.
     * @param userId The user being inspected.
     * @param d Describe result for the object.
     * @param ids Record Ids in display order.
     * @param byId Fetched records keyed by Id.
     * @param nameField Name field API name, or null.
     * @param shares Share reason per record, keyed by record Id.
     * @param ctx Sharing context, or null on a share-driven page.
     */
    @SuppressWarnings('PMD.ExcessiveParameterList,PMD.CognitiveComplexity,PMD.CyclomaticComplexity,PMD.StdCyclomaticComplexity')
    private static void buildRows(
        RecordPage page, Id userId, Schema.DescribeSObjectResult d,
        List<Id> ids, Map<Id, SObject> byId, String nameField,
        Map<Id, ReasonBucket> shares, PERecordAccessService.SharingContext ctx
    ) {
        if (ids.isEmpty()) {
            return;
        }
        AccessLookup access = accessFor(userId, ids);
        Boolean objectDeletable = d.isDeletable();
        Boolean hasOwner = d.fields.getMap().containsKey('OwnerId');
        Boolean hasCreated = d.fields.getMap().containsKey('CreatedDate');

        // ctx is set only on the object-driven page, and that is the only page
        // the filter has to enforce: every row on a share-driven page came from
        // a share row, so it is reachable by construction. Without resolved
        // access there is nothing to filter on, and dropping every row because
        // a permission is missing would be worse than listing them.
        Boolean filtering = ctx != null && page.reachableOnly == true && access.resolved;
        Integer outOfReach = 0;

        for (Id rid : ids) {
            SObject s = byId.get(rid);
            if (s == null) {
                continue;
            }

            RecordRow row = new RecordRow();
            row.recordId = rid;
            row.label = nameField == null
                ? String.valueOf(rid)
                : String.valueOf(s.get(nameField));

            if (hasOwner) {
                row.ownedByUser = s.get('OwnerId') == userId;
                SObject owner = s.getSObject('Owner');
                row.ownerName = owner == null ? null : String.valueOf(owner.get('Name'));
            }
            if (hasCreated) {
                row.createdDate = (Datetime) s.get('CreatedDate');
            }

            UserRecordAccess ura = access.byId.get(rid);
            if (ura != null) {
                row.canRead   = ura.HasReadAccess;
                row.canEdit   = ura.HasEditAccess;
                row.canDelete = ura.HasDeleteAccess;
            }

            if (access.resolved && !row.canRead) {
                outOfReach++;
            }
            if (filtering && !row.canRead) {
                continue;
            }

            assignReason(row, shares == null ? null : shares.get(rid), ctx);

            // The contradiction worth surfacing: object permissions allow
            // delete, the record does not. A manual share can only grant Read
            // or Read/Write, so this is the normal state for shared records and
            // is invisible anywhere in Setup.
            row.deleteBlockedByRecord = objectDeletable && row.canRead && !row.canDelete;

            page.rows.add(row);
        }

        noteUnreachable(page, ctx, access.resolved, outOfReach);
    }

    /**
     * Explains, once per page, whatever the counters could not.
     *
     * Two cases, both worth saying out loud rather than papering over. The
     * per-record access could not be read, so the filter could not be applied
     * and the list is wider than it claims. Or the default is public, records
     * are still out of reach, and no carve-out on record explains them - a
     * restriction rule is the usual answer and it cannot be read from Apex, so
     * the total is a ceiling and the panel should not pretend otherwise.
     *
     * @param page Page under construction, mutated in place.
     * @param ctx Sharing context, or null on a share-driven page.
     * @param accessResolved True when per-record access was actually read.
     * @param outOfReach Rows on this page the user cannot read.
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static void noteUnreachable(
        RecordPage page, PERecordAccessService.SharingContext ctx,
        Boolean accessResolved, Integer outOfReach
    ) {
        if (ctx == null) {
            return;
        }
        if (page.reachableOnly == true && !accessResolved) {
            page.notes.add(
                'The access this user has to individual records could not be read, so ' +
                'every record in scope is listed rather than only the ones they reach.'
            );
            return;
        }
        if (outOfReach > 0 && ctx.sharingBypassed == true
            && ctx.owdCarveOutApplies != true && ctx.hasViewAll != true) {
            page.notes.add(
                'Some records on this page are out of reach for this user even though ' +
                'the org-wide default is public. A restriction rule is the usual cause ' +
                'and it cannot be read from here, so the reachable total may be lower.'
            );
        }
    }

    /**
     * Works out why this user reaches this record, in order of certainty.
     *
     * Owner and share rows are facts. The last rung is a deduction: not the
     * owner, no share row, org-wide default is private, and yet the platform
     * reports read access - so it can only be role hierarchy, implicit
     * parent-child sharing, or Apex-managed sharing. Which of the three is not
     * knowable from here, so the row says it was inferred rather than naming
     * one.
     *
     * @param row Row being populated, mutated in place.
     * @param share Share bucket for this record, or null.
     * @param ctx Sharing context, or null on a share-driven page.
     */
    private static void assignReason(
        RecordRow row, ReasonBucket share, PERecordAccessService.SharingContext ctx
    ) {
        if (row.ownedByUser) {
            row.reason = 'Owner';
            return;
        }
        if (share != null) {
            row.reason = share.reason;
            return;
        }
        if (ctx == null || !row.canRead) {
            return;
        }
        if (ctx.hasViewAll) {
            row.reason = REASON_VIEW_ALL;
            return;
        }
        if (ctx.isPublic) {
            row.reason = REASON_OWD;
            return;
        }
        row.reason = REASON_INFERRED;
        row.reasonInferred = true;
    }

    /* ---------------------------------------------------------------
     * Queries
     * --------------------------------------------------------------- */

    /**
     * Share rows for a page of records, strongest per record.
     *
     * @param objectApiName API name of the object.
     * @param userId The user being inspected.
     * @param ids Record Ids on this page.
     * @return Strongest share bucket per record Id.
     */
    private static Map<Id, ReasonBucket> sharesFor(
        String objectApiName, Id userId, List<Id> ids
    ) {
        Map<Id, ReasonBucket> out = new Map<Id, ReasonBucket>();
        String shareName = shareObjectName(objectApiName);
        if (ids.isEmpty() || !objectExists(shareName)) {
            return out;
        }
        try {
            Set<Id> holders = PERecordAccessService.accessHolders(userId);
            String parentField = parentFieldName(objectApiName);
            String lvlField = PERecordAccessService.accessLevelFieldName(objectApiName);

            for (SObject sh : Database.queryWithBinds(
                'SELECT ' + parentField + ', RowCause, ' + lvlField + ' FROM ' + shareName +
                ' WHERE UserOrGroupId IN :holders AND ' + parentField + ' IN :ids',
                new Map<String, Object>{ 'holders' => holders, 'ids' => ids },
                AccessLevel.USER_MODE
            )) {
                Id pid = (Id) sh.get(parentField);
                ReasonBucket b = new ReasonBucket();
                b.reason      = (String) sh.get('RowCause');
                b.accessLevel = (String) sh.get(lvlField);

                ReasonBucket existing = out.get(pid);
                if (existing == null || rank(b.accessLevel) > rank(existing.accessLevel)) {
                    out.put(pid, b);
                }
            }
        } catch (Exception e) {
            // No reasons rather than wrong ones. The access chips are still
            // exact, which is the load-bearing part of the row.
            return new Map<Id, ReasonBucket>();
        }
        return out;
    }

    /**
     * Distinct records reachable through any share row.
     *
     * @param objectApiName API name of the object.
     * @param userId The user being inspected.
     * @return Distinct reachable record count, or null when unreadable.
     */
    private static Integer countDistinctShares(String objectApiName, Id userId) {
        String shareName = shareObjectName(objectApiName);
        if (!objectExists(shareName)) {
            return null;
        }
        try {
            Set<Id> holders = PERecordAccessService.accessHolders(userId);
            String parentField = parentFieldName(objectApiName);

            List<AggregateResult> ar = (List<AggregateResult>) Database.queryWithBinds(
                'SELECT COUNT_DISTINCT(' + parentField + ') cnt FROM ' + shareName +
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
     * Total records in the object, as the running user sees them.
     *
     * @param objectApiName API name of the object.
     * @param page Page under construction, for notes.
     * @return Record count, or null when the count could not run.
     */
    @SuppressWarnings('PMD.AvoidNonRestrictiveQueries')
    private static Integer countAll(String objectApiName, RecordPage page) {
        try {
            return Database.countQueryWithBinds(
                'SELECT COUNT() FROM ' + safeName(objectApiName),
                new Map<String, Object>(), AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            page.notes.add('The total record count could not be read for this object.');
            return null;
        }
    }

    /**
     * Fetches the display fields for a set of record Ids.
     *
     * @param objectApiName API name of the object.
     * @param d Describe result for the object.
     * @param ids Record Ids to fetch.
     * @return Records keyed by Id.
     */
    private static Map<Id, SObject> fetchRecords(
        String objectApiName, Schema.DescribeSObjectResult d, List<Id> ids
    ) {
        if (ids.isEmpty()) {
            return new Map<Id, SObject>();
        }
        return new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT ' + String.join(selectFields(d, nameFieldOf(d)), ', ') +
                ' FROM ' + safeName(objectApiName) + ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        );
    }

    /**
     * The display fields that exist on this object.
     *
     * @param d Describe result for the object.
     * @param nameField Name field API name, or null.
     * @return Field API names safe to select.
     */
    private static List<String> selectFields(
        Schema.DescribeSObjectResult d, String nameField
    ) {
        List<String> fields = new List<String>{ 'Id' };
        if (nameField != null) {
            fields.add(nameField);
        }
        if (d.fields.getMap().containsKey('OwnerId')) {
            fields.add('OwnerId');
            fields.add('Owner.Name');
        }
        if (d.fields.getMap().containsKey('CreatedDate')) {
            fields.add('CreatedDate');
        }
        return fields;
    }

    /** A page of per-record access, and whether it was actually read. */
    private class AccessLookup {
        /** True only when the access query ran and returned something. */
        private Boolean resolved = false;
        /** Access rows keyed by record Id; empty when unresolved. */
        private Map<Id, UserRecordAccess> byId = new Map<Id, UserRecordAccess>();
    }

    /**
     * The selected user's access to a page of records.
     *
     * UserRecordAccess is the only object that answers for another user, and it
     * is the only thing here that sees role hierarchy and implicit sharing.
     *
     * The resolved flag exists because an empty result cannot be told apart
     * from a query that returned nothing for want of permission, and the
     * difference decides whether the filter may drop a row. Unknown access
     * widens the list and says so; it never silently empties it.
     *
     * @param userId The user being inspected.
     * @param ids Record Ids, at most 200.
     * @return Access rows plus the flag saying whether they mean anything.
     */
    private static AccessLookup accessFor(Id userId, List<Id> ids) {
        AccessLookup out = new AccessLookup();
        if (ids.isEmpty()) {
            return out;
        }
        // Preserve the selected-user access query while explicitly checking
        // object read permission before querying this platform object.
        if (!Schema.sObjectType.UserRecordAccess.isAccessible()) {
            return out;
        }
        try {
            for (UserRecordAccess a : [
                SELECT RecordId, HasReadAccess, HasEditAccess, HasDeleteAccess, MaxAccessLevel
                FROM UserRecordAccess
                WHERE UserId = :userId AND RecordId IN :ids
            ]) {
                out.byId.put(a.RecordId, a);
            }
            out.resolved = !out.byId.isEmpty();
        } catch (Exception e) {
            // Querying another user's access needs elevated permission. Without
            // it the rows still list, with the access chips blank rather than
            // wrong - absent is recoverable, false is a lie.
            return new AccessLookup();
        }
        return out;
    }

    /* ---------------------------------------------------------------
     * Share breakdown
     * --------------------------------------------------------------- */

    /**
     * Why the user reaches what they reach, grouped by share reason.
     *
     * Not used by the current panel, which shows the reason per row instead.
     * Kept because it is still the cheapest way to get the split without
     * reading every record, for any summary view that needs it later.
     *
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @return Buckets ordered by size, largest first.
     */
    public static List<ReasonBucket> getReasonBreakdown(Id userId, String objectApiName) {
        List<ReasonBucket> out = new List<ReasonBucket>();
        String shareName = shareObjectName(objectApiName);
        if (!objectExists(shareName)) {
            return out;
        }

        try {
            Set<Id> holders = PERecordAccessService.accessHolders(userId);
            String parentField = parentFieldName(objectApiName);
            String lvlField = PERecordAccessService.accessLevelFieldName(objectApiName);

            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT RowCause cause, ' + lvlField + ' lvl, COUNT_DISTINCT(' + parentField + ') cnt ' +
                'FROM ' + shareName + ' WHERE UserOrGroupId IN :holders ' +
                'GROUP BY RowCause, ' + lvlField +
                ' ORDER BY COUNT_DISTINCT(' + parentField + ') DESC',
                new Map<String, Object>{ 'holders' => holders },
                AccessLevel.USER_MODE
            )) {
                ReasonBucket b = new ReasonBucket();
                b.reason      = (String) ar.get('cause');
                b.accessLevel = (String) ar.get('lvl');
                b.total       = (Integer) ar.get('cnt');
                out.add(b);
            }
        } catch (Exception e) {
            return new List<ReasonBucket>();
        }
        return out;
    }

    /* ---------------------------------------------------------------
     * Helpers
     * --------------------------------------------------------------- */

    /**
     * Ranks an AccessLevel so the strongest share row wins per record.
     *
     * @param level AccessLevel value from a share row.
     * @return Higher is stronger.
     */
    private static Integer rank(String level) {
        if (level == 'All') {
            return 3;
        }
        if (level == 'Edit') {
            return 2;
        }
        if (level == 'Read') {
            return 1;
        }
        return 0;
    }

    /**
     * The object's name field, or null when it has none.
     *
     * @param d Describe result for the object.
     * @return Name field API name, or null.
     */
    private static String nameFieldOf(Schema.DescribeSObjectResult d) {
        for (Schema.SObjectField f : d.fields.getMap().values()) {
            Schema.DescribeFieldResult fd = f.getDescribe();
            if (fd.isNameField() && fd.isAccessible()) {
                return fd.getName();
            }
        }
        return null;
    }

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
     * Whether an object exists in this org.
     *
     * @param apiName API name to look up.
     * @return True when the type resolves.
     */
    private static Boolean objectExists(String apiName) {
        return apiName != null && Schema.getGlobalDescribe().get(apiName) != null;
    }

    /**
     * Share table name for an object.
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
     * @param objectApiName API name of the object.
     * @return Parent field API name.
     */
    private static String parentFieldName(String objectApiName) {
        return objectApiName.endsWith('__c') ? 'ParentId' : objectApiName + 'Id';
    }

    /**
     * Guards an object name before it reaches a dynamic query.
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
}
