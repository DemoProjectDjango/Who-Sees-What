/**
 * Covers the posture signals.
 *
 * The counts themselves depend on org configuration a test cannot control, so
 * these assert the contract the dashboard relies on rather than specific
 * numbers: every signal is present, carries a remedy, and reports a severity
 * the UI knows how to render. A signal that silently appeared with a null
 * severity would render as an all-clear.
 */
@IsTest
private class PEPostureServiceTest {

    private static final Set<String> VALID_SEVERITIES = new Set<String>{ 'ok', 'watch', 'alert' };

    private static final Set<String> EXPECTED_KEYS = new Set<String>{
        'staleGroups',
        'PermissionsModifyAllData',
        'PermissionsViewAllData',
        'dormantUsers',
        'unassignedSets'
    };

    @IsTest
    static void everySignalIsPresentAndRenderable() {
        System.runAs(asSelf()) {
            Test.startTest();
            PEPostureService.Posture p = PEPostureService.get(true);
            Test.stopTest();

            Set<String> seen = new Set<String>();
            for (PEPostureService.Signal s : p.signals) {
                seen.add(s.key);

                Assert.isTrue(
                    String.isNotBlank(s.label),
                    'a signal with no label cannot be rendered: ' + s.key
                );
                Assert.isTrue(
                    String.isNotBlank(s.remedy),
                    'a count an administrator cannot act on does not belong here: ' + s.key
                );
                Assert.isTrue(
                    VALID_SEVERITIES.contains(s.severity),
                    'unknown severity "' + s.severity + '" would render as an all-clear: ' + s.key
                );
            }

            Assert.areEqual(
                EXPECTED_KEYS, seen,
                'the dashboard renders a fixed set of signals; adding or dropping one is a UI change too'
            );
        }
    }

    @IsTest
    static void staleGroupsAlertsOnlyWhenSomethingIsStale() {
        System.runAs(asSelf()) {
            Test.startTest();
            PEPostureService.Posture p = PEPostureService.get(true);
            Test.stopTest();

            PEPostureService.Signal stale = signalFor(p, 'staleGroups');
            Assert.isNotNull(stale, 'the stale group signal is the sharpest one this product raises');

            if (stale.value == null) {
                return; // Object unreadable in this context; nothing further to assert.
            }
            if (stale.value == 0) {
                Assert.areEqual('ok', stale.severity, 'nothing stale means nothing to flag');
            } else {
                Assert.areEqual(
                    'alert', stale.severity,
                    'an unrecalculated group makes every other answer in this app provisional'
                );
            }
        }
    }

    @IsTest
    static void housekeepingNeverEscalatesToAlert() {
        System.runAs(asSelf()) {
            Test.startTest();
            PEPostureService.Posture p = PEPostureService.get(true);
            Test.stopTest();

            PEPostureService.Signal unassigned = signalFor(p, 'unassignedSets');
            Assert.isNotNull(unassigned, 'the unassigned set signal must be present');
            Assert.areNotEqual(
                'alert', unassigned.severity,
                'reserving alert for things that affect access is what keeps alert meaningful'
            );
        }
    }

    @IsTest
    static void privilegeSignalsCarryTheirDenominator() {
        System.runAs(asSelf()) {
            Test.startTest();
            PEPostureService.Posture p = PEPostureService.get(true);
            Test.stopTest();

            Assert.isNotNull(p.activeUsers, 'the denominator is needed to judge a share');

            for (String key : new List<String>{
                'PermissionsModifyAllData', 'PermissionsViewAllData', 'dormantUsers'
            }) {
                PEPostureService.Signal s = signalFor(p, key);
                Assert.areEqual(
                    p.activeUsers, s.outOf,
                    'a count of users is only readable against the user total: ' + key
                );
            }
        }
    }

    @IsTest
    static void adminPermissionIsCountedThroughTheProfileRoute() {
        System.runAs(asSelf()) {
            Test.startTest();
            PEPostureService.Posture p = PEPostureService.get(true);
            Test.stopTest();

            PEPostureService.Signal mad = signalFor(p, 'PermissionsModifyAllData');
            if (mad.value == null) {
                return; // Unreadable here; the contract test above already covers shape.
            }
            // The running user is a System Administrator, and that grant arrives via
            // a profile-owned permission set. Counting only standalone sets would
            // report most orgs as having no administrators at all.
            Assert.isTrue(
                mad.value >= 1,
                'Modify All Data granted by profile must be counted, not just by assigned sets'
            );
        }
    }

    @IsTest
    static void licenceUseExcludesUnlimitedFromTheDenominator() {
        System.runAs(asSelf()) {
            Test.startTest();
            PEPostureService.Posture p = PEPostureService.get(true);
            Test.stopTest();

            if (p.licences == null) {
                return; // UserLicense unreadable in this context.
            }
            Assert.isTrue(p.licences.total >= 0, 'a negative seat total is a sentinel leaking through');
            Assert.isTrue(p.licences.used >= 0, 'seats in use cannot be negative');
            Assert.areEqual(
                p.licences.total - p.licences.used, p.licences.free,
                'free seats must reconcile with owned minus used'
            );
        }
    }

    @IsTest
    static void secondCallIsServedFromCache() {
        System.runAs(asSelf()) {
            Test.startTest();
            PEPostureService.Posture first = PEPostureService.get(true);
            Integer queriesAfterFirst = Limits.getQueries();
            PEPostureService.Posture second = PEPostureService.get();
            Integer queriesAfterSecond = Limits.getQueries();
            Test.stopTest();

            Assert.isNotNull(first, 'the first call computes');
            Assert.isNotNull(second, 'the cached call still returns a posture');
            Assert.areEqual(
                queriesAfterFirst, queriesAfterSecond,
                'a cache hit that still queries is not a cache'
            );
        }
    }

    /**
     * Finds one signal by key.
     *
     * @param p Posture to search.
     * @param key Signal key to find.
     * @return The matching signal, or null when absent.
     */
    private static PEPostureService.Signal signalFor(PEPostureService.Posture p, String key) {
        for (PEPostureService.Signal s : p.signals) {
            if (s.key == key) {
                return s;
            }
        }
        return null;
    }

    /**
     * The running user, as a User record runAs can accept.
     *
     * Every test body runs inside System.runAs. These tests inspect another
     * user's access, which is exactly the operation that behaves differently
     * depending on who is executing it - so the executing identity should be
     * stated rather than inherited from whatever context the runner happens to
     * provide.
     *
     * @return The current user.
     */
    private static User asSelf() {
        return new User(Id = UserInfo.getUserId());
    }
}
