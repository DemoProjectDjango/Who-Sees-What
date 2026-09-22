/**
 * Data transfer objects for the Permission Explorer UI.
 *
 * Every field is `@AuraEnabled public` so LWC receives plain objects.
 * Deliberately `public`, never `global` — global members in a managed package
 * are a permanent API commitment that can never be removed.
 */
public with sharing class PEDto {

    /* ---------------------------------------------------------------
     * Shared
     * --------------------------------------------------------------- */

    /** Where a permission came from. Renders as one chip. */
    public class Source {
        @AuraEnabled public Id parentId;              // PermissionSet Id
        @AuraEnabled public String label;             // 'Sales User', 'Sales_Power_User'
        @AuraEnabled public String kind;              // profile | permset | group | muting
        @AuraEnabled public String groupLabel;        // set when kind = group
        @AuraEnabled public Boolean isOutdatedGroup;  // PermissionSetGroup.Status != Updated

        /**
         * The Id a Setup deep link actually needs, which is NOT always parentId.
         *
         * For a profile source, parentId is the profile-owned PermissionSet
         * (0PS…) because that is what ObjectPermissions.ParentId joins on — but
         * Setup addresses a profile by its ProfileId (00e…). Keeping the two
         * apart is the whole reason this field exists; deriving one from the
         * other on the client is not possible.
         */
        @AuraEnabled public Id linkId;

        /** The owning group, when one is known. Set for kind = group | muting. */
        @AuraEnabled public Id groupId;

        /**
         * False when the source has no page an admin can open: protected
         * permission sets from managed packages, and muting sets with no known
         * group. A link that 404s is worse than no link, so the server decides
         * this rather than letting the client guess.
         */
        @AuraEnabled public Boolean linkable;

        /**
         * Creates a source chip that tells an admin which profile, permission set,
         * group, or muting set produced a permission result.
         *
         * @param parentId PermissionSet-family parent Id used by permission metadata rows.
         * @param label Display label shown in the inspection UI.
         * @param kind Source category used for grouping, linking, and muting treatment.
         */
        public Source(Id parentId, String label, String kind) {
            this.parentId = parentId;
            this.label = label;
            this.kind = kind;
            this.isOutdatedGroup = false;
            this.linkId = parentId;   // correct for permset/group; overridden for profile
            this.linkable = true;
        }
    }

    /** A single resolved permission: granted or not, and why. */
    public class Grant {
        @AuraEnabled public String name;      // 'PermissionsViewAllData'
        @AuraEnabled public String label;     // 'View All Data'
        @AuraEnabled public Boolean granted;
        @AuraEnabled public Boolean muted;    // granted somewhere, then muted
        @AuraEnabled public List<Source> sources = new List<Source>();

        /**
         * Creates an ungranted permission row that the resolver can mark with
         * grants, mutes, and explanatory sources.
         *
         * @param name Salesforce permission API name being evaluated.
         * @param label Admin-facing label for the permission row.
         */
        public Grant(String name, String label) {
            this.name = name;
            this.label = label;
            this.granted = false;
            this.muted = false;
        }
    }

    /**
     * Wrapper for keyset-paginated results. No totalCount, by design.
     *
     * Concrete row type, not List<Object>: @AuraEnabled cannot serialise a
     * generic Object list, and it fails at runtime rather than compile time.
     */
    public class PagedResult {
        @AuraEnabled public List<UserRow> records = new List<UserRow>();
        @AuraEnabled public Boolean hasMore = false;
        @AuraEnabled public String nextCursor;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Boolean capReached = false;  // drives "refine your search"
    }

    /** Structured error so the UI can distinguish causes, not just show a string. */
    public class ErrorInfo {
        @AuraEnabled public String cause;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean retryable;

        /**
         * Creates a structured service error for partial failures that the LWC can
         * render without losing already-resolved permission inspection data.
         *
         * @param cause Stable product error code.
         * @param message Admin-facing explanation of the failed inspection section.
         * @param retryable True when the UI should present the failure as worth retrying.
         */
        public ErrorInfo(String cause, String message, Boolean retryable) {
            this.cause = cause;
            this.message = message;
            this.retryable = retryable;
        }
    }

    /* ---------------------------------------------------------------
     * Column 1 — users
     * --------------------------------------------------------------- */

    /** One row in the user column. Thin, because the column is paginated. */
    public class UserRow {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String username;
        @AuraEnabled public String profileName;
        @AuraEnabled public String roleName;
        @AuraEnabled public Datetime lastLogin;
        @AuraEnabled public Boolean isFrozen = false;
    }

    /** Header shown once a user is selected. */
    public class UserSummary {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String username;
        @AuraEnabled public String email;
        @AuraEnabled public String department;
        @AuraEnabled public String managerName;
        @AuraEnabled public String profileName;
        @AuraEnabled public Id profileId;
        @AuraEnabled public String roleName;
        @AuraEnabled public String licenseName;
        @AuraEnabled public String userType;
        @AuraEnabled public Datetime lastLogin;
        @AuraEnabled public Boolean isFrozen = false;
        @AuraEnabled public Integer permSetCount = 0;
        @AuraEnabled public Integer permSetGroupCount = 0;
        @AuraEnabled public Integer mutingSetCount = 0;
        @AuraEnabled public Integer unreadableCount = 0;
        @AuraEnabled public List<String> outdatedGroups = new List<String>();
        @AuraEnabled public Datetime resolvedAt;   // feeds the "as of HH:MM" stale marker
    }

    /* ---------------------------------------------------------------
     * Header drill-downs — login history, permission sets, groups
     *
     * These three payloads exist so the counts in the summary header stop
     * being dead ends. Each one is sourced from the same resolver pass that
     * produced the count, so the list can never disagree with the number
     * printed above it.
     * --------------------------------------------------------------- */

    /** One login history row shown in the selected user's header drill-down. */
    public class LoginEvent {
        @AuraEnabled public Datetime loginTime;
        @AuraEnabled public String status;
        @AuraEnabled public String loginType;
        @AuraEnabled public String sourceIp;
        @AuraEnabled public String application;
        @AuraEnabled public String browser;
        @AuraEnabled public String platform;
    }

    /**
     * Login history is the one panel in this tool that can be structurally
     * unavailable rather than empty. Reading LoginHistory requires a
     * high-privilege permission the packaged permission set deliberately does
     * not grant, so "cannot read" and "never signed in" must never render the
     * same way.
     */
    public class LoginHistoryResult {
        @AuraEnabled public List<LoginEvent> events = new List<LoginEvent>();
        @AuraEnabled public Integer appliedLimit = 0;
        /** True when the result filled the limit — there is probably more. */
        @AuraEnabled public Boolean truncated = false;
        /** Non-null when the running user cannot read LoginHistory at all. */
        @AuraEnabled public String notAvailableReason;
        @AuraEnabled public String retentionNote =
            'Salesforce retains roughly six months of login history. Older sign-ins are not available here.';
    }

    /** Direct permission set assignment row shown from the selected user's summary count. */
    public class PermSetRow {
        @AuraEnabled public Id permSetId;
        @AuraEnabled public String label;
        @AuraEnabled public String apiName;
        @AuraEnabled public String setType;      // Regular | Session | Standard | ...
        /** False for managed-package sets whose label the running user cannot read. */
        @AuraEnabled public Boolean isReadable = true;
    }

    /**
     * Direct assignments only, matching UserSummary.permSetCount exactly.
     * `viaGroupCount` names the sets that apply through an assigned group so
     * the gap between this list and effective access is stated, not hidden.
     */
    public class PermSetList {
        @AuraEnabled public List<PermSetRow> directSets = new List<PermSetRow>();
        @AuraEnabled public Integer viaGroupCount = 0;
        @AuraEnabled public Integer unreadableCount = 0;
    }

    /** Permission set group assignment row used to explain group-derived effective access. */
    public class PermSetGroupRow {
        @AuraEnabled public Id groupId;
        @AuraEnabled public String developerName;
        @AuraEnabled public String masterLabel;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isOutdated = false;
    }

    /* ---------------------------------------------------------------
     * Column 2 — apps
     * --------------------------------------------------------------- */

    /** App visibility row shown in the second column of the admin inspection workspace. */
    public class AppRow {
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public String appType;      // Lightning | Classic | Connected
        @AuraEnabled public Boolean visible;
        @AuraEnabled public Boolean isDefault;
        @AuraEnabled public List<Source> sources = new List<Source>();
        /** True when visibility came from the degraded AppMenuItem fallback. */
        @AuraEnabled public Boolean visibilityEstimated = false;
    }

    /** Column 2 payload. Carries the degradation flag for the whole column. */
    public class AppList {
        @AuraEnabled public List<AppRow> apps = new List<AppRow>();
        @AuraEnabled public String resolutionMode;   // APP_MENU_ITEM (only mode)
        @AuraEnabled public Boolean setupRequired = false;
        @AuraEnabled public String setupMessage;
    }

    /** Returned by resolveUser — one round trip for header + apps. */
    public class UserContext {
        @AuraEnabled public UserSummary summary;
        @AuraEnabled public AppList apps;
    }

    /* ---------------------------------------------------------------
     * Modal rail — objects and tabs
     * --------------------------------------------------------------- */

    /** Object or tab row shown when an admin opens app visibility details. */
    public class ObjectRow {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isObjectTab;     // false for VF / web / Reports tabs
        @AuraEnabled public String tabVisibility;    // DefaultOn | DefaultOff | Hidden | NoTab
        @AuraEnabled public List<Source> tabSources = new List<Source>();
        @AuraEnabled public Boolean canRead = false;
        @AuraEnabled public Boolean canCreate = false;
        @AuraEnabled public Boolean canEdit = false;
        @AuraEnabled public Boolean canDelete = false;
        @AuraEnabled public Boolean viewAll = false;
        @AuraEnabled public Boolean modifyAll = false;
        /** True for the "reachable by API but not in navigation" group. */
        @AuraEnabled public Boolean accessWithoutTab = false;
    }

    /* ---------------------------------------------------------------
     * Modal detail
     * --------------------------------------------------------------- */

    /** Field-level security row used in object detail to show readable/editable outcomes and sources. */
    public class FieldPerm {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String dataType;
        @AuraEnabled public Boolean readable = false;
        @AuraEnabled public Boolean editable = false;
        @AuraEnabled public List<Source> readSources = new List<Source>();
        @AuraEnabled public List<Source> editSources = new List<Source>();
        /** When true, absence of FLS is structural, not a permission gap. */
        @AuraEnabled public Boolean flsNotApplicable = false;
        @AuraEnabled public String flsNotApplicableReason;
    }

    /** Composite object detail payload that backs the modal tabs for CRUD, FLS, record types, and sharing context. */
    public class ObjectDetail {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public List<Grant> objectPermissions = new List<Grant>();
        @AuraEnabled public List<FieldPerm> fields = new List<FieldPerm>();
        @AuraEnabled public String internalSharingModel;
        @AuraEnabled public String externalSharingModel;
        @AuraEnabled public Datetime resolvedAt;
        /** Populated per section so one failure does not blank the modal. */
        @AuraEnabled public ErrorInfo fieldsError;
        @AuraEnabled public List<RecordTypeRow> recordTypes = new List<RecordTypeRow>();
    }

    /** Org-level record type row displayed with an explicit running-user availability caveat. */
    public class RecordTypeRow {
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isActive = false;
        @AuraEnabled public Boolean isMaster = false;
        /** Running user's access, NOT the target user's. Label it as such. */
        @AuraEnabled public Boolean availableToRunningUser = false;
    }

    /* ---------------------------------------------------------------
     * License Inspector
     * --------------------------------------------------------------- */

    /** One row of the license table: a User License, Permission Set License,
        Package License, or Usage-Based Entitlement. */
    public class LicenseRow {
        @AuraEnabled public Id licenseId;
        @AuraEnabled public String licenseType;   // 'UserLicense' | 'PermissionSetLicense' | 'PackageLicense' | 'UsageEntitlement'
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Integer total;        // null when isUnlimited
        @AuraEnabled public Integer used = 0;
        @AuraEnabled public Integer free;         // null when isUnlimited
        @AuraEnabled public Boolean isUnlimited = false;
        @AuraEnabled public Datetime expirationDate;  // PSL/PackageLicense expiry, or entitlement period end
        @AuraEnabled public String frequency;         // set for usage-based entitlements only, e.g. 'Daily'
    }

    /** One user holding a license, shown in the "view users" drill-down. */
    public class LicenseUserRow {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String username;
        @AuraEnabled public String profileName;
        @AuraEnabled public Boolean isActive = true;
    }

    /* ---------------------------------------------------------------
     * Org stats bar
     * --------------------------------------------------------------- */

    /**
     * Org-wide counts for the top KPI bar. Every field is nullable and
     * independently optional — one count failing to compute (an object this
     * running user cannot query, say) hides that one card, not the whole
     * bar. See PEOrgStatsService for how each is derived.
     */
    public class OrgStats {
        @AuraEnabled public Integer activeUsers;
        @AuraEnabled public Integer permissionSets;
        @AuraEnabled public Integer permissionSetGroups;
        @AuraEnabled public Integer profiles;
        @AuraEnabled public Integer reachableApps;
        @AuraEnabled public Integer objectsWithAccess;
    }
}
