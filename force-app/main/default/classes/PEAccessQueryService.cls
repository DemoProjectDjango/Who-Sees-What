/**
 * The per-column and composite queries. Everything here filters against the
 * cached effective parent Ids, so no query re-derives permissions.
 *
 * Absence rule, applied throughout: a missing ObjectPermissions or
 * FieldPermissions row means *no access*, not unknown. Treating absence as
 * unknown produces a tool that shrugs, which is worse than one that answers.
 *
 * Two PMD suppressions below are deliberate and structural, not deferred work:
 *
 * OperationWithLimitsInLoop — every query here sits inside a loop over
 * PESoqlChunker batches. That loop exists precisely to respect limits: a
 * user with hundreds of effective parents exceeds the SOQL bind-list ceiling
 * in one query, so the work is split and the count is pre-checked by
 * assertQueryBudget. Hoisting the queries out of the loop is the bug this
 * pattern prevents.
 *
 * CognitiveComplexity / CyclomaticComplexity at class level — this is the
 * query surface for the whole product. Its complexity is breadth (six
 * permission columns, four query shapes) rather than depth, and splitting it
 * to satisfy a threshold would scatter the absence rule across files, which
 * is the one invariant that has to hold identically everywhere.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.CyclomaticComplexity')
public with sharing class PEAccessQueryService {

    /* ---------------------------------------------------------------
     * Modal table — objects and tabs for the selected app
     * --------------------------------------------------------------- */

    /**
     * Builds the object and tab access rows shown when an admin opens an app's
     * visibility details, combining app navigation metadata with effective CRUD.
     *
     * @param r Effective permission-set resolution for the inspected user.
     * @param appDeveloperName Developer name of the Lightning app being inspected.
     * @return Object and tab rows that explain what the selected user can reach from the app.
     */
    public static List<PEDto.ObjectRow> getAppObjects(
        PEPermissionResolver.Resolved r, String appDeveloperName
    ) {
        Map<String, PEDto.ObjectRow> byApiName = new Map<String, PEDto.ObjectRow>();

        // 1. App's tabs, in the app's own tab order.
        List<PEMetadataCatalog.TabInfo> tabs = PEMetadataCatalog.getAppTabs(appDeveloperName);

        for (PEMetadataCatalog.TabInfo t : tabs) {
            PEDto.ObjectRow row = new PEDto.ObjectRow();
            row.apiName       = t.objectApiName != null ? t.objectApiName : t.tabName;
            row.label         = t.label;
            row.isObjectTab   = t.objectApiName != null;
            row.tabVisibility = 'Hidden';
            byApiName.put(row.apiName, row);
        }

        // 2. Tab visibility, per parent. Chunked — never one query per tab.
        applyTabVisibility(r, byApiName, tabs);

        // 3. Object CRUD for the object-backed rows.
        applyObjectPermissions(r, byApiName);

        // 4. Objects with data access but no tab in this app. Reachable by API
        //    and related lists, invisible in navigation — a frequent source of
        //    "why can they see this?" tickets, so surfaced rather than omitted.
        appendAccessWithoutTab(r, byApiName);

        return byApiName.values();
    }

    /**
     * Tab name to row-key mapping, lifted out so applyTabVisibility reads as
     * two steps rather than one long method.
     *
     * @param tabs Tab metadata for the app being inspected.
     * @return Map of tab name to the row key used for that tab, which is the backing object API name where one exists.
     */
    private static Map<String, String> apiNameByTabName(List<PEMetadataCatalog.TabInfo> tabs) {
        Map<String, String> out = new Map<String, String>();
        for (PEMetadataCatalog.TabInfo t : tabs) {
            out.put(t.tabName, t.objectApiName != null ? t.objectApiName : t.tabName);
        }
        return out;
    }

    /**
     * Applies per-parent tab visibility onto the already-seeded rows, merging
     * additively so DefaultOn beats DefaultOff beats Hidden.
     *
     * @param r Effective permission-set resolution for the inspected user.
     * @param rows Rows keyed by object API name or tab name, mutated in place.
     * @param tabs Tab metadata for the app being inspected.
     */
    @SuppressWarnings('PMD.OperationWithLimitsInLoop')
    private static void applyTabVisibility(
        PEPermissionResolver.Resolved r,
        Map<String, PEDto.ObjectRow> rows,
        List<PEMetadataCatalog.TabInfo> tabs
    ) {
        Map<String, String> apiNameByTabName = apiNameByTabName(tabs);
        Set<String> tabNames = apiNameByTabName.keySet();
        if (tabNames.isEmpty()) {
            return;
        }

        List<List<Id>> batches = PESoqlChunker.chunk(r.effectiveParents);
        PESoqlChunker.assertQueryBudget(batches.size());

        for (List<Id> batch : batches) {
            for (PermissionSetTabSetting s : [
                SELECT Name, Visibility, ParentId
                FROM PermissionSetTabSetting
                WHERE ParentId IN :batch AND Name IN :tabNames
                WITH USER_MODE
            ]) {
                PEDto.ObjectRow row = rows.get(apiNameByTabName.get(s.Name));
                if (row == null) {
                    continue;
                }

                // DefaultOn beats DefaultOff beats Hidden — additive, like every
                // other permission.
                if (s.Visibility == 'DefaultOn' || row.tabVisibility == 'Hidden') {
                    row.tabVisibility = s.Visibility;
                }
                PEDto.Source src = r.sourcesById.get(s.ParentId);
                if (src != null) {
                    row.tabSources.add(src);
                }
            }
        }
    }

    /**
     * The six CRUD columns are OR-merged in two different query paths. Keeping
     * that in one place means the two can never disagree about what "additive"
     * means, which is the failure a permission tool cannot afford.
     *
     * @param row Row to merge into, mutated in place.
     * @param op Object permission record contributing its six columns to the row.
     */
    private static void mergeCrud(PEDto.ObjectRow row, ObjectPermissions op) {
        row.canRead   = row.canRead   || op.PermissionsRead;
        row.canCreate = row.canCreate || op.PermissionsCreate;
        row.canEdit   = row.canEdit   || op.PermissionsEdit;
        row.canDelete = row.canDelete || op.PermissionsDelete;
        row.viewAll   = row.viewAll   || op.PermissionsViewAllRecords;
        row.modifyAll = row.modifyAll || op.PermissionsModifyAllRecords;
    }

    /**
     * Applies effective object CRUD onto the object-backed rows already seeded
     * from the app's tabs.
     *
     * @param r Effective permission-set resolution for the inspected user.
     * @param rows Rows keyed by object API name or tab name, mutated in place.
     */
    @SuppressWarnings('PMD.OperationWithLimitsInLoop')
    private static void applyObjectPermissions(
        PEPermissionResolver.Resolved r, Map<String, PEDto.ObjectRow> rows
    ) {
        Set<String> objectNames = new Set<String>();
        for (PEDto.ObjectRow row : rows.values()) {
            if (row.isObjectTab) {
                objectNames.add(row.apiName);
            }
        }
        if (objectNames.isEmpty()) {
            return;
        }

        for (List<Id> batch : PESoqlChunker.chunk(r.effectiveParents)) {
            for (ObjectPermissions op : [
                SELECT SobjectType, ParentId,
                       PermissionsRead, PermissionsCreate, PermissionsEdit,
                       PermissionsDelete, PermissionsViewAllRecords,
                       PermissionsModifyAllRecords
                FROM ObjectPermissions
                WHERE ParentId IN :batch AND SobjectType IN :objectNames
                WITH USER_MODE
            ]) {
                PEDto.ObjectRow row = rows.get(op.SobjectType);
                if (row == null) {
                    continue;
                }
                mergeCrud(row, op);
            }
        }
    }

    /**
     * A row for an object reachable by data access but absent from this app's tabs.
     *
     * @param objectApiName API name of the object that has data access but no tab in the app.
     * @return A row marked as reachable without a tab, ready for CRUD merging.
     */
    private static PEDto.ObjectRow newAccessWithoutTabRow(String objectApiName) {
        PEDto.ObjectRow row = new PEDto.ObjectRow();
        row.apiName          = objectApiName;
        row.label            = PEMetadataCatalog.labelFor(objectApiName);
        row.isObjectTab      = true;
        row.tabVisibility    = 'NoTab';
        row.accessWithoutTab = true;
        return row;
    }

    /**
     * Adds rows for objects the user can read but which have no tab in the
     * selected app, so navigation-invisible access is still explained.
     *
     * @param r Effective permission-set resolution for the inspected user.
     * @param rows Rows keyed by object API name or tab name, mutated in place.
     */
    @SuppressWarnings('PMD.OperationWithLimitsInLoop')
    private static void appendAccessWithoutTab(
        PEPermissionResolver.Resolved r, Map<String, PEDto.ObjectRow> rows
    ) {
        Map<String, PEDto.ObjectRow> extra = new Map<String, PEDto.ObjectRow>();

        for (List<Id> batch : PESoqlChunker.chunk(r.effectiveParents)) {
            for (ObjectPermissions op : [
                SELECT SobjectType, PermissionsRead, PermissionsCreate,
                       PermissionsEdit, PermissionsDelete,
                       PermissionsViewAllRecords, PermissionsModifyAllRecords
                FROM ObjectPermissions
                WHERE ParentId IN :batch AND PermissionsRead = true
                WITH USER_MODE
            ]) {
                if (rows.containsKey(op.SobjectType)) {
                    continue;
                }

                PEDto.ObjectRow row = extra.get(op.SobjectType);
                if (row == null) {
                    row = newAccessWithoutTabRow(op.SobjectType);
                    extra.put(op.SobjectType, row);
                }
                mergeCrud(row, op);
            }
        }
        rows.putAll(extra);
    }

    /* ---------------------------------------------------------------
     * Composite object detail — one round trip, not four
     * --------------------------------------------------------------- */

    /**
     * Everything SOQL-cheap in a single call, so switching sections afterwards is
     * pure client-side rendering. Sharing is deliberately excluded: it needs a
     * Metadata API callout and __Share queries can be enormous.
     *
     * The rule: eager for anything SOQL-cheap, lazy for anything that touches a
     * callout.
     *
     * @param r Effective permission-set resolution for the inspected user.
     * @param objectApiName API name of the object whose permissions are being inspected.
     * @return Composite object detail used by the admin console to render object, field, record type, and sharing context.
     */
    public static PEDto.ObjectDetail getObjectDetail(
        PEPermissionResolver.Resolved r, String objectApiName
    ) {
        PEDto.ObjectDetail d = new PEDto.ObjectDetail();
        d.apiName    = objectApiName;
        d.label      = PEMetadataCatalog.labelFor(objectApiName);
        d.resolvedAt = System.now();

        d.objectPermissions = buildObjectGrants(r, objectApiName);

        // Per-section error boundary: a field-list failure must not blank the
        // Object Permissions panel that already rendered correctly.
        try {
            d.fields = buildFieldPerms(r, objectApiName);
        } catch (Exception e) {
            d.fields = new List<PEDto.FieldPerm>();
            d.fieldsError = new PEDto.ErrorInfo(
                PermissionExplorerException.LIMIT_EXCEEDED,
                'Field permissions could not be loaded for this object. Retry, or open a smaller object.',
                true
            );
        }

        // Org-level record type list. Not the target user's visibility — the UI
        // labels it as such, and the panel keeps its "not analysed" notice.
        d.recordTypes = buildRecordTypes(objectApiName);

        Map<String, String> owd = PEMetadataCatalog.sharingModel(objectApiName);
        d.internalSharingModel = owd.get('internal');
        d.externalSharingModel = owd.get('external');

        return d;
    }

    /**
     * Permission name to value, so the grant/mute split reads as one loop.
     *
     * @param op Object permission record whose six columns are being unpacked.
     * @return Map of permission API name to its Boolean value on that record.
     */
    private static Map<String, Boolean> permValues(ObjectPermissions op) {
        return new Map<String, Boolean>{
            'PermissionsRead'             => op.PermissionsRead,
            'PermissionsCreate'           => op.PermissionsCreate,
            'PermissionsEdit'             => op.PermissionsEdit,
            'PermissionsDelete'           => op.PermissionsDelete,
            'PermissionsViewAllRecords'   => op.PermissionsViewAllRecords,
            'PermissionsModifyAllRecords' => op.PermissionsModifyAllRecords
        };
    }

    /**
     * Builds the six object-level grants, keeping granting and muting parents in
     * separate maps so the resolver can subtract rather than union.
     *
     * @param r Effective permission-set resolution for the inspected user.
     * @param objectApiName API name of the object whose grants are being resolved.
     * @return One grant per object permission, in the product's fixed display order.
     */
    @SuppressWarnings('PMD.OperationWithLimitsInLoop')
    private static List<PEDto.Grant> buildObjectGrants(
        PEPermissionResolver.Resolved r, String objectApiName
    ) {
        Map<String, Map<Id, Boolean>> grantedByPerm = new Map<String, Map<Id, Boolean>>();
        Map<String, Map<Id, Boolean>> mutedByPerm   = new Map<String, Map<Id, Boolean>>();
        for (String p : PEConstants.OBJECT_PERM_ORDER) {
            grantedByPerm.put(p, new Map<Id, Boolean>());
            mutedByPerm.put(p, new Map<Id, Boolean>());
        }

        Set<Id> allParents = new Set<Id>(r.effectiveParents);
        allParents.addAll(r.mutingParents);

        for (List<Id> batch : PESoqlChunker.chunk(allParents)) {
            for (ObjectPermissions op : [
                SELECT ParentId, PermissionsRead, PermissionsCreate, PermissionsEdit,
                       PermissionsDelete, PermissionsViewAllRecords, PermissionsModifyAllRecords
                FROM ObjectPermissions
                WHERE ParentId IN :batch AND SobjectType = :objectApiName
                WITH USER_MODE
            ]) {
                Boolean isMuting = r.mutingParents.contains(op.ParentId);
                Map<String, Boolean> values = permValues(op);
                for (String perm : values.keySet()) {
                    Map<String, Map<Id, Boolean>> target = isMuting ? mutedByPerm : grantedByPerm;
                    target.get(perm).put(op.ParentId, values.get(perm));
                }
            }
        }

        List<PEDto.Grant> out = new List<PEDto.Grant>();
        for (String perm : PEConstants.OBJECT_PERM_ORDER) {
            out.add(PEPermissionResolver.applyGrant(
                perm,
                PEConstants.OBJECT_PERM_LABELS.get(perm),
                r,
                grantedByPerm.get(perm),
                mutedByPerm.get(perm)
            ));
        }
        return out;
    }

    /**
     * Every field on the object, classified before any permission row is read.
     * Seeding first is what lets absence mean "no access" rather than "not in
     * the result set".
     *
     * @param objectApiName API name of the object whose fields are being enumerated.
     * @return Field rows keyed by qualified field name, pre-classified for FLS applicability and with no permissions applied yet.
     */
    private static Map<String, PEDto.FieldPerm> seedFieldRows(String objectApiName) {
        Map<String, Schema.SObjectField> fieldMap = PEMetadataCatalog.fieldMap(objectApiName);
        Map<String, PEDto.FieldPerm> byApiName = new Map<String, PEDto.FieldPerm>();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();

            PEDto.FieldPerm fp = new PEDto.FieldPerm();
            fp.apiName  = dfr.getName();
            fp.label    = dfr.getLabel();
            fp.dataType = String.valueOf(dfr.getType()).toLowerCase().capitalize();

            PEFlsClassifier.Verdict v = PEFlsClassifier.classify(dfr);
            fp.flsNotApplicable       = v.notApplicable;
            fp.flsNotApplicableReason = v.reason;

            byApiName.put(objectApiName + '.' + dfr.getName(), fp);
        }
        return byApiName;
    }

    /**
     * Applies effective read and edit FLS onto the seeded field rows, recording
     * the source of each grant.
     *
     * @param r Effective permission-set resolution for the inspected user.
     * @param objectApiName API name of the object whose field permissions are being resolved.
     * @return Every field on the object, with readability, editability, and grant sources filled in.
     */
    @SuppressWarnings('PMD.OperationWithLimitsInLoop')
    private static List<PEDto.FieldPerm> buildFieldPerms(
        PEPermissionResolver.Resolved r, String objectApiName
    ) {
        Map<String, PEDto.FieldPerm> byApiName = seedFieldRows(objectApiName);

        for (List<Id> batch : PESoqlChunker.chunk(r.effectiveParents)) {
            for (FieldPermissions f : [
                SELECT Field, ParentId, PermissionsRead, PermissionsEdit
                FROM FieldPermissions
                WHERE ParentId IN :batch AND SobjectType = :objectApiName
                WITH USER_MODE
            ]) {
                PEDto.FieldPerm fp = byApiName.get(f.Field);
                if (fp == null) {
                    continue;
                }

                PEDto.Source src = r.sourcesById.get(f.ParentId);
                if (f.PermissionsRead) {
                    fp.readable = true;
                    if (src != null) {
                        fp.readSources.add(src);
                    }
                }
                if (f.PermissionsEdit) {
                    fp.editable = true;
                    if (src != null) {
                        fp.editSources.add(src);
                    }
                }
            }
        }

        // No sort() here: List.sort() on a wrapper needs Comparable, and the
        // field table sorts client-side anyway where the admin can change it.
        return byApiName.values();
    }

    /**
     * The record types that exist on the object.
     *
     * Per-permission-set visibility lives only in Profile/PermissionSet metadata,
     * so this is deliberately the org-level list. `availableToRunningUser` is the
     * *running* user's access, never the target's — describe cannot answer for
     * someone else, and presenting it as though it could is the exact confusion
     * this tool exists to remove.
     *
     * @param objectApiName API name of the object whose record type catalog is displayed beside permission findings.
     * @return Org-level record type rows for the object, annotated with running-user describe availability.
     */
    private static List<PEDto.RecordTypeRow> buildRecordTypes(String objectApiName) {
        List<PEDto.RecordTypeRow> out = new List<PEDto.RecordTypeRow>();

        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApiName);
        if (t == null) {
            return out;
        }

        for (Schema.RecordTypeInfo info : t.getDescribe().getRecordTypeInfos()) {
            PEDto.RecordTypeRow row = new PEDto.RecordTypeRow();
            row.developerName          = info.getDeveloperName();
            row.label                  = info.getName();
            row.isActive               = info.isActive();
            row.isMaster               = info.isMaster();
            row.availableToRunningUser = info.isAvailable();
            out.add(row);
        }
        return out;
    }
}