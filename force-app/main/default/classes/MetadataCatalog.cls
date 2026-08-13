/**
 * Org-level structure: app → tab → object map, field lists, OWD, role tree.
 * Identical for every admin using the tool, so it lives in the org partition
 * and is shared.
 *
 * Caveat that matters: TabDefinition and AppMenuItem are filtered by the
 * *running* user's access, not the target user's. Safe as org structure,
 * unsafe as the source of truth for the target user's visibility.
 */
public with sharing class MetadataCatalog {

    public class TabInfo {
        public String tabName;        // PermissionSetTabSetting.Name
        public String label;
        public String objectApiName;  // null for Visualforce / web / Reports tabs
        public String tabType;
    }

    /* ----------------------------- tabs ----------------------------- */

    public static List<TabInfo> getAppTabs(String appDeveloperName) {
        String key = 'appTabs' + appDeveloperName;
        Object cached = PECacheManager.orgGet(key);
        if (cached != null) return (List<TabInfo>) cached;

        List<TabInfo> out = new List<TabInfo>();
        for (TabDefinition t : [
            SELECT DurableId, Name, Label, SobjectName
            FROM TabDefinition
            ORDER BY Label
        ]) {
            TabInfo info = new TabInfo();
            // PermissionSetTabSetting addresses standard object tabs as
            // 'standard-<Object>' and custom tabs by developer name. TabDefinition
            // exposes no IsCustom flag, so the '__' suffix is the available signal.
            // CONFIRM during the Phase 0 spike — custom tabs on standard objects
            // and packaged tabs with a namespace prefix are the edge cases.
            Boolean isCustom = t.Name != null && t.Name.endsWith('__c') || t.Name.contains('__');
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

    public static String labelFor(String objectApiName) {
        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApiName);
        return t == null ? objectApiName : t.getDescribe().getLabel();
    }

    public static Map<String, Schema.SObjectField> fieldMap(String objectApiName) {
        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApiName);
        if (t == null) {
            throw PermissionExplorerException.build(
                PermissionExplorerException.NOT_FOUND,
                'That object is not available in this org.', false
            );
        }
        return t.getDescribe().fields.getMap();
    }

    /* ----------------------------- sharing model ----------------------------- */

    public static Map<String, String> sharingModel(String objectApiName) {
        String key = 'owd' + objectApiName;
        Object cached = PECacheManager.orgGet(key);
        if (cached != null) return (Map<String, String>) cached;

        Map<String, String> out = new Map<String, String>{
            'internal' => 'Unknown', 'external' => 'Unknown'
        };
        List<EntityDefinition> defs = [
            SELECT InternalSharingModel, ExternalSharingModel
            FROM EntityDefinition
            WHERE QualifiedApiName = :objectApiName
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