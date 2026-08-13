/**
 * The per-column and composite queries. Everything here filters against the
 * cached effective parent Ids, so no query re-derives permissions.
 *
 * Absence rule, applied throughout: a missing ObjectPermissions or
 * FieldPermissions row means *no access*, not unknown. Treating absence as
 * unknown produces a tool that shrugs, which is worse than one that answers.
 */
public with sharing class AccessQueryService {

    /* ---------------------------------------------------------------
     * Modal table — objects and tabs for the selected app
     * --------------------------------------------------------------- */

    public static List<PEDto.ObjectRow> getAppObjects(
        PermissionResolver.Resolved r, String appDeveloperName
    ) {
        Map<String, PEDto.ObjectRow> byApiName = new Map<String, PEDto.ObjectRow>();

        // 1. App's tabs, in the app's own tab order.
        List<MetadataCatalog.TabInfo> tabs = MetadataCatalog.getAppTabs(appDeveloperName);

        for (MetadataCatalog.TabInfo t : tabs) {
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

    private static void applyTabVisibility(
        PermissionResolver.Resolved r,
        Map<String, PEDto.ObjectRow> rows,
        List<MetadataCatalog.TabInfo> tabs
    ) {
        Set<String> tabNames = new Set<String>();
        Map<String, String> apiNameByTabName = new Map<String, String>();
        for (MetadataCatalog.TabInfo t : tabs) {
            tabNames.add(t.tabName);
            apiNameByTabName.put(t.tabName, t.objectApiName != null ? t.objectApiName : t.tabName);
        }
        if (tabNames.isEmpty()) return;

        List<List<Id>> batches = PESoqlChunker.chunk(r.effectiveParents);
        PESoqlChunker.assertQueryBudget(batches.size());

        for (List<Id> batch : batches) {
            for (PermissionSetTabSetting s : [
                SELECT Name, Visibility, ParentId
                FROM PermissionSetTabSetting
                WHERE ParentId IN :batch AND Name IN :tabNames
            ]) {
                String apiName = apiNameByTabName.get(s.Name);
                PEDto.ObjectRow row = rows.get(apiName);
                if (row == null) continue;

                // DefaultOn beats DefaultOff beats Hidden — additive, like every
                // other permission.
                if (s.Visibility == 'DefaultOn' || row.tabVisibility == 'Hidden') {
                    row.tabVisibility = s.Visibility;
                }
                PEDto.Source src = r.sourcesById.get(s.ParentId);
                if (src != null) row.tabSources.add(src);
            }
        }
    }

    private static void applyObjectPermissions(
        PermissionResolver.Resolved r, Map<String, PEDto.ObjectRow> rows
    ) {
        Set<String> objectNames = new Set<String>();
        for (PEDto.ObjectRow row : rows.values()) {
            if (row.isObjectTab) objectNames.add(row.apiName);
        }
        if (objectNames.isEmpty()) return;

        for (List<Id> batch : PESoqlChunker.chunk(r.effectiveParents)) {
            for (ObjectPermissions op : [
                SELECT SobjectType, ParentId,
                       PermissionsRead, PermissionsCreate, PermissionsEdit,
                       PermissionsDelete, PermissionsViewAllRecords,
                       PermissionsModifyAllRecords
                FROM ObjectPermissions
                WHERE ParentId IN :batch AND SobjectType IN :objectNames
            ]) {
                PEDto.ObjectRow row = rows.get(op.SobjectType);
                if (row == null) continue;
                row.canRead   = row.canRead   || op.PermissionsRead;
                row.canCreate = row.canCreate || op.PermissionsCreate;
                row.canEdit   = row.canEdit   || op.PermissionsEdit;
                row.canDelete = row.canDelete || op.PermissionsDelete;
                row.viewAll   = row.viewAll   || op.PermissionsViewAllRecords;
                row.modifyAll = row.modifyAll || op.PermissionsModifyAllRecords;
            }
        }
    }

    private static void appendAccessWithoutTab(
        PermissionResolver.Resolved r, Map<String, PEDto.ObjectRow> rows
    ) {
        Map<String, PEDto.ObjectRow> extra = new Map<String, PEDto.ObjectRow>();

        for (List<Id> batch : PESoqlChunker.chunk(r.effectiveParents)) {
            for (ObjectPermissions op : [
                SELECT SobjectType, PermissionsRead, PermissionsCreate,
                       PermissionsEdit, PermissionsDelete,
                       PermissionsViewAllRecords, PermissionsModifyAllRecords
                FROM ObjectPermissions
                WHERE ParentId IN :batch AND PermissionsRead = true
            ]) {
                if (rows.containsKey(op.SobjectType)) continue;

                PEDto.ObjectRow row = extra.get(op.SobjectType);
                if (row == null) {
                    row = new PEDto.ObjectRow();
                    row.apiName          = op.SobjectType;
                    row.label            = MetadataCatalog.labelFor(op.SobjectType);
                    row.isObjectTab      = true;
                    row.tabVisibility    = 'NoTab';
                    row.accessWithoutTab = true;
                    extra.put(op.SobjectType, row);
                }
                row.canRead   = row.canRead   || op.PermissionsRead;
                row.canCreate = row.canCreate || op.PermissionsCreate;
                row.canEdit   = row.canEdit   || op.PermissionsEdit;
                row.canDelete = row.canDelete || op.PermissionsDelete;
                row.viewAll   = row.viewAll   || op.PermissionsViewAllRecords;
                row.modifyAll = row.modifyAll || op.PermissionsModifyAllRecords;
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
     */
    public static PEDto.ObjectDetail getObjectDetail(
        PermissionResolver.Resolved r, String objectApiName
    ) {
        PEDto.ObjectDetail d = new PEDto.ObjectDetail();
        d.apiName    = objectApiName;
        d.label      = MetadataCatalog.labelFor(objectApiName);
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

        Map<String, String> owd = MetadataCatalog.sharingModel(objectApiName);
        d.internalSharingModel = owd.get('internal');
        d.externalSharingModel = owd.get('external');

        return d;
    }

    private static List<PEDto.Grant> buildObjectGrants(
        PermissionResolver.Resolved r, String objectApiName
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
            ]) {
                Boolean isMuting = r.mutingParents.contains(op.ParentId);
                Map<String, Boolean> values = new Map<String, Boolean>{
                    'PermissionsRead'             => op.PermissionsRead,
                    'PermissionsCreate'           => op.PermissionsCreate,
                    'PermissionsEdit'             => op.PermissionsEdit,
                    'PermissionsDelete'           => op.PermissionsDelete,
                    'PermissionsViewAllRecords'   => op.PermissionsViewAllRecords,
                    'PermissionsModifyAllRecords' => op.PermissionsModifyAllRecords
                };
                for (String perm : values.keySet()) {
                    if (isMuting) {
                        mutedByPerm.get(perm).put(op.ParentId, values.get(perm));
                    } else {
                        grantedByPerm.get(perm).put(op.ParentId, values.get(perm));
                    }
                }
            }
        }

        List<PEDto.Grant> out = new List<PEDto.Grant>();
        for (String perm : PEConstants.OBJECT_PERM_ORDER) {
            out.add(PermissionResolver.applyGrant(
                perm,
                PEConstants.OBJECT_PERM_LABELS.get(perm),
                r,
                grantedByPerm.get(perm),
                mutedByPerm.get(perm)
            ));
        }
        return out;
    }

    private static List<PEDto.FieldPerm> buildFieldPerms(
        PermissionResolver.Resolved r, String objectApiName
    ) {
        Map<String, Schema.SObjectField> fieldMap = MetadataCatalog.fieldMap(objectApiName);

        Map<String, PEDto.FieldPerm> byApiName = new Map<String, PEDto.FieldPerm>();
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();

            PEDto.FieldPerm fp = new PEDto.FieldPerm();
            fp.apiName  = dfr.getName();
            fp.label    = dfr.getLabel();
            fp.dataType = String.valueOf(dfr.getType()).toLowerCase().capitalize();

            FlsClassifier.Verdict v = FlsClassifier.classify(dfr);
            fp.flsNotApplicable       = v.notApplicable;
            fp.flsNotApplicableReason = v.reason;

            byApiName.put(objectApiName + '.' + dfr.getName(), fp);
        }

        for (List<Id> batch : PESoqlChunker.chunk(r.effectiveParents)) {
            for (FieldPermissions f : [
                SELECT Field, ParentId, PermissionsRead, PermissionsEdit
                FROM FieldPermissions
                WHERE ParentId IN :batch AND SobjectType = :objectApiName
            ]) {
                PEDto.FieldPerm fp = byApiName.get(f.Field);
                if (fp == null) continue;

                PEDto.Source src = r.sourcesById.get(f.ParentId);
                if (f.PermissionsRead) {
                    fp.readable = true;
                    if (src != null) fp.readSources.add(src);
                }
                if (f.PermissionsEdit) {
                    fp.editable = true;
                    if (src != null) fp.editSources.add(src);
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
     */
    private static List<PEDto.RecordTypeRow> buildRecordTypes(String objectApiName) {
        List<PEDto.RecordTypeRow> out = new List<PEDto.RecordTypeRow>();

        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApiName);
        if (t == null) return out;

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