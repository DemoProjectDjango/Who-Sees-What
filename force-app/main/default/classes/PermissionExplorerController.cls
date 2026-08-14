/**
 * The only class with `@AuraEnabled` methods. Gates, delegates, converts
 * exceptions into structured payloads. No business logic lives here.
 *
 * `with sharing` on the facade, but note that the services deliberately read
 * setup objects the running user may not own — which is the product's purpose,
 * gated by PEAccessGate and recorded by PEInspectionAuditLogger. That combination
 * is the security model, and it is documented as such for review.
 */
public with sharing class PermissionExplorerController {

    /* ---------------------------------------------------------------
     * Column 1
     * --------------------------------------------------------------- */

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getFilterOptions() {
        try {
            PEAccessGate.assertAuthorised();
            return PEUserSearchService.filterOptions();
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /**
     * Not cacheable: the cursor makes each page a distinct call anyway, and
     * @AuraEnabled(cacheable=true) would strand pages in the client cache after
     * a refresh-token bump.
     */
    @AuraEnabled
    public static PEDto.PagedResult searchUsers(
        String term, Id profileId, Id roleId, String userType,
        String sortField, String cursor, Integer pageSize
    ) {
        try {
            PEAccessGate.assertAuthorised();

            PEUserSearchService.Filters f = new PEUserSearchService.Filters();
            f.term      = term;
            f.profileId = profileId;
            f.roleId    = roleId;
            f.userType  = userType;
            f.sortField = String.isBlank(sortField) ? 'LastLoginDate' : sortField;

            return PEUserSearchService.search(f, cursor, pageSize);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /* ---------------------------------------------------------------
     * User selection — the one expensive computation
     * --------------------------------------------------------------- */

    /**
     * Runs the resolver, caches the effective parent Ids, and returns the
     * summary header plus the visible app list in the same round trip.
     */
    @AuraEnabled
    public static PEDto.UserContext resolveUser(Id userId, Boolean forceRefresh) {
        try {
            PEAccessGate.assertAuthorisedAndLog('RESOLVE_USER', userId, null);

            User u = PEAccessGate.assertInspectable(userId);
            PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(
                userId, forceRefresh == true
            );

            PEDto.UserContext ctx = new PEDto.UserContext();
            ctx.summary = buildSummary(u, r);
            ctx.apps = PEAppVisibilityService.getVisibleApps(userId, r);
            return ctx;
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /* ---------------------------------------------------------------
     * Header drill-downs
     *
     * Fetched on modal open rather than folded into resolveUser. Most
     * inspections never open them, and login history in particular is a query
     * against an object the running user may not be able to read at all —
     * paying for it on every user selection would be paying for nothing.
     * --------------------------------------------------------------- */

    @AuraEnabled
    public static PEDto.LoginHistoryResult getLoginHistory(Id userId, Integer maxRows) {
        try {
            PEAccessGate.assertAuthorisedAndLog('VIEW_LOGIN_HISTORY', userId, null);
            PEAccessGate.assertInspectable(userId);
            return PEUserDetailService.loginHistory(userId, maxRows);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static PEDto.PermSetList getAssignedPermissionSets(Id userId) {
        try {
            PEAccessGate.assertAuthorisedAndLog('VIEW_PERM_SETS', userId, null);
            return PEUserDetailService.permissionSets(userId);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static List<PEDto.PermSetGroupRow> getAssignedPermissionSetGroups(Id userId) {
        try {
            PEAccessGate.assertAuthorisedAndLog('VIEW_PERM_SET_GROUPS', userId, null);
            return PEUserDetailService.permissionSetGroups(userId);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /* ---------------------------------------------------------------
     * App selection — populates the modal rail
     * --------------------------------------------------------------- */

    @AuraEnabled
    public static List<PEDto.ObjectRow> getAppObjects(Id userId, String appDeveloperName) {
        try {
            PEAccessGate.assertAuthorisedAndLog('GET_APP_OBJECTS', userId, appDeveloperName);
            PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(userId);
            return PEAccessQueryService.getAppObjects(r, appDeveloperName);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /* ---------------------------------------------------------------
     * Object selection — one composite call, not four
     * --------------------------------------------------------------- */

    @AuraEnabled
    public static PEDto.ObjectDetail getObjectDetail(Id userId, String objectApiName) {
        try {
            PEAccessGate.assertAuthorisedAndLog('GET_OBJECT_DETAIL', userId, objectApiName);
            PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(userId);
            return PEAccessQueryService.getObjectDetail(r, objectApiName);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /* ---------------------------------------------------------------
     * Refresh
     * --------------------------------------------------------------- */

    /** Bumps the version token rather than clearing the partition. */
    @AuraEnabled
    public static String refreshCache() {
        try {
            PEAccessGate.assertAuthorised();
            return PECacheManager.bumpVersionToken();
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /* ---------------------------------------------------------------
     * Internals
     * --------------------------------------------------------------- */

    private static PEDto.UserSummary buildSummary(User u, PEPermissionResolver.Resolved r) {
        PEDto.UserSummary s = new PEDto.UserSummary();
        s.userId            = u.Id;
        s.name              = u.Name;
        s.username          = u.Username;
        s.email             = u.Email;
        s.profileId         = u.ProfileId;
        s.profileName       = u.Profile != null ? u.Profile.Name : null;
        s.roleName          = u.UserRole != null ? u.UserRole.Name : null;
        s.licenseName       = u.Profile != null && u.Profile.UserLicense != null
                              ? u.Profile.UserLicense.Name : null;
        s.userType          = u.UserType;
        s.lastLogin         = u.LastLoginDate;
        s.isFrozen          = PEUserSearchService.isFrozen(u.Id);
        s.permSetCount      = r.permSetCount;
        s.permSetGroupCount = r.permSetGroupCount;
        s.mutingSetCount    = r.mutingParents.size();
        s.unreadableCount   = r.unreadableCount;
        s.outdatedGroups    = r.outdatedGroups;
        s.resolvedAt        = r.resolvedAt;
        return s;
    }

    /**
     * Serialises the structured cause into the AuraHandledException message as
     * JSON, so the client can branch on cause instead of matching strings.
     */
    private static AuraHandledException toAura(Exception e) {
        PEDto.ErrorInfo info;
        if (e instanceof PermissionExplorerException) {
            info = ((PermissionExplorerException) e).toInfo();
        } else if (e instanceof System.LimitException) {
            info = new PEDto.ErrorInfo(
                PermissionExplorerException.LIMIT_EXCEEDED,
                'This org is larger than one request can analyse. Narrow the scope and try again.',
                false
            );
        } else {
            info = new PEDto.ErrorInfo(
                PermissionExplorerException.UNKNOWN, e.getMessage(), true
            );
        }
        AuraHandledException aura = new AuraHandledException(JSON.serialize(info));
        aura.setMessage(JSON.serialize(info));
        return aura;
    }
}
