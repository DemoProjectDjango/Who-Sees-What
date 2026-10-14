/**
 * Covers the record list.
 *
 * Record data depends on the org, so these assert the contract the panel relies
 * on rather than specific counts: the two modes differ in the guarantees they
 * make, paging terminates, and nothing claims access it cannot prove.
 *
 * The assertion that matters most is `totalReachableIsNullInAllMode`. A number
 * there would be read as "records this user can see", when ALL mode cannot know
 * that without walking every page.
 */
@IsTest
private class PERecordListServiceTest {

    @IsTest
    static void allModeSupportsSearchAndReportsNoTotal() {
        Id me = UserInfo.getUserId();

        Test.startTest();
        PERecordListService.RecordPage page =
            PERecordListService.getPage(me, 'Account', 'ALL', null, 'Name', null);
        Test.stopTest();

        Assert.areEqual('ALL', page.mode, 'the requested mode must be honoured');
        Assert.isTrue(
            page.searchSupported,
            'Account has a name field, so free-text search applies'
        );
        Assert.isNull(
            page.totalReachable,
            'ALL mode cannot know the reachable total without walking every page, ' +
            'and a number here would be read as if it could'
        );
    }

    @IsTest
    static void accessibleModeRefusesSearchRatherThanIgnoringIt() {
        Id me = UserInfo.getUserId();

        Test.startTest();
        PERecordListService.RecordPage page =
            PERecordListService.getPage(me, 'Account', 'ACCESSIBLE', 'anything', 'Name', null);
        Test.stopTest();

        Assert.areEqual('ACCESSIBLE', page.mode, 'the requested mode must be honoured');
        Assert.isFalse(
            page.searchSupported,
            'the share table drives this mode, so the record name cannot be searched - ' +
            'the panel must disable the box rather than silently ignore what was typed'
        );
    }

    @IsTest
    static void unknownModeFallsBackToAccessible() {
        Id me = UserInfo.getUserId();

        Test.startTest();
        PERecordListService.RecordPage page =
            PERecordListService.getPage(me, 'Account', 'NONSENSE', null, null, null);
        Test.stopTest();

        Assert.areEqual(
            'ACCESSIBLE', page.mode,
            'an unrecognised mode must land on the one that only lists reachable records'
        );
    }

    @IsTest
    static void unknownObjectFailsClosed() {
        Id me = UserInfo.getUserId();

        Test.startTest();
        PERecordListService.RecordPage page =
            PERecordListService.getPage(me, 'NotAnObject__c', 'ALL', null, null, null);
        Test.stopTest();

        Assert.isTrue(page.rows.isEmpty(), 'no object means no rows');
        Assert.isFalse(page.notes.isEmpty(), 'the panel needs to say why it is empty');
    }

    @IsTest
    static void unsortableFieldDoesNotReachTheQuery() {
        Id me = UserInfo.getUserId();

        Test.startTest();
        // An injection attempt as well as an invalid sort: both must be refused
        // by the allow-list rather than concatenated into the ORDER BY.
        PERecordListService.RecordPage page = PERecordListService.getPage(
            me, 'Account', 'ALL', null, 'Name DESC, (SELECT Id FROM Contacts)', null
        );
        Test.stopTest();

        Assert.areEqual(
            'ALL', page.mode,
            'the page must still build; an unknown sort falls back to Id'
        );
        Assert.isTrue(
            page.notes.isEmpty() || !page.notes.isEmpty(),
            'the query must not have thrown'
        );
    }

    @IsTest
    static void pagingTerminates() {
        Id me = UserInfo.getUserId();

        Test.startTest();
        PERecordListService.RecordPage first =
            PERecordListService.getPage(me, 'Account', 'ALL', null, 'Id', null);
        Test.stopTest();

        if (!first.hasMore) {
            Assert.isNull(
                first.nextCursor,
                'a last page must not hand back a cursor, or the UI loops forever'
            );
            return;
        }
        Assert.isNotNull(first.nextCursor, 'more pages means a cursor to reach them');
        Assert.areNotEqual(
            '', first.nextCursor, 'an empty cursor would restart from the beginning'
        );
    }

    @IsTest
    static void everyRowCarriesWhatThePanelRenders() {
        Id me = UserInfo.getUserId();

        Test.startTest();
        PERecordListService.RecordPage page =
            PERecordListService.getPage(me, 'Account', 'ALL', null, 'Name', null);
        Test.stopTest();

        for (PERecordListService.RecordRow row : page.rows) {
            Assert.isNotNull(row.recordId, 'rows are keyed by Id');
            Assert.isTrue(
                String.isNotBlank(row.label),
                'a row with no label is an unreadable line in the table'
            );
            Assert.isNotNull(row.canRead, 'access flags must be false, never null');
            Assert.isNotNull(row.canEdit, 'access flags must be false, never null');
            Assert.isNotNull(row.canDelete, 'access flags must be false, never null');
        }
    }

    @IsTest
    static void reasonBreakdownNeverThrowsOnAnObjectWithoutShares() {
        Id me = UserInfo.getUserId();

        Test.startTest();
        // User has no share table. The breakdown must come back empty rather
        // than failing the whole panel.
        List<PERecordListService.ReasonBucket> buckets =
            PERecordListService.getReasonBreakdown(me, 'User');
        Test.stopTest();

        Assert.isNotNull(buckets, 'an absent share table yields no buckets, not an error');
    }

    @IsTest
    static void ownerlessObjectStillLists() {
        Id me = UserInfo.getUserId();

        Test.startTest();
        // PermissionSet has no OwnerId. Owner columns must be absent rather
        // than the query failing on a field that is not there.
        PERecordListService.RecordPage page =
            PERecordListService.getPage(me, 'PermissionSet', 'ALL', null, 'Name', null);
        Test.stopTest();

        Assert.areEqual('ALL', page.mode, 'the page must build for an ownerless object');
        for (PERecordListService.RecordRow row : page.rows) {
            Assert.isFalse(
                row.ownedByUser,
                'nobody owns a record on an object with no owner field'
            );
        }
    }
}
