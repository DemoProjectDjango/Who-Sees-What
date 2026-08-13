/** Single home for magic values. Keeps labels out of query classes. */
public with sharing class PEConstants {

    public static final Integer USER_PAGE_SIZE     = 50;
    public static final Integer MAX_SEARCH_RESULTS = 200;   // cap before "refine your search"
    public static final Integer PARENT_ID_CHUNK    = 100;   // ParentId IN :ids batch size
    public static final Integer CURSOR_MAX_LENGTH  = 255;

    public static final String CUSTOM_PERMISSION = 'Use_Permission_Explorer';
    /**
     * PermissionSet.Type value for muting permission sets.
     *
     * UNVERIFIED. The observed Type picklist in a real org returns Session,
     * Regular, Group, Profile and Standard. No muting permission set was
     * available to confirm the value, so this is an assumption. Change it here —
     * one edit, one place — the moment an org can produce one.
     */
    public static final String MUTING_TYPE = 'Muting';
    public static final String CACHE_ORG_PARTITION     = 'PermissionExplorer';
    public static final String CACHE_SESSION_PARTITION = 'PermissionExplorer';

    /** Object-level permissions surfaced on sub-tab 1, in display order. */
    public static final Map<String, String> OBJECT_PERM_LABELS = new Map<String, String>{
        'PermissionsRead'           => 'Read',
        'PermissionsCreate'         => 'Create',
        'PermissionsEdit'           => 'Edit',
        'PermissionsDelete'        => 'Delete',
        'PermissionsViewAllRecords' => 'View All',
        'PermissionsModifyAllRecords'=> 'Modify All'
    };

    public static final List<String> OBJECT_PERM_ORDER = new List<String>{
        'PermissionsRead', 'PermissionsCreate', 'PermissionsEdit', 'PermissionsDelete',
        'PermissionsViewAllRecords', 'PermissionsModifyAllRecords'
    };
}