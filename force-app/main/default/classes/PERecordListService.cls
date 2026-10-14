/**
 * The record list behind Data Visibility: which records a user reaches, and
 * what they can do to each one.
 *
 * Two modes, because the two questions have different guarantees and no single
 * query answers both.
 *
 * ACCESSIBLE mode is driven from the share table. Every row returned is
 * genuinely reachable, the total is known up front, and each row carries the
 * reason it is reachable (Owner, Manual, Rule, Team, Territory). It cannot
 * free-text search on the record's own fields, because the driving query is
 * over share rows rather than records.
 *
 * ALL mode is driven from the object. Search, sort and paging are native on
 * indexed fields, and each page is then annotated with the selected user's real
 * access through UserRecordAccess. That is exact and includes role hierarchy
 * and implicit parent-child sharing, which share rows do not reliably show -
 * but the total reachable count is unknowable without walking every page.
 *
 * Presenting these as one blended list with an "accessible only" checkbox would
 * mean filtering the current page and reporting "12 of 200" while meaning "12
 * on this page". The mode switch is the honest shape.
 */
public with sharing class PERecordListService {

    /** UserRecordAccess accepts at most 200 record Ids per query, so the page
     *  size is set by the platform rather than chosen. */
    private static final Integer PAGE_SIZE = 200;

    /** Share rows read per page before de-duplication. A record can carry
     *  several share rows, so this is deliberately larger than PAGE_SIZE. */
    private static final Integer SHARE_SCAN = 1000;

    private static final Set<String> SORTABLE =
        new Set<String>{ 'Name', 'CreatedDate', 'LastModifiedDate', 'Id' };

    /* ---------------------------------------------------------------
     * Result shape
     * --------------------------------------------------------------- */

    /** One record, with the selected user's access to it. */
    public class RecordRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String label;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Boolean ownedByUser = false;
        /** Owner, Manual, Rule, Team, Territory, ImplicitChild, or null. */
        @AuraEnabled public String reason;
        @AuraEnabled public Boolean canRead = false;
        @AuraEnabled public Boolean canEdit = false;
        @AuraEnabled public Boolean canDelete = false;
        /** True when object permissions allow delete but the record does not.
         *  The contradiction an administrator cannot see anywhere in Setup. */
        @AuraEnabled public Boolean deleteBlockedByRecord = false;
        @AuraEnabled public Datetime createdDate;
    }

    /** One page of records. */
    public class RecordPage {
        @AuraEnabled public List<RecordRow> rows = new List<RecordRow>();
        /** Cursor for the next page, null when this is the last one. */
        @AuraEnabled public String nextCursor;
        @AuraEnabled public Boolean hasMore = false;
        /** Known only in ACCESSIBLE mode; null in ALL mode by nature. */
        @AuraEnabled public Integer totalReachable;
        /** Records the driving query matched, for the "showing x of y" line. */
        @AuraEnabled public Integer matchedRecords;
        @AuraEnabled public String mode;
        /** False when the object has no name field and rows are keyed by Id. */
        @AuraEnabled public Boolean hasNameField = true;
        @AuraEnabled public Boolean searchSupported = true;
        @AuraEnabled public List<String> notes = new List<String>();
    }

    /** One bucket of the share breakdown. */
    public class ReasonBucket {
        @AuraEnabled public String reason;
        @AuraEnabled public String accessLevel;
        @AuraEnabled public Integer total;
    }

    /* ---------------------------------------------------------------
     * Share breakdown
     * --------------------------------------------------------------- */

    /**
     * Why the user reaches what they reach, grouped by share reason.
     *
     * Buckets can overlap: one record may carry both an Owner row and a Manual
     * row, so the bucket totals do not necessarily sum to the reachable count.
     * They are reported as separate facts rather than as parts of a whole, and
     * the reachable figure is a COUNT_DISTINCT over all rows so it stays
     * correct whether or not this object's share table materialises Owner rows
     * at all - a detail that differs between standard and custom objects and is
     * not worth betting the arithmetic on.
     *
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @return Buckets ordered by size, largest first.
     */
    public static List<ReasonBucket> getReasonBreakdown(Id userId, String objectApiName) {
        List<ReasonBucket> out = new List<ReasonBucket>();

        String shareName = shareObjectName(objectApiName);
        String parentField = parentFieldName(objectApiName);
        if (!objectExists(shareName)) {
            return out;
        }

        try {
            Set<Id> holders = PERecordAccessService.accessHolders(userId);

            String lvlField = PERecordAccessService.accessLevelFieldName(objectApiName);

            List<AggregateResult> rows = (List<AggregateResult>) Database.query(
                'SELECT RowCause cause, ' + lvlField + ' lvl, COUNT_DISTINCT(' + parentField + ') cnt ' +
                'FROM ' + shareName + ' WHERE UserOrGroupId IN :holders ' +
                'GROUP BY RowCause, ' + lvlField +
                ' ORDER BY COUNT_DISTINCT(' + parentField + ') DESC',
                AccessLevel.USER_MODE
            );

            for (AggregateResult ar : rows) {
                ReasonBucket b = new ReasonBucket();
                b.reason      = (String) ar.get('cause');
                b.accessLevel = (String) ar.get('lvl');
                b.total       = (Integer) ar.get('cnt');
                out.add(b);
            }
        } catch (Exception e) {
            // A missing or unreadable share table is not an error here: the
            // summary above it already explains the object's sharing model.
            return new List<ReasonBucket>();
        }
        return out;
    }

    /* ---------------------------------------------------------------
     * Record page
     * --------------------------------------------------------------- */

    /**
     * One page of records with the selected user's access to each.
     *
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @param mode 'ACCESSIBLE' or 'ALL'.
     * @param searchTerm Free text, ALL mode only; ignored otherwise.
     * @param sortField Name, CreatedDate, LastModifiedDate or Id.
     * @param cursor Opaque cursor from the previous page, or null to start.
     * @return A page of rows plus the cursor for the next one.
     */
    // The parameter list mirrors the control surface the panel exposes; folding
    // it into a wrapper object would hide which knobs exist from the caller.
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static RecordPage getPage(
        Id userId,
        String objectApiName,
        String mode,
        String searchTerm,
        String sortField,
        String cursor
    ) {
        RecordPage page = new RecordPage();
        page.mode = mode == 'ALL' ? 'ALL' : 'ACCESSIBLE';

        Schema.DescribeSObjectResult d = describe(objectApiName);
        if (d == null || !d.isAccessible()) {
            page.notes.add('This object cannot be read by your user.');
            return page;
        }

        page.hasNameField = nameFieldOf(d) != null;
        if (!page.hasNameField) {
            page.notes.add('This object has no name field, so records are listed by Id.');
        }

        return page.mode == 'ALL'
            ? allMode(page, userId, objectApiName, d, searchTerm, sortField, cursor)
            : accessibleMode(page, userId, objectApiName, d, cursor);
    }

    /* ---------------------------------------------------------------
     * ACCESSIBLE mode
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
    private static RecordPage accessibleMode(
        RecordPage page, Id userId, String objectApiName,
        Schema.DescribeSObjectResult d, String cursor
    ) {
        page.searchSupported = false;

        String shareName = shareObjectName(objectApiName);
        String parentField = parentFieldName(objectApiName);
        if (!objectExists(shareName)) {
            page.notes.add(
                'This object has no share table, so there is no per-record sharing to list.'
            );
            return page;
        }

        try {
            Set<Id> holders = PERecordAccessService.accessHolders(userId);
            Id after = String.isBlank(cursor) ? null : (Id) cursor;
            Integer scan = SHARE_SCAN;

            String lvlField = PERecordAccessService.accessLevelFieldName(objectApiName);

            // No field aliases and no AggregateResult cast: aliases are only
            // legal in an aggregate query, and asking for them here threw on
            // every object, which is why the list came back empty rather than
            // wrong.
            String q =
                'SELECT ' + parentField + ', RowCause, ' + lvlField + ' ' +
                'FROM ' + shareName + ' WHERE UserOrGroupId IN :holders ';
            if (after != null) {
                q += 'AND ' + parentField + ' > :after ';
            }
            q += 'ORDER BY ' + parentField + ' ASC LIMIT :scan';

            // Keyset on the parent Id, not OFFSET: OFFSET caps at 2000 in SOQL
            // and re-reads everything before the window on every page.
            Map<Id, ReasonBucket> best = new Map<Id, ReasonBucket>();
            for (SObject sh : Database.query(q, AccessLevel.USER_MODE)) {
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
            page.nextCursor = ids.isEmpty() || !more ? null : String.valueOf(ids[ids.size() - 1]);
            page.totalReachable = countReachable(objectApiName, holders);
            page.matchedRecords = page.totalReachable;

            buildRows(page, userId, objectApiName, d, ids, best);
        } catch (Exception e) {
            page.notes.add('Shared records could not be listed for this object.');
        }
        return page;
    }

    /**
     * Distinct records reachable through any share row.
     *
     * COUNT_DISTINCT rather than a sum of buckets: one record can appear under
     * several reasons, and adding the buckets would over-count it.
     *
     * @param objectApiName API name of the object.
     * @param holders Every Id a share row could name for this user.
     * @return Distinct reachable record count, or null when unreadable.
     */
    private static Integer countReachable(String objectApiName, Set<Id> holders) {
        try {
            String shareName = shareObjectName(objectApiName);
            String parentField = parentFieldName(objectApiName);

            List<AggregateResult> ar = (List<AggregateResult>) Database.query(
                'SELECT COUNT_DISTINCT(' + parentField + ') cnt FROM ' + shareName +
                ' WHERE UserOrGroupId IN :holders',
                AccessLevel.USER_MODE
            );
            return ar.isEmpty() ? 0 : (Integer) ar[0].get('cnt');
        } catch (Exception e) {
            return null;
        }
    }

    /* ---------------------------------------------------------------
     * ALL mode
     * --------------------------------------------------------------- */

    /**
     * Driven from the object, so search and sort are native and fast.
     *
     * @param page Page under construction.
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @param d Describe result for the object.
     * @param searchTerm Free text to match against the name field.
     * @param sortField Field to order by.
     * @param cursor Last record Id from the previous page, or null.
     * @return The populated page.
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static RecordPage allMode(
        RecordPage page, Id userId, String objectApiName,
        Schema.DescribeSObjectResult d, String searchTerm, String sortField, String cursor
    ) {
        String nameField = nameFieldOf(d);
        // `sort` is a reserved identifier in Apex and cannot name a variable.
        String sortBy = SORTABLE.contains(sortField) ? sortField : 'Id';
        if (sortBy == 'Name' && nameField == null) {
            sortBy = 'Id';
        }
        page.searchSupported = nameField != null;

        try {
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

            Id after = String.isBlank(cursor) ? null : (Id) cursor;
            String term = String.isBlank(searchTerm) ? null : '%' + searchTerm.trim() + '%';
            Integer lim = PAGE_SIZE + 1;

            String q = 'SELECT ' + String.join(fields, ', ') +
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

            List<SObject> records = Database.query(q, AccessLevel.USER_MODE);

            page.hasMore = records.size() > PAGE_SIZE;
            if (page.hasMore) {
                records.remove(PAGE_SIZE);
            }
            page.matchedRecords = records.size();
            page.nextCursor = records.isEmpty() || !page.hasMore
                ? null
                : String.valueOf(records[records.size() - 1].Id);

            // Unknowable without walking every page, and a guess here would be
            // read as a count.
            page.totalReachable = null;

            List<Id> ids = new List<Id>();
            Map<Id, SObject> byId = new Map<Id, SObject>();
            for (SObject s : records) {
                ids.add((Id) s.get('Id'));
                byId.put((Id) s.get('Id'), s);
            }

            buildRowsFrom(page, userId, d, ids, byId, nameField, null);
        } catch (Exception e) {
            page.notes.add('Records could not be listed for this object.');
        }
        return page;
    }

    /* ---------------------------------------------------------------
     * Row assembly
     * --------------------------------------------------------------- */

    /**
     * Fetches the parent records for a set of Ids, then builds the rows.
     *
     * @param page Page under construction.
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @param d Describe result for the object.
     * @param ids Record Ids to display.
     * @param reasons Share reason per record, keyed by record Id.
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static void buildRows(
        RecordPage page, Id userId, String objectApiName,
        Schema.DescribeSObjectResult d, List<Id> ids, Map<Id, ReasonBucket> reasons
    ) {
        if (ids.isEmpty()) {
            return;
        }
        String nameField = nameFieldOf(d);

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

        Map<Id, SObject> byId = new Map<Id, SObject>(
            Database.query(
                'SELECT ' + String.join(fields, ', ') + ' FROM ' + safeName(objectApiName) +
                ' WHERE Id IN :ids',
                AccessLevel.USER_MODE
            )
        );
        buildRowsFrom(page, userId, d, ids, byId, nameField, reasons);
    }

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
     * @param reasons Share reason per record, or null in ALL mode.
     */
    @SuppressWarnings('PMD.ExcessiveParameterList,PMD.CognitiveComplexity')
    private static void buildRowsFrom(
        RecordPage page, Id userId, Schema.DescribeSObjectResult d,
        List<Id> ids, Map<Id, SObject> byId, String nameField,
        Map<Id, ReasonBucket> reasons
    ) {
        Map<Id, UserRecordAccess> access = accessFor(userId, ids);
        Boolean objectDeletable = d.isDeletable();

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

            if (d.fields.getMap().containsKey('OwnerId')) {
                row.ownedByUser = s.get('OwnerId') == userId;
                SObject owner = s.getSObject('Owner');
                row.ownerName = owner == null ? null : String.valueOf(owner.get('Name'));
            }
            if (d.fields.getMap().containsKey('CreatedDate')) {
                row.createdDate = (Datetime) s.get('CreatedDate');
            }

            ReasonBucket rb = reasons == null ? null : reasons.get(rid);
            row.reason = row.ownedByUser ? 'Owner' : (rb == null ? null : rb.reason);

            UserRecordAccess ura = access.get(rid);
            if (ura != null) {
                row.canRead   = ura.HasReadAccess;
                row.canEdit   = ura.HasEditAccess;
                row.canDelete = ura.HasDeleteAccess;
            }

            // The contradiction worth surfacing: object permissions allow
            // delete, the record does not. A manual share can only grant Read
            // or Read/Write, so this is the normal state for shared records and
            // is invisible anywhere in Setup.
            row.deleteBlockedByRecord = objectDeletable && row.canRead && !row.canDelete;

            page.rows.add(row);
        }
    }

    /**
     * The selected user's access to a page of records.
     *
     * UserRecordAccess is the only object that answers for another user, and it
     * is the only thing here that sees role hierarchy and implicit sharing.
     *
     * @param userId The user being inspected.
     * @param ids Record Ids, at most 200.
     * @return Access rows keyed by record Id; empty when the query fails.
     */
    private static Map<Id, UserRecordAccess> accessFor(Id userId, List<Id> ids) {
        Map<Id, UserRecordAccess> out = new Map<Id, UserRecordAccess>();
        if (ids.isEmpty()) {
            return out;
        }
        try {
            for (UserRecordAccess a : [
                SELECT RecordId, HasReadAccess, HasEditAccess, HasDeleteAccess, MaxAccessLevel
                FROM UserRecordAccess
                WHERE UserId = :userId AND RecordId IN :ids
            ]) {
                out.put(a.RecordId, a);
            }
        } catch (Exception e) {
            // Querying another user's access needs elevated permission. Without
            // it the rows still list, with the access chips blank rather than
            // wrong - absent is recoverable, false is a lie.
            return new Map<Id, UserRecordAccess>();
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
        if (level == 'All') return 3;
        if (level == 'Edit') return 2;
        if (level == 'Read') return 1;
        return 0;
    }

    /**
     * The object's name field, or null when it has none.
     *
     * Junction objects and several standard objects have no name field, and
     * listing those by Id is better than rendering a column of blanks.
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
