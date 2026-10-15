/**
 * Org-level access posture: the signals an administrator can act on.
 *
 * PEOrgStatsService answers "how big is this org" - 143 permission sets, 44
 * profiles. Those figures are true, static for weeks, and nothing follows from
 * reading them. This class answers the different question an access-audit tool
 * exists for: is anything here wrong, and what would I do about it.
 *
 * Every signal is a count with a defined remedy. A signal nobody can act on
 * does not belong in this class.
 *
 * Each query is independently try/caught and leaves its field null on failure.
 * A null renders as "unavailable"; it never renders as zero, because on a risk
 * panel a fabricated zero reads as an all-clear.
 */
public with sharing class PEPostureService {

    private static final String CACHE_KEY = 'postureV1';

    /** Ten minutes, matching PEOrgStatsService. Long enough to make the page
     *  cheap, short enough that a change made this session shows up. */
    private static final Integer CACHE_TTL_SECONDS = 600;

    /** Ceiling on the permission set Id list feeding the privilege counts.
     *  Orgs with more admin-granting sets than this have a bigger problem than
     *  an imprecise KPI. */
    private static final Integer PERM_SET_SCAN_CAP = 2000;

    /**
     * One actionable signal.
     *
     * `value` null means the query failed or the running user cannot read the
     * objects behind it. The UI must distinguish that from zero.
     */
    public class Signal {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
        /** Comparison figure where one exists, e.g. active users. */
        @AuraEnabled public Integer outOf;
        /** What to do about it, in one line. */
        @AuraEnabled public String remedy;
        /** 'alert' needs attention now, 'watch' is worth reviewing, 'ok' is clean. */
        @AuraEnabled public String severity = 'ok';
    }

    /** Seats in use against seats owned, for the licences that have a ceiling. */
    public class LicenceUse {
        @AuraEnabled public Integer used;
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer free;
        /** Licences with no ceiling are excluded from the totals and counted here. */
        @AuraEnabled public Integer unlimitedCount = 0;
    }

    /** Everything the posture section renders. */
    public class Posture {
        @AuraEnabled public List<Signal> signals = new List<Signal>();
        @AuraEnabled public LicenceUse licences;
        @AuraEnabled public Integer activeUsers;
    }

    /* ---------------------------------------------------------------
     * Entry points
     * --------------------------------------------------------------- */

    /**
     * Posture signals, served from the org cache when warm.
     *
     * @return The actionable signals plus licence utilisation.
     */
    public static Posture get() {
        return get(false);
    }

    /**
     * Posture signals, optionally recomputed.
     *
     * @param forceRefresh True when the admin explicitly refreshes.
     * @return The actionable signals plus licence utilisation.
     */
    // forceRefresh mirrors PEOrgStatsService rather than inventing a second
    // shape for the same idea.
    @SuppressWarnings('PMD.AvoidBooleanMethodParameters')
    public static Posture get(Boolean forceRefresh) {
        if (forceRefresh != true) {
            Object cached = PECacheManager.orgGet(CACHE_KEY);
            if (cached instanceof Posture) {
                return (Posture) cached;
            }
        }

        Posture p = compute();
        PECacheManager.orgPut(CACHE_KEY, p, CACHE_TTL_SECONDS);
        return p;
    }

    /* ---------------------------------------------------------------
     * Computation
     * --------------------------------------------------------------- */

    /**
     * Runs every signal. One failing never blanks the others.
     *
     * @return Freshly computed posture.
     */
    private static Posture compute() {
        Posture p = new Posture();
        p.activeUsers = countActiveUsers();

        p.signals.add(staleGroups());
        p.signals.add(privilegedUsers('PermissionsModifyAllData',
            'Users with Modify All Data',
            'Review each holder. This bypasses sharing, field security and record ownership.',
            p.activeUsers));
        p.signals.add(privilegedUsers('PermissionsViewAllData',
            'Users with View All Data',
            'Confirm each holder needs org-wide read. This bypasses sharing rules.',
            p.activeUsers));
        p.signals.add(dormantUsers(p.activeUsers));
        p.signals.add(unassignedPermissionSets());

        p.licences = licenceUse();
        return p;
    }

    /**
     * Active user count, used as the denominator for the user-based signals.
     *
     * @return Active users, or null when the query fails.
     */
    @SuppressWarnings('PMD.AvoidNonRestrictiveQueries')
    private static Integer countActiveUsers() {
        try {
            return [SELECT COUNT() FROM User WHERE IsActive = true WITH USER_MODE];
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Permission set groups whose Status is not 'Updated'.
     *
     * The sharpest signal this product can raise. While a group is unrecalculated
     * the permissions its members actually hold differ from what the
     * administrator configured, which means every other answer in this app is
     * provisional for those users.
     *
     * @return The stale-group signal.
     */
    private static Signal staleGroups() {
        Signal s = new Signal();
        s.key    = 'staleGroups';
        s.label  = 'Groups awaiting recalculation';
        s.remedy = 'Until these finish recalculating, members hold different permissions than configured.';

        try {
            s.value = [
                SELECT COUNT() FROM PermissionSetGroup
                WHERE Status != 'Updated'
                WITH USER_MODE
            ];
            s.severity = s.value > 0 ? 'alert' : 'ok';
        } catch (Exception e) {
            s.value = null;
        }
        return s;
    }

    /**
     * Active users holding a sweeping permission, through any route.
     *
     * Counts assignments to profile-owned permission sets as well as standalone
     * ones, so a permission granted by profile is counted exactly like one
     * granted by an assigned set. Counting only standalone sets would report
     * most orgs as having no administrators.
     *
     * @param permissionField API name of the permission field on PermissionSet.
     * @param label Display label for the signal.
     * @param remedy One-line instruction for the administrator.
     * @param activeUsers Active user count used as the denominator.
     * @return The privileged-user signal.
     */
    // Four parameters because a signal needs all four to be renderable: the
    // permission to count, the label and remedy an administrator reads, and the
    // denominator that turns a raw count into a judgeable share.
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static Signal privilegedUsers(
        String permissionField, String label, String remedy, Integer activeUsers
    ) {
        Signal s = new Signal();
        s.key    = permissionField;
        s.label  = label;
        s.remedy = remedy;
        s.outOf  = activeUsers;

        try {
            // Use static SOQL for the two supported privilege flags. This
            // prevents identifier injection and preserves user-mode access.
            List<PermissionSet> sets;
            if (permissionField == 'PermissionsModifyAllData') {
                sets = [
                    SELECT Id FROM PermissionSet
                    WHERE PermissionsModifyAllData = true
                    WITH USER_MODE LIMIT :PERM_SET_SCAN_CAP
                ];
            } else if (permissionField == 'PermissionsViewAllData') {
                sets = [
                    SELECT Id FROM PermissionSet
                    WHERE PermissionsViewAllData = true
                    WITH USER_MODE LIMIT :PERM_SET_SCAN_CAP
                ];
            } else {
                // Unsupported signal: do not silently turn it into a zero.
                s.value = null;
                return s;
            }
            if (sets.isEmpty()) {
                s.value = 0;
                return s;
            }

            Set<Id> setIds = new Map<Id, PermissionSet>(sets).keySet();

            AggregateResult[] ar = [
                SELECT COUNT_DISTINCT(AssigneeId) cnt
                FROM PermissionSetAssignment
                WHERE PermissionSetId IN :setIds AND Assignee.IsActive = true
                WITH USER_MODE
            ];
            s.value = ar.isEmpty() ? 0 : (Integer) ar[0].get('cnt');

            // No fixed threshold: a five-person org with three admins is normal,
            // a thousand-person org with three hundred is not. Severity tracks
            // the share of active users rather than the raw count.
            s.severity = severityByShare(s.value, activeUsers, 0.10, 0.25);
        } catch (Exception e) {
            s.value = null;
        }
        return s;
    }

    /**
     * Active users who have never signed in.
     *
     * Each one consumes a licence and carries whatever permissions their profile
     * grants, with nobody ever having exercised them.
     *
     * @param activeUsers Active user count used as the denominator.
     * @return The dormant-user signal.
     */
    private static Signal dormantUsers(Integer activeUsers) {
        Signal s = new Signal();
        s.key    = 'dormantUsers';
        s.label  = 'Active users who never signed in';
        s.remedy = 'Each holds a licence and its permissions without ever having used them.';
        s.outOf  = activeUsers;

        try {
            s.value = [
                SELECT COUNT() FROM User
                WHERE IsActive = true AND LastLoginDate = null
                WITH USER_MODE
            ];
            s.severity = severityByShare(s.value, activeUsers, 0.10, 0.25);
        } catch (Exception e) {
            s.value = null;
        }
        return s;
    }

    /**
     * Standalone permission sets assigned to nobody.
     *
     * Not a risk on its own - unused grants cannot be exercised. It is a
     * maintenance signal: they clutter every assignment screen in the org and
     * make real grants harder to find.
     *
     * @return The unassigned-set signal.
     */
    private static Signal unassignedPermissionSets() {
        Signal s = new Signal();
        s.key    = 'unassignedSets';
        s.label  = 'Permission sets assigned to nobody';
        s.remedy = 'Harmless but noisy. Retiring them makes real grants easier to find.';

        try {
            s.value = [
                SELECT COUNT() FROM PermissionSet
                WHERE IsOwnedByProfile = false
                  AND Id NOT IN (SELECT PermissionSetId FROM PermissionSetAssignment)
                WITH USER_MODE
            ];
            // Housekeeping never escalates past 'watch'. Reserving 'alert' for
            // things that actually affect access is what keeps it meaningful.
            s.severity = s.value > 0 ? 'watch' : 'ok';
        } catch (Exception e) {
            s.value = null;
        }
        return s;
    }

    /**
     * Seat utilisation across active user licences.
     *
     * Only licences with a real ceiling are summed. Unlimited licences report a
     * sentinel total, and adding that to a denominator would make utilisation
     * meaningless.
     *
     * @return Seats used, owned and free, plus how many licences are unlimited.
     */
    @SuppressWarnings('PMD.AvoidNonRestrictiveQueries')
    private static LicenceUse licenceUse() {
        LicenceUse lu = new LicenceUse();
        try {
            Integer used = 0;
            Integer total = 0;

            for (UserLicense ul : [
                SELECT TotalLicenses, UsedLicenses
                FROM UserLicense
                WHERE Status = 'Active'
                WITH USER_MODE
            ]) {
                Integer seats = ul.TotalLicenses;
                if (seats == null || seats < 0) {
                    lu.unlimitedCount++;
                    continue;
                }
                total += seats;
                used  += ul.UsedLicenses == null ? 0 : ul.UsedLicenses;
            }

            lu.used  = used;
            lu.total = total;
            lu.free  = total - used;
        } catch (Exception e) {
            return null;
        }
        return lu;
    }

    /**
     * Severity from a proportion rather than an absolute count.
     *
     * @param value The signal's count.
     * @param outOf The denominator, or null when there isn't one.
     * @param watchAt Share above which the signal is worth reviewing.
     * @param alertAt Share above which the signal needs attention.
     * @return 'ok', 'watch' or 'alert'.
     */
    // The two thresholds are the point of the method; folding them into a
    // constant would fix every signal to one sensitivity.
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static String severityByShare(
        Integer value, Integer outOf, Decimal watchAt, Decimal alertAt
    ) {
        if (value == null || value == 0) {
            return 'ok';
        }
        // Without a denominator there is no share to judge, and guessing a
        // threshold would raise alarms in small orgs and miss them in large ones.
        if (outOf == null || outOf == 0) {
            return 'watch';
        }
        Decimal share = Decimal.valueOf(value) / Decimal.valueOf(outOf);
        if (share >= alertAt) {
            return 'alert';
        }
        return share >= watchAt ? 'watch' : 'ok';
    }
}
