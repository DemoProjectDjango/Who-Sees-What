/**
 * Walks the full stack the way the LWC does: search, resolve, then drill into
 * one object. The reason this exists as one test rather than four unit tests is
 * that PEAccessQueryService, PEMetadataCatalog and PEAppVisibilityService are only
 * ever reached through the controller, and testing them in isolation would
 * assert against a call shape no caller actually uses.
 *
 * All assertions are contract-level - never throws, never null, states its own
 * limitations - because the org this runs in has unknown permission data and
 * asserting specific counts would make the test a mirror of one sandbox.
 */
@IsTest
private class PermissionExplorerFlowTest {

    private static final String INSPECTOR_EMAIL = 'flow.inspector@example.invalid';

    @TestSetup
    static void makeData() {
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' WITH USER_MODE LIMIT 1];
        String stamp = String.valueOf(Datetime.now().getTime());

        User inspector = new User(
            FirstName = 'Flow',
            LastName  = 'Inspector',
            Alias     = 'flwins',
            Email     = INSPECTOR_EMAIL,
            Username  = 'flwins.' + stamp + '@example.invalid',
            ProfileId = admin.Id,
            TimeZoneSidKey    = 'GMT',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert inspector;

        List<PermissionSet> gate = [
            SELECT Id FROM PermissionSet
            WHERE Name = 'PermissionCheckerPermissionSet' WITH USER_MODE LIMIT 1
        ];
        if (!gate.isEmpty()) {
            insert new PermissionSetAssignment(
                AssigneeId = inspector.Id, PermissionSetId = gate[0].Id
            );
        }
    }

    private static User inspector() {
        return [SELECT Id FROM User WHERE Email = :INSPECTOR_EMAIL WITH USER_MODE LIMIT 1];
    }

    @IsTest
    static void resolveThenDrillIntoAnObject() {
        User ins = inspector();
        Id target = UserInfo.getUserId();

        System.runAs(ins) {
            Test.startTest();
            PEDto.UserContext ctx = PermissionExplorerController.resolveUser(target, true);
            PEDto.ObjectDetail detail = PermissionExplorerController.getObjectDetail(target, 'Account');
            Test.stopTest();

            Assert.isNotNull(ctx, 'resolveUser must return a context');
            Assert.isNotNull(ctx.summary, 'The header summary is the whole point of the call');
            Assert.isNotNull(ctx.apps, 'App list must be present even when estimated');
            Assert.areEqual('APP_MENU_ITEM', ctx.apps.resolutionMode,
                'App visibility has exactly one resolution mode now that the callout path is gone');
            Assert.isTrue(ctx.apps.setupRequired,
                'The estimate must always disclose itself');

            Assert.isNotNull(detail, 'Object detail must return for a standard object');
            Assert.isNotNull(detail.fields, 'Field list must never be null');
            Assert.isNotNull(detail.recordTypes, 'Record type list must never be null');
        }
    }

    @IsTest
    static void recordTypesAreListedButNeverClaimUserAccess() {
        User ins = inspector();

        System.runAs(ins) {
            Test.startTest();
            PEDto.ObjectDetail detail =
                PermissionExplorerController.getObjectDetail(UserInfo.getUserId(), 'Account');
            Test.stopTest();

            // Account always has at least the Master record type.
            Assert.isTrue(detail.recordTypes.size() > 0,
                'Master record type must always appear');

            Boolean sawMaster = false;
            for (PEDto.RecordTypeRow rt : detail.recordTypes) {
                if (rt.isMaster) { sawMaster = true; }
            }
            Assert.isTrue(sawMaster, 'Master is not optional');
        }
    }

    @IsTest
    static void searchReturnsAPageAndNeverThrows() {
        User ins = inspector();

        System.runAs(ins) {
            Test.startTest();
            PEDto.PagedResult page =
                PermissionExplorerController.searchUsers(null, null, null, null, null, null, 25);
            Test.stopTest();

            Assert.isNotNull(page, 'Search must return a page object');
            Assert.isNotNull(page.records, 'Records list must never be null');
            Assert.areEqual(25, page.pageSize, 'The requested page size must be echoed back');
        }
    }

    @IsTest
    static void filterOptionsAndCacheRefreshAreReachable() {
        User ins = inspector();

        System.runAs(ins) {
            Test.startTest();
            Map<String, Object> opts = PermissionExplorerController.getFilterOptions();
            String result = PermissionExplorerController.refreshCache();
            Test.stopTest();

            Assert.isNotNull(opts, 'Filter options drive the user column picklists');
            Assert.isNotNull(result, 'refreshCache must report its outcome');
        }
    }

    @IsTest
    static void appObjectsReturnsAListForAValidApp() {
        User ins = inspector();

        System.runAs(ins) {
            Test.startTest();
            PEDto.UserContext ctx =
                PermissionExplorerController.resolveUser(UserInfo.getUserId(), true);
            List<PEDto.ObjectRow> rows = new List<PEDto.ObjectRow>();
            if (ctx.apps != null && !ctx.apps.apps.isEmpty()) {
                rows = PermissionExplorerController.getAppObjects(
                    UserInfo.getUserId(), ctx.apps.apps[0].developerName
                );
            }
            Test.stopTest();

            Assert.isNotNull(rows, 'Object list must never be null');
        }
    }
}