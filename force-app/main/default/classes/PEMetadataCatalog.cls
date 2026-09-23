/**
 * Org-level structure: app → tab → object map, field lists, OWD, role tree.
 * Identical for every admin using the tool, so it lives in the org partition
 * and is shared.
 *
 * Caveat that matters: TabDefinition and AppMenuItem are filtered by the
 * *running* user's access, not the target user's. Safe as org structure,
 * unsafe as the source of truth for the target user's visibility.
 */
public with sharing class PEMetadataCatalog {

    /**
     * Transaction-level cache for Schema.getGlobalDescribe().
     * Avoids rebuilding/retrieving the same describe map repeatedly while
     * preserving the exact same metadata and lookup behavior.
     */
    private static Map<String, Schema.SObjectType> globalDescribeCache;

    /** App tab metadata row used to line up navigation visibility with object permissions. */
    public class TabInfo {
        public String tabName;        // PermissionSetTabSetting.Name
        public String label;
        public String objectApiName;  // null for Visualforce / web / Reports tabs
        public String tabType;
    }

    /**
     * Returns the transaction-cached global describe map.
     *
     * @return Global object describe map keyed by object API name.
     */
    private static Map<String, Schema.SObjectType> globalDescribe() {
        if (globalDescribeCache == null) {
            globalDescribeCache = Schema.getGlobalDescribe();
        }
        return globalDescribeCache;
    }

    /* ----------------------------- tabs ----------------------------- */

    /**
     * Returns the org-level tab catalog used when an admin drills into app visibility.
     *
     * The result does not vary by app: TabDefinition has no app association, so
     * this is the org's full tab list and the app → tab join happens downstream.
     * It is therefore cached under a single fixed key rather than one key per
     * app, which would store an identical 2,000-row list once per app and put
     * needless pressure on the org cache partition.
     *
     * @param appDeveloperName Developer name of the app selected in the UI. Accepted
     *                         for call-site symmetry with the other catalog lookups;
     *                         the tab list itself is org-wide.
     * @return Tab metadata rows used to join app navigation with permission set tab settings.
     */
    public static List<TabInfo> getAppTabs(String appDeveloperName) {
        final String key = 'appTabsAll';
        Object cached = PECacheManager.orgGet(key);
        if (cached != null) {
            return (List<TabInfo>) cached;
        }

        // Materialised into a List deliberately, NOT iterated as an inline SOQL
        // for-loop. A SOQL for-loop opens a query cursor and pages in batches of
        // 200 via queryMore(), and TabDefinition does not support queryMore():
        // it fails with "TabDefinition does not support queryMore(), use LIMIT to
        // restrict the results to a single batch" in any org with more than 200
        // tabs. LIMIT alone does not help — the cursor is created by the loop
        // form, so the query must be assigned to a List and the List iterated.
        List<TabDefinition> tabs = [
            SELECT DurableId, Name, Label, SobjectName
            FROM TabDefinition
            WITH USER_MODE
            ORDER BY Label
            LIMIT 2000
        ];

        List<TabInfo> out = new List<TabInfo>();
        for (TabDefinition t : tabs) {
            TabInfo info = new TabInfo();

            // PermissionSetTabSetting addresses standard object tabs as
            // 'standard-<Object>' and custom tabs by developer name. TabDefinition
            // exposes no IsCustom flag, so the '__' suffix is the available signal.
            //
            // The null guard has to wrap BOTH tests. Written as
            //   t.Name != null && t.Name.endsWith('__c') || t.Name.contains('__')
            // && binds tighter than ||, so a null Name makes the first group false
            // and evaluation falls through to contains() on a null — which throws.
            //
            // endsWith('__c') is subsumed by contains('__') and is kept only as
            // documentation of the common case.
            //
            // CONFIRM during the Phase 0 spike — custom tabs on standard objects
            // and packaged tabs with a namespace prefix are the edge cases, and a
            // subscriber org with managed packages installed will have the latter.
            Boolean isCustom = t.Name != null
                && (t.Name.endsWith('__c') || t.Name.contains('__'));

            info.tabName = isCustom ? t.Name : 'standard-' + t.Name;
            info.label = t.Label;
            info.objectApiName = String.isBlank(t.SobjectName) ? null : t.SobjectName;
            info.tabType = String.isBlank(t.SobjectName) ? 'NonObject' : 'Object';
            out.add(info);
        }

        PECacheManager.orgPut(key, out, 3600);
        return out;
    }

    /* ----------------------------- describes ----------------------------- */

    /**
     * Resolves an object label for permission inspection rows without failing on unavailable metadata.
     *
     * @param objectApiName API name of the object being displayed.
     * @return Object label when describe metadata is available, otherwise the API name.
     */
    public static String labelFor(String objectApiName) {
        Schema.SObjectType t = globalDescribe().get(objectApiName);
        return t == null ? objectApiName : t.getDescribe().getLabel();
    }

    /**
     * Retrieves the field describe map used to build field-level security rows for an object.
     *
     * @param objectApiName API name of the object selected in object detail.
     * @return Field describe map keyed by field API name.
     */
    public static Map<String, Schema.SObjectField> fieldMap(String objectApiName) {
        Schema.SObjectType t = globalDescribe().get(objectApiName);

        if (t == null) {
            throw PermissionExplorerException.build(
                PermissionExplorerException.NOT_FOUND,
                'That object is not available in this org.',
                false
            );
        }

        return t.getDescribe().fields.getMap();
    }

    /* ----------------------------- sharing model ----------------------------- */

    /**
     * Returns internal and external org-wide defaults for the object so admins can interpret object access.
     *
     * @param objectApiName API name of the object selected in object detail.
     * @return Map containing internal and external sharing model values, or Unknown when metadata is not readable.
     */
    public static Map<String, String> sharingModel(String objectApiName) {
        String key = 'owd' + objectApiName;
        Object cached = PECacheManager.orgGet(key);

        if (cached != null) {
            return (Map<String, String>) cached;
        }

        Map<String, String> out = new Map<String, String>{
            'internal' => 'Unknown',
            'external' => 'Unknown'
        };

        // Already a List assignment with LIMIT 1, so no cursor is opened.
        // EntityDefinition has the same queryMore() restriction as TabDefinition.
        List<EntityDefinition> defs = [
            SELECT InternalSharingModel, ExternalSharingModel
            FROM EntityDefinition
            WHERE QualifiedApiName = :objectApiName
            WITH USER_MODE
            LIMIT 1
        ];

        if (!defs.isEmpty()) {
            out.put('internal', defs[0].InternalSharingModel);
            out.put('external', defs[0].ExternalSharingModel);
        }

        PECacheManager.orgPut(key, out, 3600);
        return out;
    }
}