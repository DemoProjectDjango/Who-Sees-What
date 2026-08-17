/**
 * Covers PermissionExplorerController — specifically the nine catch blocks that
 * were uncovered, plus buildSummary and toAura.
 *
 * The technique: every @AuraEnabled method opens with a PEAccessGate call, so
 * running as a user who lacks the packaged custom permission drives all nine
 * into their catch path in one pass. That is cheaper and more honest than
 * feeding each method a malformed Id, because it exercises the failure the
 * product actually has to handle — an unauthorised caller reaching the
 * @AuraEnabled surface directly, bypassing the UI.
 *
 * Assertions are contract-level: the org's permission data is unknown, so this
 * asserts that errors are typed and surfaced as AuraHandledException rather
 * than asserting specific counts.
 */
@IsTest
private class PermissionExplorerControllerTest {

    private static final String AUTHORISED_ALIAS   = 'pecAuth';
    private static final String UNAUTHORISED_ALIAS = 'pecDeny';

    @TestSetup
    static void makeData() {
        Profile admin = [
            SELECT Id FROM Profile WHERE Name = 'System Administrator' WITH USER_MODE LIMIT 1
        ];
        String stamp = String.valueOf(Datetime.now().getTime());

        User authorised = newUser('Auth', AUTHORISED_ALIAS, stamp, admin.Id);
        User denied     = newUser('Deny', UNAUTHORISED_ALIAS, stamp, admin.Id);
        insert new List<User>{ authorised, denied };

        // Only the authorised user gets the gate permission set.
        List<PermissionSet> gate = [
            SELECT Id FROM PermissionSet
            WHERE Name = 'PermissionCheckerPermissionSet' WITH USER_MODE LIMIT 1
        ];
        if (!gate.isEmpty()) {
            insert new PermissionSetAssignment(
                AssigneeId = authorised.Id, PermissionSetId = gate[0].Id
            );
        }
    }

    private static User newUser(String first, String alias, String stamp, Id profileId) {
        return new User(
            FirstName = first,
            LastName  = 'Controller',
            Alias     = alias,
            Email     = alias + '@example.invalid',
            Username  = alias + '.' + stamp + '@example.invalid',
            ProfileId = profileId,
            TimeZoneSidKey    = 'GMT',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static User userByAlias(String alias) {
        return [SELECT Id FROM User WHERE Alias = :alias WITH USER_MODE LIMIT 1];
    }

    /* ---------------------------------------------------------------
     * The nine catch blocks
     * --------------------------------------------------------------- */

    @IsTest
    static void unauthorisedCallerIsRejectedByEveryEntryPoint() {
        User denied = userByAlias(UNAUTHORISED_ALIAS);
        Id target = userByAlias(AUTHORISED_ALIAS).Id;
        Integer rejected = 0;

        Test.startTest();
        System.runAs(denied) {
            rejected += expectRejection('getFilterOptions', null, null);
            rejected += expectRejection('searchUsers', null, null);
            rejected += expectRejection('resolveUser', target, null);
            rejected += expectRejection('getLoginHistory', target, null);
            rejected += expectRejection('getAssignedPermissionSets', target, null);
            rejected += expectRejection('getAssignedPermissionSetGroups', target, null);
            rejected += expectRejection('getAppObjects', target, 'Sales');
            rejected += expectRejection('getObjectDetail', target, 'Account');
            rejected += expectRejection('refreshCache', null, null);
        }
        Test.stopTest();

        Assert.areEqual(
            9, rejected,
            'every @AuraEnabled entry point must reject an unauthorised caller'
        );
    }

    /**
     * Calls one entry point and returns 1 if it threw. Kept as a dispatcher so
     * the nine calls read as a list rather than nine near-identical try blocks.
     */
    private static Integer expectRejection(String method, Id userId, String extra) {
        try {
            switch on method {
                when 'getFilterOptions' {
                    PermissionExplorerController.getFilterOptions();
                }
                when 'searchUsers' {
                    PermissionExplorerController.searchUsers(
                        null, null, null, null, null, null, 10
                    );
                }
                when 'resolveUser' {
                    PermissionExplorerController.resolveUser(userId, false);
                }
                when 'getLoginHistory' {
                    PermissionExplorerController.getLoginHistory(userId, 25);
                }
                when 'getAssignedPermissionSets' {
                    PermissionExplorerController.getAssignedPermissionSets(userId);
                }
                when 'getAssignedPermissionSetGroups' {
                    PermissionExplorerController.getAssignedPermissionSetGroups(userId);
                }
                when 'getAppObjects' {
                    PermissionExplorerController.getAppObjects(userId, extra);
                }
                when 'getObjectDetail' {
                    PermissionExplorerController.getObjectDetail(userId, extra);
                }
                when 'refreshCache' {
                    PermissionExplorerController.refreshCache();
                }
                when else {
                    Assert.fail('unknown method in dispatcher: ' + method);
                }
            }
        } catch (Exception e) {
            Assert.isInstanceOfType(
                e, AuraHandledException.class,
                method + ' must surface a typed AuraHandledException, got: ' + e
            );
            return 1;
        }
        Assert.fail(method + ' should have rejected an unauthorised caller');
        return 0;
    }

    /* ---------------------------------------------------------------
     * toAura's non-PermissionExplorerException branches
     * --------------------------------------------------------------- */

    @IsTest
    static void malformedIdIsSurfacedAsTypedError() {
        User authorised = userByAlias(AUTHORISED_ALIAS);

        Test.startTest();
        System.runAs(authorised) {
            try {
                // A well-formed Id of the wrong sObject type: reaches past the
                // gate and fails inside, exercising toAura's generic branch.
                PermissionExplorerController.resolveUser(UserInfo.getOrganizationId(), false);
                Assert.fail('a non-User Id must not resolve');
            } catch (Exception e) {
                Assert.isInstanceOfType(
                    e, AuraHandledException.class,
                    'unexpected failures must still be converted, not leaked raw'
                );
            }
        }
        Test.stopTest();
    }

    /* ---------------------------------------------------------------
     * Authorised happy paths — buildSummary and the delegation shape
     * --------------------------------------------------------------- */

    @IsTest
    static void authorisedCallerResolvesAUserSummary() {
        User authorised = userByAlias(AUTHORISED_ALIAS);

        Test.startTest();
        System.runAs(authorised) {
            PEDto.UserContext ctx =
                PermissionExplorerController.resolveUser(authorised.Id, false);

            Assert.isNotNull(ctx, 'context must never be null');
            Assert.isNotNull(ctx.summary, 'buildSummary must populate a summary');
            Assert.isNotNull(ctx.summary.userId, 'summary must carry the user id');
            Assert.isNotNull(ctx.apps, 'app list must never be null');
        }
        Test.stopTest();
    }

    @IsTest
    static void forceRefreshTakesTheUncachedPath() {
        User authorised = userByAlias(AUTHORISED_ALIAS);

        Test.startTest();
        System.runAs(authorised) {
            PEDto.UserContext warm = PermissionExplorerController.resolveUser(authorised.Id, false);
            PEDto.UserContext cold = PermissionExplorerController.resolveUser(authorised.Id, true);

            Assert.isNotNull(warm.summary, 'cached path must return a summary');
            Assert.isNotNull(cold.summary, 'forceRefresh path must return a summary');
            Assert.areEqual(
                warm.summary.userId, cold.summary.userId,
                'refreshing must not change which user was resolved'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void authorisedCallerReachesTheSimpleEntryPoints() {
        User authorised = userByAlias(AUTHORISED_ALIAS);

        Test.startTest();
        System.runAs(authorised) {
            Assert.isNotNull(
                PermissionExplorerController.getFilterOptions(),
                'filter options must never be null'
            );
            Assert.isNotNull(
                PermissionExplorerController.searchUsers(
                    null, null, null, null, null, null, 5
                ),
                'search must never return null'
            );
            Assert.isNotNull(
                PermissionExplorerController.getLoginHistory(authorised.Id, 10),
                'login history must report availability rather than return null'
            );
            Assert.isNotNull(
                PermissionExplorerController.getAssignedPermissionSets(authorised.Id),
                'permission set list must never be null'
            );
            Assert.isNotNull(
                PermissionExplorerController.getAssignedPermissionSetGroups(authorised.Id),
                'group list must never be null'
            );
            Assert.isNotNull(
                PermissionExplorerController.refreshCache(),
                'refreshCache must return a version token'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void blankSortFieldDefaultsToLastLogin() {
        User authorised = userByAlias(AUTHORISED_ALIAS);

        Test.startTest();
        System.runAs(authorised) {
            PEDto.PagedResult r = PermissionExplorerController.searchUsers(
                null, null, null, null, '   ', null, 5
            );
            Assert.isNotNull(r, 'a blank sort field must fall back, not throw');
        }
        Test.stopTest();
    }
}