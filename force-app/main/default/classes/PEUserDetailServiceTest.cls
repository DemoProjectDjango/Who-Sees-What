/**
 * Tests for the three header drill-downs.
 *
 * The assertion that matters most here is `listLengthMatchesHeaderCount`. The
 * whole reason the permission set list is read off the resolver instead of
 * re-queried is that a second predicate can drift from the first, leaving a
 * header that says 42 above a list of 43. This test is what makes that
 * guarantee real rather than a comment.
 *
 * LoginHistory cannot be inserted in a test context, so login history is tested
 * for its contract — never throws, always states its own availability — rather
 * than for rows.
 */
@IsTest
private class PEUserDetailServiceTest {

    private static final String SUBJECT_EMAIL   = 'drill.subject@example.invalid';
    private static final String INSPECTOR_EMAIL = 'drill.inspector@example.invalid';

    /* ===============================================================
     * Setup
     * =============================================================== */

    @TestSetup
    static void makeData() {
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' WITH USER_MODE LIMIT 1];
        String stamp = String.valueOf(Datetime.now().getTime());

        User subject = buildUser(admin.Id, 'Drill', 'Subject', 'drlsub', SUBJECT_EMAIL, stamp + 'a');

        // A second admin who will actually hold the packaged custom permission,
        // so the controller's gate is exercised rather than sidestepped.
        User inspector = buildUser(admin.Id, 'Drill', 'Inspector', 'drlins', INSPECTOR_EMAIL, stamp + 'b');

        insert new List<User>{ subject, inspector };

        List<PermissionSet> sets = new List<PermissionSet>{
            new PermissionSet(Name = 'PE_Test_Alpha', Label = 'PE Test Alpha'),
            new PermissionSet(Name = 'PE_Test_Beta',  Label = 'PE Test Beta')
        };
        insert sets;

        List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
        for (PermissionSet ps : sets) {
            psas.add(new PermissionSetAssignment(AssigneeId = subject.Id, PermissionSetId = ps.Id));
        }

        // Grants Use_Permission_Explorer plus PE_Inspection_Log__c create access.
        List<PermissionSet> gate = [
            SELECT Id FROM PermissionSet
            WHERE Name = 'PermissionCheckerPermissionSet'
            WITH USER_MODE
            LIMIT 1
        ];
        if (!gate.isEmpty()) {
            psas.add(new PermissionSetAssignment(
                AssigneeId = inspector.Id, PermissionSetId = gate[0].Id
            ));
        }
        insert psas;
    }

    private static User buildUser(
        Id profileId, String first, String last, String alias, String email, String stamp
    ) {
        return new User(
            FirstName = first,
            LastName  = last,
            Alias     = alias,
            Email     = email,
            Username  = alias + '.' + stamp + '@example.invalid',
            ProfileId = profileId,
            TimeZoneSidKey    = 'GMT',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static User subject() {
        return [SELECT Id FROM User WHERE Email = :SUBJECT_EMAIL WITH USER_MODE LIMIT 1];
    }

    private static User inspector() {
        return [SELECT Id FROM User WHERE Email = :INSPECTOR_EMAIL WITH USER_MODE LIMIT 1];
    }

    /* ===============================================================
     * The consistency guarantee
     * =============================================================== */

    @IsTest
    static void listLengthMatchesHeaderCount() {
        Id userId = subject().Id;

        Test.startTest();
        PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(userId, true);
        PEDto.PermSetList result = PEUserDetailService.permissionSets(userId);
        Test.stopTest();

        Assert.areEqual(
            r.permSetCount,
            result.directSets.size(),
            'The drill-down list must be exactly as long as the count printed in the header'
        );
    }

    @IsTest
    static void directSetsCarryLabelAndApiName() {
        Id userId = subject().Id;

        Test.startTest();
        PEDto.PermSetList result = PEUserDetailService.permissionSets(userId);
        Test.stopTest();

        Assert.isFalse(result.directSets.isEmpty(), 'Two sets were assigned in setup');

        Boolean foundAlpha = false;
        for (PEDto.PermSetRow row : result.directSets) {
            Assert.isNotNull(row.permSetId, 'A row without an Id cannot be linked to Setup');
            if (row.apiName == 'PE_Test_Alpha') {
                foundAlpha = true;
                Assert.areEqual('PE Test Alpha', row.label, 'Label did not survive the mapping');
                Assert.isTrue(row.isReadable, 'A locally created set is readable');
            }
        }
        Assert.isTrue(foundAlpha, 'The assigned set was not in the list');
    }

    @IsTest
    static void profileOwnedSetIsNotListedAsAnAssignment() {
        Id userId = subject().Id;

        Test.startTest();
        PEDto.PermSetList result = PEUserDetailService.permissionSets(userId);
        Test.stopTest();

        for (PEDto.PermSetRow row : result.directSets) {
            Assert.areNotEqual(
                'Profile', row.setType,
                'The profile is a parent, not an assignment, and must not appear in this list'
            );
        }
    }

    /* ===============================================================
     * Groups
     * =============================================================== */

    @IsTest
    static void groupListIsNeverNull() {
        Id userId = subject().Id;

        Test.startTest();
        List<PEDto.PermSetGroupRow> groups = PEUserDetailService.permissionSetGroups(userId);
        Test.stopTest();

        Assert.isNotNull(groups, 'An empty list is a valid answer; null is not');
        Assert.areEqual(0, groups.size(), 'No groups were assigned in setup');
    }

    /* ===============================================================
     * Login history — contract, not rows
     * =============================================================== */

    @IsTest
    static void loginHistoryAlwaysReportsItsOwnAvailability() {
        Id userId = subject().Id;

        Test.startTest();
        PEDto.LoginHistoryResult res = PEUserDetailService.loginHistory(userId, null);
        Test.stopTest();

        Assert.isNotNull(res, 'The panel must always get a payload');
        Assert.isNotNull(res.events, 'Events list must be initialised even when unavailable');
        Assert.isNotNull(res.retentionNote, 'The six-month window must always be stated');

        // The failure this guards against is silence: reporting no rows without
        // saying whether that means "none" or "could not look".
        Assert.isTrue(
            res.notAvailableReason == null || res.events.isEmpty(),
            'If history could not be read, no rows may be reported'
        );
    }

    @IsTest
    static void loginHistoryClampsAnAbsurdLimit() {
        Test.startTest();
        PEDto.LoginHistoryResult res = PEUserDetailService.loginHistory(subject().Id, 999999);
        Test.stopTest();

        Assert.areEqual(50, res.appliedLimit, 'An out-of-range limit falls back to the default');
    }

    @IsTest
    static void loginHistoryClampsZeroAndNegative() {
        Id userId = subject().Id;

        Test.startTest();
        PEDto.LoginHistoryResult zero = PEUserDetailService.loginHistory(userId, 0);
        PEDto.LoginHistoryResult neg  = PEUserDetailService.loginHistory(userId, -5);
        Test.stopTest();

        Assert.areEqual(50, zero.appliedLimit, 'Zero is not a usable page size');
        Assert.areEqual(50, neg.appliedLimit, 'Negative is not a usable page size');
    }

    /* ===============================================================
     * Controller surface — the gate, both ways
     * =============================================================== */

    @IsTest
    static void unauthorisedUserIsRejectedBeforeAnyQuery() {
        Id userId = subject().Id;
        User plain = [SELECT Id FROM User WHERE Email = :SUBJECT_EMAIL WITH USER_MODE LIMIT 1];

        Boolean threw = false;
        String message;

        System.runAs(plain) {
                Test.startTest();
            try {
                PermissionExplorerController.getAssignedPermissionSets(userId);
            } catch (Exception e) {
                threw = true;
                message = e.getMessage();
            }
            Test.stopTest();
        }

        Assert.isTrue(threw, 'The gate must reject a user without the custom permission');
        Assert.isTrue(
            message != null && message.contains(PermissionExplorerException.NOT_AUTHORISED),
            'The structured cause must reach the client, not a generic message. Got: ' + message
        );
    }

    @IsTest
    static void authorisedInspectorReachesAllThreeDrillDowns() {
        Id userId = subject().Id;
        User ins = inspector();

        Test.startTest();
        System.runAs(ins) {
            PEDto.PermSetList sets =
                PermissionExplorerController.getAssignedPermissionSets(userId);
            List<PEDto.PermSetGroupRow> groups =
                PermissionExplorerController.getAssignedPermissionSetGroups(userId);
            PEDto.LoginHistoryResult history =
                PermissionExplorerController.getLoginHistory(userId, 10);

            Assert.isNotNull(sets, 'Permission set payload missing');
            Assert.isNotNull(groups, 'Group payload missing');
            Assert.isNotNull(history, 'Login history payload missing');
            Assert.areEqual(10, history.appliedLimit, 'Requested limit was not honoured');
        }
        Test.stopTest();
    }
}
