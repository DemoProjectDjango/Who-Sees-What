/**
 * The only class with `@AuraEnabled` methods. Gates, delegates, converts
 * exceptions into structured payloads. No business logic lives here.
 *
 * `with sharing` on the facade, but note that the services deliberately read
 * setup objects the running user may not own — which is the product's purpose,
 * gated by PEAccessGate and recorded by PEInspectionAuditLogger. That combination
 * is the security model, and it is documented as such for review.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.CyclomaticComplexity')
public with sharing class PermissionExplorerController {

    /* ---------------------------------------------------------------
     * Column 1
     * --------------------------------------------------------------- */

    /**
     * Provides filter picklists for the user search column after confirming the admin can use the tool.
     *
     * @return Profile, role, and user type options used to narrow permission inspections.
     */
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
     *
     * @param term Text entered by the admin to find users by name, username, or email.
     * @param profileId Optional profile filter selected in the user column.
     * @param roleId Optional role filter selected in the user column.
     * @param userType Optional Salesforce user type filter.
     * @param sortField Requested keyset-supported sort field.
     * @param cursor Opaque next-page cursor from the previous search response.
     * @param pageSize Requested number of rows for the user column.
     * @return Paged active-user search results for choosing a permission inspection subject.
     */
    @AuraEnabled
    @SuppressWarnings('PMD.ExcessiveParameterList')
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
     *
     * @param userId User selected as the permission inspection subject.
     * @param forceRefresh True when the admin clicked refresh and wants resolver caches rebuilt.
     * @return User header and app visibility payload for the selected user.
     */
    @AuraEnabled
    @SuppressWarnings('PMD.AvoidBooleanMethodParameters')
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

    /**
     * Returns recent login activity for the selected user when the running admin can read it.
     *
     * @param userId User whose login activity is being inspected.
     * @param maxRows Maximum number of login rows to return to the drill-down.
     * @return Login history payload with unavailable/truncated state for the UI.
     */
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

    /**
     * Returns directly assigned permission sets for the selected user summary drill-down.
     *
     * @param userId User whose direct permission set assignments are being inspected.
     * @return Permission set list matching the summary count and unreadable-set warnings.
     */
    @AuraEnabled
    public static PEDto.PermSetList getAssignedPermissionSets(Id userId) {
        try {
            PEAccessGate.assertAuthorisedAndLog('VIEW_PERM_SETS', userId, null);
            return PEUserDetailService.permissionSets(userId);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /**
     * Returns assigned permission set groups so admins can trace group-derived effective access.
     *
     * @param userId User whose permission set group assignments are being inspected.
     * @return Permission set group rows for the selected user's header drill-down.
     */
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

    /**
     * Returns object and tab permission rows for the selected app and inspected user.
     *
     * @param userId User whose app object access is being inspected.
     * @param appDeveloperName Developer name of the app selected by the admin.
     * @return Object rows that combine tab visibility, CRUD, and access-without-tab signals.
     */
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

    /**
     * Returns composite object detail for the modal opened from an app object row.
     *
     * @param userId User whose object and field permissions are being inspected.
     * @param objectApiName API name of the object selected by the admin.
     * @return Object detail payload with CRUD, FLS, record type, sharing, and section error data.
     */
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
     * License Inspector
     * --------------------------------------------------------------- */

    /**
     * Lists every user license, permission set license, package license and
     * usage-based entitlement in the org with total, used, and free seat
     * counts for the License Inspector tab.
     *
     * Not cacheable. The tab has its own explicit Refresh action — a
     * cacheable method can be served from Lightning's client-side storable
     * action cache even after this class is redeployed, which would make
     * that Refresh button lie about actually refreshing anything.
     *
     * @return License rows sorted by name.
     */
    @AuraEnabled
    public static String getLicenses() {
        try {
            PEAccessGate.assertAuthorised();
            return JSON.serialize(PELicenseInspectorService.getLicenses());
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /* ---------------------------------------------------------------
     * Org stats bar
     * --------------------------------------------------------------- */

    /**
     * Org-wide counts for the KPI bar atop Permission Explorer. Not
     * cacheable, same reasoning as getLicenses — cheap to compute, and a
     * stale cached count after config changes is worse than a repeat query.
     *
     * @return Six independently-optional org counts.
     */
    @AuraEnabled
    public static PEDto.OrgStats getOrgStats() {
        try {
            PEAccessGate.assertAuthorised();
            return PEOrgStatsService.getStats();
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /**
     * Same counts, cache bypassed. Wired to the refresh control on Home so an
     * admin who has just created a permission set can see it reflected without
     * waiting out the TTL.
     *
     * @return Six independently-optional org counts, freshly computed.
     */
    @AuraEnabled
    public static PEDto.OrgStats refreshOrgStats() {
        try {
            PEAccessGate.assertAuthorised();
            return PEOrgStatsService.getStats(true);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /* ---------------------------------------------------------------
     * Record-level reach
     * --------------------------------------------------------------- */

    /**
     * How many records of one object the selected user can reach.
     *
     * Logged, unlike the posture signals: this names a specific person and asks
     * how much data they can see, which is exactly the kind of question the
     * audit trail exists to record.
     *
     * @param userId The user being inspected.
     * @param objectApiName API name of the object to measure.
     * @return Reach figures with an explicit basis for each one.
     */
    @AuraEnabled
    public static PERecordAccessService.Reach getRecordReach(
        Id userId, String objectApiName
    ) {
        try {
            PEAccessGate.assertAuthorisedAndLog(
                'VIEW_RECORD_REACH', userId, objectApiName
            );
            PEAccessGate.assertInspectable(userId);
            return PERecordAccessService.getReach(userId, objectApiName);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /**
     * Why the selected user reaches what they reach, grouped by share reason.
     *
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @return Reason buckets, largest first.
     */
    @AuraEnabled
    public static List<PERecordListService.ReasonBucket> getReasonBreakdown(
        Id userId, String objectApiName
    ) {
        try {
            PEAccessGate.assertAuthorised();
            PEAccessGate.assertInspectable(userId);
            return PERecordListService.getReasonBreakdown(userId, objectApiName);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /**
     * One page of records with the selected user's access to each.
     *
     * Logged once per page: paging through someone's visible data is the same
     * act as inspecting it, and a trail that records only the first page would
     * understate what was looked at.
     *
     * @param userId The user being inspected.
     * @param objectApiName API name of the object.
     * @param mode ACCESSIBLE or ALL.
     * @param searchTerm Free text, ALL mode only.
     * @param sortField Field to order by.
     * @param cursor Cursor from the previous page, or null.
     * @return A page of records plus the next cursor.
     */
    @AuraEnabled
    public static PERecordListService.RecordPage getRecordPage(
        Id userId, String objectApiName, String mode,
        String searchTerm, String sortField, String cursor
    ) {
        try {
            PEAccessGate.assertAuthorisedAndLog(
                'VIEW_RECORD_LIST', userId, objectApiName
            );
            PEAccessGate.assertInspectable(userId);
            return PERecordListService.getPage(
                userId, objectApiName, mode, searchTerm, sortField, cursor
            );
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /* ---------------------------------------------------------------
     * Posture
     * --------------------------------------------------------------- */

    /**
     * Actionable access-posture signals for the Home dashboard.
     *
     * Not logged. These are org-level counts about configuration, not an
     * inspection of any person, so there is no subject to record.
     *
     * @return Posture signals plus licence utilisation.
     */
    @AuraEnabled
    public static PEPostureService.Posture getPosture() {
        try {
            PEAccessGate.assertAuthorised();
            return PEPostureService.get();
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /**
     * Same signals, cache bypassed. Wired to the refresh control on Home.
     *
     * @return Freshly computed posture signals.
     */
    @AuraEnabled
    public static PEPostureService.Posture refreshPosture() {
        try {
            PEAccessGate.assertAuthorised();
            return PEPostureService.get(true);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /* ---------------------------------------------------------------
     * Inspection log
     * --------------------------------------------------------------- */

    /**
     * Recent inspection history for the Home panel.
     *
     * Not cacheable: the whole point of an audit panel is that it reflects what
     * just happened, and a client-cached page would show an admin a trail that
     * predates their own last inspection.
     *
     * Reading the log is itself gated but deliberately NOT logged. Logging a
     * read of the log makes the trail grow every time someone looks at it, and
     * an audit trail that records its own observation is noise, not evidence.
     *
     * @param inspectorId Optional filter to one inspector.
     * @param subjectId Optional filter to one inspected user.
     * @param rowLimit Maximum rows to return; the service clamps this.
     * @return A page of inspection history with header counts.
     */
    @AuraEnabled
    public static PEInspectionLogService.LogPage getRecentInspections(
        Id inspectorId, Id subjectId, Integer rowLimit
    ) {
        try {
            PEAccessGate.assertAuthorised();
            return PEInspectionLogService.getRecent(inspectorId, subjectId, rowLimit);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /**
     * Lists the users currently holding a given license, for the
     * "view users" drill-down on the License Inspector table.
     *
     * @param licenseId Id of the license row selected in the table.
     * @param licenseType Discriminator returned alongside licenseId by getLicenses.
     * @return Users assigned that license.
     */
    @AuraEnabled
    public static String getLicenseUsers(Id licenseId, String licenseType) {
        try {
            PEAccessGate.assertAuthorisedAndLog(
                'VIEW_LICENSE_USERS', null, licenseType + ':' + licenseId
            );
            return JSON.serialize(
                PELicenseInspectorService.getLicenseUsers(licenseId, licenseType)
            );
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /* ---------------------------------------------------------------
     * Refresh
     * --------------------------------------------------------------- */

    /**
     * Bumps the version token rather than clearing the partition.
     *
     * @return Fresh cache version token that makes later permission inspections recompute resolver data.
     */
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
        s.department        = u.Department;
        s.managerName       = u.Manager != null ? u.Manager.Name : null;
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
     *
     * @param e Exception raised by the controller or delegated service.
     * @return AuraHandledException containing a serialized ErrorInfo payload for the LWC.
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
