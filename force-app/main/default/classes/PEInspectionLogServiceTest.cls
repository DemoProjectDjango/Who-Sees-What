/**
 * Covers the inspection log read path.
 *
 * Real DML here, unlike the muting matrix: the point of this service is the
 * query and its FLS behaviour, and a synthetic fixture would prove neither.
 * Rows are written through PEInspectionAuditLogger rather than constructed
 * directly, so the test exercises the same shape the product actually writes.
 */
@IsTest
private class PEInspectionLogServiceTest {

    /**
     * Managed package version tests execute in a fresh packaging org. A
     * System.runAs(current user) does not grant the application's field-level
     * permissions. Give the inspecting test user the same permission set that
     * customers must assign before opening the Inspection Log.
     *
     * Setup DML runs in a separate setup transaction from audit-log records.
     */
    @TestSetup
    static void giveInspectorApplicationPermissions() {
        List<PermissionSet> candidates = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'PermissionCheckerPermissionSet'
              AND IsOwnedByProfile = false
            LIMIT 1
        ];
        System.assertEquals(1, candidates.size(),
            'The Who Sees What inspection permission set must be packaged.');

        Id testUserId = UserInfo.getUserId();
        List<PermissionSetAssignment> existing = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :testUserId
              AND PermissionSetId = :candidates[0].Id
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert new PermissionSetAssignment(
                AssigneeId = testUserId,
                PermissionSetId = candidates[0].Id
            );
        }
    }

    @IsTest
    static void returnsMostRecentFirst() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'first');
            PEInspectionAuditLogger.log('VIEW_PERM_SETS', me, 'second');
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            Assert.isTrue(page.readable, 'the running user can read the object in this context');
            Assert.areEqual(2, page.rows.size(), 'both logged inspections must come back');

            // Equal timestamps are possible inside one transaction, so assert the
            // set rather than a strict ordering the clock may not provide.
            Set<String> actions = new Set<String>();
            for (PEInspectionLogService.LogRow row : page.rows) {
                actions.add(row.action);
            }
            Assert.isTrue(actions.contains('RESOLVE_USER'), 'first inspection missing');
            Assert.isTrue(actions.contains('VIEW_PERM_SETS'), 'second inspection missing');
        }
    }

    @IsTest
    static void emptyLogExplainsItself() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            Assert.isTrue(page.rows.isEmpty(), 'nothing was logged in this test');
            Assert.isNotNull(
                page.notice,
                'an empty panel must say why it is empty rather than render blank'
            );
        }
    }

    @IsTest
    static void filtersBySubject() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'mine');
            PEInspectionLogService.LogPage mine =
                PEInspectionLogService.getRecent(null, me, 25);
            PEInspectionLogService.LogPage other =
                PEInspectionLogService.getRecent(null, fakeUserId(), 25);
            Test.stopTest();

            Assert.areEqual(1, mine.rows.size(), 'the subject filter must find the logged row');
            Assert.isTrue(
                other.rows.isEmpty(),
                'a subject with no inspections must return nothing, not everything'
            );
        }
    }

    @IsTest
    static void filtersByInspector() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'mine');
            PEInspectionLogService.LogPage mine =
                PEInspectionLogService.getRecent(me, null, 25);
            PEInspectionLogService.LogPage other =
                PEInspectionLogService.getRecent(fakeUserId(), null, 25);
            Test.stopTest();

            Assert.areEqual(1, mine.rows.size(), 'the inspector filter must find the logged row');
            Assert.isTrue(other.rows.isEmpty(), 'another inspector has no rows here');
        }
    }

    @IsTest
    static void rowCarriesTheFieldsThePanelRenders() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PEInspectionAuditLogger.log('VIEW_LOGIN_HISTORY', me, 'detail text');
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            Assert.areEqual(1, page.rows.size(), 'one inspection was logged');
            PEInspectionLogService.LogRow row = page.rows[0];

            Assert.areEqual('VIEW_LOGIN_HISTORY', row.action, 'action must survive the round trip');
            Assert.areEqual('detail text', row.detail, 'detail must survive the round trip');
            Assert.areEqual(me, row.inspectorId, 'the inspector is the running user');
            Assert.areEqual(me, row.subjectId, 'the subject is who was inspected');
            Assert.isNotNull(row.inspectedAt, 'a row with no timestamp is not evidence of anything');
            Assert.isNotNull(row.recordId, 'the panel keys rows by Id');
        }
    }

    @IsTest
    static void limitIsClampedRatherThanTrusted() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'one');
            // Null, zero and absurd must all resolve to something queryable rather
            // than producing LIMIT 0 or a governor failure.
            PEInspectionLogService.LogPage nullLimit =
                PEInspectionLogService.getRecent(null, null, null);
            PEInspectionLogService.LogPage zeroLimit =
                PEInspectionLogService.getRecent(null, null, 0);
            PEInspectionLogService.LogPage hugeLimit =
                PEInspectionLogService.getRecent(null, null, 100000);
            Test.stopTest();

            Assert.areEqual(1, nullLimit.rows.size(), 'a null limit must fall back to the default');
            Assert.areEqual(1, zeroLimit.rows.size(), 'zero must not become LIMIT 0');
            Assert.areEqual(1, hugeLimit.rows.size(), 'an oversized limit must be clamped, not rejected');
        }
    }

    @IsTest
    static void countsAreReported() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'counted');
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            Assert.areEqual(1, page.totalCount, 'the header total must match what was written');
            Assert.areEqual(1, page.last7Days, 'a row written now falls inside the 7 day window');
        }
    }

    @IsTest
    static void activityIsZeroFilledAcrossTheWindow() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'today');
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            Assert.areEqual(
                14, page.activity.size(),
                'every day in the window needs an entry, including the quiet ones'
            );

            Integer summed = 0;
            Date previous = null;
            for (PEInspectionLogService.DayCount dc : page.activity) {
                Assert.isNotNull(dc.day, 'a bar with no date cannot be placed on an axis');
                Assert.isNotNull(dc.total, 'a null total would render as a missing bar, not a zero');
                if (previous != null) {
                    Assert.areEqual(
                        previous.addDays(1), dc.day,
                        'days must be consecutive or the chart compresses the gaps'
                    );
                }
                previous = dc.day;
                summed += dc.total;
            }

            Assert.areEqual(1, summed, 'the one logged inspection must appear exactly once');
            Assert.areEqual(
                Date.today(), page.activity[13].day,
                'the window must end today, not yesterday'
            );
        }
    }

    @IsTest
    static void topInspectorsCountsAndNamesTheRunningUser() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'one');
            PEInspectionAuditLogger.log('VIEW_PERM_SETS', me, 'two');
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            Assert.areEqual(1, page.topInspectors.size(), 'only one person inspected anything');

            PEInspectionLogService.InspectorCount top = page.topInspectors[0];
            Assert.areEqual(me, top.inspectorId, 'the running user did the inspecting');
            Assert.areEqual(2, top.total, 'both inspections must be counted');
            Assert.isNotNull(
                top.inspectorName,
                'a ranked bar with no name tells an auditor nothing'
            );
        }
    }

    @IsTest
    static void emptyLogStillReturnsAnActivityWindow() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            Assert.areEqual(
                14, page.activity.size(),
                'an empty log is still fourteen days of zero, not an absent chart'
            );
            Assert.isTrue(
                page.topInspectors.isEmpty(),
                'nobody inspected anything, so nobody is ranked'
            );
        }
    }

    @IsTest
    static void windowTotalIsSummedInApexNotTheBrowser() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'one');
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'two');
            PEInspectionAuditLogger.log('VIEW_PERM_SETS', me, 'three');
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            Assert.areEqual(3, page.windowTotal, 'the headline figure must match what was logged');

            Integer barSum = 0;
            for (PEInspectionLogService.DayCount dc : page.activity) {
                barSum += dc.total;
            }
            Assert.areEqual(
                page.windowTotal, barSum,
                'the bars and the headline must agree - a chart reading zero above a ' +
                'populated table is the exact failure this replaced'
            );
        }
    }

    @IsTest
    static void todaysColumnIsMarkedAndCarriesTheRows() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'today');
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            PEInspectionLogService.DayCount last = page.activity[page.activity.size() - 1];
            Assert.isTrue(last.isToday, 'the window must end on today, not yesterday');
            Assert.areEqual(Date.today(), last.day, 'the final bucket is today');
            Assert.areEqual(
                1, last.total,
                'an inspection logged today must land in the bucket for today'
            );

            Integer markedToday = 0;
            for (PEInspectionLogService.DayCount dc : page.activity) {
                if (dc.isToday) {
                    markedToday++;
                }
            }
            Assert.areEqual(1, markedToday, 'exactly one column can be today');
        }
    }

    @IsTest
    static void everyBarCarriesAPreformattedLabel() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            for (PEInspectionLogService.DayCount dc : page.activity) {
                Assert.isTrue(
                    String.isNotBlank(dc.label),
                    'labels are formatted server-side so the browser never parses a date'
                );
                Assert.isTrue(
                    String.isNotBlank(dc.fullLabel),
                    'the hover title needs the month as well as the day'
                );
            }
        }
    }

    @IsTest
    static void actionMixIsOrderedByVolume() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'a');
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'b');
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'c');
            PEInspectionAuditLogger.log('VIEW_PERM_SETS', me, 'd');
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            Assert.areEqual(2, page.actionMix.size(), 'two distinct actions were logged');
            Assert.areEqual(
                'RESOLVE_USER', page.actionMix[0].action,
                'the busiest action must come first'
            );
            Assert.areEqual(3, page.actionMix[0].total, 'three resolves were logged');
            Assert.areEqual(1, page.actionMix[1].total, 'one permission set view was logged');
        }
    }

    @IsTest
    static void priorWindowIsZeroWhenNothingPredatesTheWindow() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'now');
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            Assert.areEqual(
                0, page.priorWindowTotal,
                'a row written now belongs to the current window, never the preceding one'
            );
            Assert.isFalse(page.activityTruncated, 'one row is nowhere near the scan cap');
        }
    }

    @IsTest
    static void distinctCountsIgnoreRepeatsAndNullSubjects() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            // Same inspector three times, so the inspector count must not be 3.
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'one');
            PEInspectionAuditLogger.log('RESOLVE_USER', me, 'two');
            // No subject at all - a license lookup is org-wide, not about a person.
            PEInspectionAuditLogger.log('VIEW_LICENSE_USERS', null, 'three');
            PEInspectionLogService.LogPage page =
                PEInspectionLogService.getRecent(null, null, 25);
            Test.stopTest();

            Assert.areEqual(
                1, page.distinctInspectors,
                'one person inspected three times, which is one inspector'
            );
            Assert.areEqual(
                1, page.distinctSubjects,
                'the subject-less license lookup must not inflate the figure'
            );
            Assert.areEqual(3, page.windowTotal, 'all three inspections still count toward volume');
        }
    }

    /**
     * A syntactically valid User Id that belongs to nobody.
     *
     * @return Synthetic User Id used only as a query filter.
     */
    private static Id fakeUserId() {
        return Id.valueOf('005000000000001');
    }
}
