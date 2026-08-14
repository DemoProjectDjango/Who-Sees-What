/**
 * * Two regions of loginHistory() are permanently uncoverable, by design of the
 * platform rather than by omission: the not-readable branch, because
 * Schema.isAccessible() cannot be made false from a test (System.runAs
 * enforces sharing, not CRUD), and the query loop, because LoginHistory rows
 * cannot be inserted. This caps the class near 57% and that is expected.
 * Backs the three drill-downs hanging off the user summary header: login
 * history, directly assigned permission sets, and assigned permission set
 * groups.
 *
 * Two of the three are free. `PEPermissionResolver.resolve()` already computed
 * the assignments and cached them, so the permission set and group lists cost
 * nothing beyond a cache read and are guaranteed to agree with the counts
 * printed in the header — the same pass produced both.
 *
 * Login history is the exception, and it is the only panel in this tool that
 * can be structurally unavailable rather than merely empty. LoginHistory is
 * readable only by a user holding a high-privilege setup permission, which the
 * packaged permission set deliberately does not grant. So the failure is
 * detected and named rather than surfaced as an error or, worse, as an empty
 * list that reads like "this user never signed in".
 */
public with sharing class PEUserDetailService {

    private static final Integer DEFAULT_LOGIN_LIMIT = 50;
    private static final Integer MAX_LOGIN_LIMIT     = 200;

    /* ---------------------------------------------------------------
     * Login history
     * --------------------------------------------------------------- */

    public static PEDto.LoginHistoryResult loginHistory(Id userId, Integer requestedLimit) {
        PEDto.LoginHistoryResult out = new PEDto.LoginHistoryResult();

        Integer lim = requestedLimit;
        if (lim == null || lim <= 0 || lim > MAX_LOGIN_LIMIT) {
            lim = DEFAULT_LOGIN_LIMIT;
        }
        out.appliedLimit = lim;

        if (!canReadLoginHistory()) {
            out.notAvailableReason =
                'Login history is not readable by your user. Salesforce restricts LoginHistory to ' +
                'users with the "Manage Users" permission, which Permission Explorer does not grant. ' +
                'Everything else on this screen is unaffected.';
            return out;
        }

        try {
            for (LoginHistory lh : [
                SELECT LoginTime, Status, LoginType, SourceIp,
                       Application, Browser, Platform
                FROM LoginHistory
                WHERE UserId = :userId
                ORDER BY LoginTime DESC
                LIMIT :lim
            ]) {
                PEDto.LoginEvent e = new PEDto.LoginEvent();
                e.loginTime   = lh.LoginTime;
                e.status      = lh.Status;
                e.loginType   = lh.LoginType;
                e.sourceIp    = lh.SourceIp;
                e.application = lh.Application;
                e.browser     = lh.Browser;
                e.platform    = lh.Platform;
                out.events.add(e);
            }
        } catch (Exception ex) {
            // isAccessible() said yes and the query still failed. Say so plainly
            // rather than letting it surface as a generic panel error.
            out.notAvailableReason =
                'Login history could not be read: ' + ex.getMessage();
            out.events.clear();
            return out;
        }

        // Filling the limit is not proof of more rows, but it is the only signal
        // available without a second query, so it is worded as a possibility.
        out.truncated = out.events.size() == lim;
        return out;
    }

    /**
     * Describe-based check, deliberately not a try/catch around the query.
     * A caught QueryException gives the same outcome but costs a query against
     * an object we already know we cannot read.
     */
    private static Boolean canReadLoginHistory() {
        try {
            return Schema.SObjectType.LoginHistory.isAccessible();
        } catch (Exception e) {
            return false;
        }
    }

    /* ---------------------------------------------------------------
     * Assignments — read straight off the resolver
     * --------------------------------------------------------------- */

    /**
     * Direct assignments only, which is what `permSetCount` counts. Sets that
     * apply through a group are reported as a number, not silently folded in:
     * listing them here would make the modal disagree with the header, and
     * omitting them entirely would imply they do not apply.
     */
    public static PEDto.PermSetList permissionSets(Id userId) {
        PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(userId);

        PEDto.PermSetList out = new PEDto.PermSetList();
        out.directSets      = r.directPermSets;
        out.viaGroupCount   = r.groupDerivedCount;
        out.unreadableCount = r.unreadableCount;
        return out;
    }

    public static List<PEDto.PermSetGroupRow> permissionSetGroups(Id userId) {
        return PEPermissionResolver.resolve(userId).assignedGroups;
    }
}
