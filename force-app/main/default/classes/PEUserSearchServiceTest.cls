/**
 * Covers PEUserSearchService: the optional filter branches, the keyset cursor
 * path, and the sort allowlist.
 *
 * Two deliberate choices, both following PermissionExplorerFlowTest:
 *
 * Assertions are contract-level rather than count-level. The org this runs in
 * has unknown user data, so asserting "returns exactly 3 rows" would make the
 * test a mirror of one sandbox. Where a count is asserted it is against users
 * this test inserted itself, matched on a unique stamp.
 *
 * LastLoginDate is not writeable, so every user this test creates has a null
 * last login. The descending sort path is therefore exercised for structure
 * (does not throw, cursor round-trips) rather than for ordering. That is the
 * limit of what a test can do here, not an omission.
 */
@IsTest
// All methods are contract tests of PEUserSearchService against the six users
// seeded in @TestSetup: filter branches, keyset paging, sort allowlist fallback,
// bind safety, and the header helpers. Assertions key on the seeded data, never
// on the running user's privileges; the USER_MODE queries would return a
// different row set to a runAs user, so runAs has nothing meaningful to add.
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
private class PEUserSearchServiceTest {

    private static final String SURNAME = 'Zzsearchtarget';
    private static String stamp;

    /**
     * Six users sharing a unique surname so the term filter can find exactly
     * this test's data regardless of what else lives in the org.
     */
    @TestSetup
    static void makeData() {
        Profile admin = [
            SELECT Id FROM Profile WHERE Name = 'System Administrator' WITH USER_MODE LIMIT 1
        ];
        String s = String.valueOf(Datetime.now().getTime());

        List<User> targets = new List<User>();
        for (Integer i = 0; i < 6; i++) {
            targets.add(new User(
                FirstName = 'Search' + i,
                LastName  = SURNAME,
                Alias     = 'zst' + i,
                Email     = 'zst' + i + '@example.invalid',
                Username  = 'zst' + i + '.' + s + '@example.invalid',
                ProfileId = admin.Id,
                TimeZoneSidKey    = 'GMT',
                LocaleSidKey      = 'en_US',
                EmailEncodingKey  = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            ));
        }
        insert targets;
    }

    private static PEUserSearchService.Filters filtersForTestData() {
        PEUserSearchService.Filters f = new PEUserSearchService.Filters();
        f.term = SURNAME;
        return f;
    }

    /* ---------------------------------------------------------------
     * Term filter and shape
     * --------------------------------------------------------------- */

    @IsTest
    static void termFilterFindsOnlyMatchingUsers() {
        Test.startTest();
        PEDto.PagedResult r = PEUserSearchService.search(filtersForTestData(), null, 50);
        Test.stopTest();

        Assert.isNotNull(r, 'result must never be null');
        Assert.isNotNull(r.records, 'records must never be null');
        Assert.areEqual(6, r.records.size(), 'should find the six seeded users');
        for (PEDto.UserRow row : r.records) {
            Assert.isTrue(
                row.name.contains(SURNAME),
                'term filter leaked a non-matching user: ' + row.name
            );
            Assert.isNotNull(row.userId, 'userId must be populated');
            Assert.isNotNull(row.username, 'username must be populated');
        }
    }

    @IsTest
    static void blankTermIsTreatedAsNoTermFilter() {
        PEUserSearchService.Filters f = new PEUserSearchService.Filters();
        f.term = '   ';

        Test.startTest();
        PEDto.PagedResult r = PEUserSearchService.search(f, null, 5);
        Test.stopTest();

        Assert.isNotNull(r, 'blank term must not throw');
        Assert.isFalse(
            r.capReached,
            'capReached is a search signal and must stay false when browsing'
        );
    }

    /* ---------------------------------------------------------------
     * Optional filter branches — the previously uncovered clauses
     * --------------------------------------------------------------- */

    @IsTest
    static void profileFilterIsApplied() {
        Profile admin = [
            SELECT Id FROM Profile WHERE Name = 'System Administrator' WITH USER_MODE LIMIT 1
        ];
        PEUserSearchService.Filters f = filtersForTestData();
        f.profileId = admin.Id;

        Test.startTest();
        PEDto.PagedResult r = PEUserSearchService.search(f, null, 50);
        Test.stopTest();

        Assert.areEqual(6, r.records.size(), 'seeded users all share the admin profile');
    }

    @IsTest
    static void profileFilterExcludesOtherProfiles() {
        List<Profile> others = [
            SELECT Id FROM Profile
            WHERE Name != 'System Administrator' WITH USER_MODE LIMIT 1
        ];
        if (others.isEmpty()) {
            return;   // nothing to assert in an org with a single profile
        }
        PEUserSearchService.Filters f = filtersForTestData();
        f.profileId = others[0].Id;

        Test.startTest();
        PEDto.PagedResult r = PEUserSearchService.search(f, null, 50);
        Test.stopTest();

        Assert.areEqual(
            0, r.records.size(),
            'seeded users are all admins, so another profile must match none'
        );
    }

    @IsTest
    static void roleFilterIsApplied() {
        List<UserRole> roles = [SELECT Id FROM UserRole WITH USER_MODE LIMIT 1];
        if (roles.isEmpty()) {
            return;   // no role hierarchy in this org
        }
        PEUserSearchService.Filters f = filtersForTestData();
        f.roleId = roles[0].Id;

        Test.startTest();
        PEDto.PagedResult r = PEUserSearchService.search(f, null, 50);
        Test.stopTest();

        Assert.isNotNull(r, 'role filter must not throw');
        Assert.areEqual(
            0, r.records.size(),
            'seeded users have no role, so a role filter must exclude them'
        );
    }

    @IsTest
    static void userTypeFilterIsApplied() {
        PEUserSearchService.Filters f = filtersForTestData();
        f.userType = 'Standard';

        Test.startTest();
        PEDto.PagedResult r = PEUserSearchService.search(f, null, 50);
        Test.stopTest();

        Assert.areEqual(6, r.records.size(), 'seeded users are Standard type');
    }

    @IsTest
    static void allFiltersTogetherDoNotConflict() {
        Profile admin = [
            SELECT Id FROM Profile WHERE Name = 'System Administrator' WITH USER_MODE LIMIT 1
        ];
        PEUserSearchService.Filters f = filtersForTestData();
        f.profileId = admin.Id;
        f.userType  = 'Standard';

        Test.startTest();
        PEDto.PagedResult r = PEUserSearchService.search(f, null, 50);
        Test.stopTest();

        Assert.areEqual(6, r.records.size(), 'stacked filters must AND, not conflict');
    }

    /* ---------------------------------------------------------------
     * Keyset pagination — the part that breaks silently
     * --------------------------------------------------------------- */

    @IsTest
    static void pagingCollectsEveryRowExactlyOnce() {
        Set<Id> seen = new Set<Id>();
        Integer pages = 0;
        String cursor = null;

        Test.startTest();
        do {
            PEDto.PagedResult r = PEUserSearchService.search(filtersForTestData(), cursor, 2);
            for (PEDto.UserRow row : r.records) {
                Assert.isTrue(
                    seen.add(row.userId),
                    'row appeared on more than one page: ' + row.name
                );
            }
            cursor = r.hasMore ? r.nextCursor : null;
            pages++;
        } while (cursor != null && pages < 10);
        Test.stopTest();

        Assert.areEqual(
            6, seen.size(),
            'paging must visit all six seeded users with no gaps'
        );
        Assert.isTrue(pages <= 4, 'six rows at two per page should not need more than four passes');
    }

    @IsTest
    static void firstPageReportsMoreWhenMoreExist() {
        Test.startTest();
        PEDto.PagedResult r = PEUserSearchService.search(filtersForTestData(), null, 2);
        Test.stopTest();

        Assert.areEqual(2, r.records.size(), 'page size must be respected');
        Assert.isTrue(r.hasMore, 'six matches at page size two means more remain');
        Assert.isNotNull(r.nextCursor, 'a cursor must be issued when more remain');
        Assert.isTrue(r.capReached, 'a filtered search with more rows sets the refine hint');
    }

    @IsTest
    static void lastPageReportsNoMore() {
        Test.startTest();
        PEDto.PagedResult r = PEUserSearchService.search(filtersForTestData(), null, 50);
        Test.stopTest();

        Assert.isFalse(r.hasMore, 'all six fit on one page');
        Assert.isNull(r.nextCursor, 'no cursor when there is nothing further');
    }

    @IsTest
    static void nullPageSizeFallsBackToDefault() {
        Test.startTest();
        PEDto.PagedResult r = PEUserSearchService.search(filtersForTestData(), null, null);
        Test.stopTest();

        Assert.areEqual(
            PEConstants.USER_PAGE_SIZE, r.pageSize,
            'null page size must use the configured default'
        );
    }

    /* ---------------------------------------------------------------
     * Sort handling
     * --------------------------------------------------------------- */

    @IsTest
    static void lastLoginSortIsAcceptedAndPages() {
        PEUserSearchService.Filters f = filtersForTestData();
        f.sortField = 'LastLoginDate';

        Test.startTest();
        PEDto.PagedResult first = PEUserSearchService.search(f, null, 2);
        PEDto.PagedResult second = first.hasMore
            ? PEUserSearchService.search(f, first.nextCursor, 2)
            : null;
        Test.stopTest();

        Assert.isNotNull(first, 'descending sort must not throw');
        Assert.areEqual(2, first.records.size(), 'page size respected on the descending path');
        if (second != null) {
            Assert.isNotNull(second.records, 'continuation on a null-last-login set must not throw');
        }
    }

    @IsTest
    static void disallowedSortFieldFallsBackToName() {
        PEUserSearchService.Filters f = filtersForTestData();
        f.sortField = 'Id DESC, Name';   // injection-shaped, must never reach the query

        Test.startTest();
        PEDto.PagedResult r = PEUserSearchService.search(f, null, 50);
        Test.stopTest();

        Assert.areEqual(
            6, r.records.size(),
            'a rejected sort field must fall back to Name, not break the query'
        );
    }

    @IsTest
    static void quoteInTermIsBoundNotInterpolated() {
        PEUserSearchService.Filters f = new PEUserSearchService.Filters();
        f.term = '\' OR Name LIKE \'%';

        Test.startTest();
        PEDto.PagedResult r = PEUserSearchService.search(f, null, 5);
        Test.stopTest();

        Assert.isNotNull(r, 'a quote in the term must be bound, never concatenated');
        Assert.areEqual(0, r.records.size(), 'no user name contains that literal string');
    }

    /* ---------------------------------------------------------------
     * Header helpers
     * --------------------------------------------------------------- */

    @IsTest
    static void isFrozenIsFalseForANewUser() {
        User u = [
            SELECT Id FROM User WHERE LastName = :SURNAME WITH USER_MODE LIMIT 1
        ];

        Test.startTest();
        Boolean frozen = PEUserSearchService.isFrozen(u.Id);
        Test.stopTest();

        Assert.isFalse(frozen, 'a freshly created user is not frozen');
    }

    @IsTest
    static void filterOptionsReturnsProfilesAndRolesAndCaches() {
        Test.startTest();
        Map<String, Object> first = PEUserSearchService.filterOptions();
        Map<String, Object> second = PEUserSearchService.filterOptions();
        Test.stopTest();

        Assert.isNotNull(first.get('profiles'), 'profiles key must be present');
        Assert.isNotNull(first.get('roles'), 'roles key must be present');
        Assert.isFalse(
            ((List<Map<String, String>>) first.get('profiles')).isEmpty(),
            'every org has at least one profile'
        );
        Assert.areEqual(
            ((List<Map<String, String>>) first.get('profiles')).size(),
            ((List<Map<String, String>>) second.get('profiles')).size(),
            'second call must agree with the first, cached or not'
        );
    }
}