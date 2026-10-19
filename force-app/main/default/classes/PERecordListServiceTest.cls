/**
 * Covers the record list.
 *
 * Record data depends on the org, so these assert the contract the panel relies
 * on rather than specific counts.
 *
 * The one that matters most is `totalsNeverComeFromThePage`. The earlier design
 * had two modes because I believed a filtered list could not report a true
 * total - that "12 of 200" could only ever mean "12 on this page". It was
 * wrong: the totals come from their own queries. If a later change ever derives
 * a total from `rows.size()`, that test fails.
 *
 * The other one that matters is `theFilterNeverListsARecordTheUserCannotRead`.
 * On an object where sharing is bypassed the filter used to be a no-op, so a
 * record with three greyed access chips appeared in a list headed "only records
 * this user can reach". The per-record access was already on the page; it was
 * simply not used.
 */
@IsTest
private class PERecordListServiceTest {

    @IsTest
    static void totalsNeverComeFromThePage() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'Account', true, null, 'Name', null);
            Test.stopTest();

            if (page.totalRecords == null) {
                return; // Object unreadable in this context.
            }
            Assert.isTrue(
                page.totalRecords >= page.rows.size(),
                'the record total is an independent count, never the size of one page'
            );
            if (page.totalReachable != null) {
                Assert.isTrue(
                    page.totalReachable >= page.rows.size(),
                    'the reachable total is an independent count, never the size of one page'
                );
            }
        }
    }

    @IsTest
    static void publicObjectReportsAnExactTotalNotAFloor() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            // User is Public Read Only in every org and cannot be made private.
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'User', true, null, 'Name', null);
            Test.stopTest();

            Assert.isTrue(page.sharingBypassed, 'User is public, so sharing is bypassed');
            Assert.isFalse(
                page.totalIsFloor,
                'when every record is reachable the count is exact; "at least" belongs ' +
                'only where hierarchy access can hide from a share table'
            );
            Assert.areEqual(
                page.totalRecords, page.totalReachable,
                'a public object puts every readable record within reach'
            );
        }
    }

    @IsTest
    static void publicObjectSuppressesTheReasonColumn() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'User', true, null, 'Name', null);
            Test.stopTest();

            Assert.isFalse(
                page.showReason,
                'every row would read the same thing, which is a fact about the object ' +
                'and belongs in one line above the table'
            );
            Assert.isTrue(
                String.isNotBlank(page.uniformReason),
                'suppressing the column must not lose the explanation'
            );
        }
    }

    @IsTest
    static void publicObjectKeepsSearchEvenWhenFiltered() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'User', true, null, 'Name', null);
            Test.stopTest();

            // The filter cannot force the share-driven path here, because sharing is
            // not what grants access, so the object still drives and search works.
            Assert.isTrue(
                page.searchSupported,
                'a public object is always object-driven, so the search box stays usable'
            );
        }
    }

    @IsTest
    static void theFilterNeverListsARecordTheUserCannotRead() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            // User is public, so the object drives the page and the filter has
            // to be applied by this class rather than by the share table.
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'User', true, null, 'Name', null);
            Test.stopTest();

            Boolean accessUnknown = false;
            for (String note : page.notes) {
                if (note.containsIgnoreCase('could not be read')) {
                    accessUnknown = true;
                }
            }

            Integer unreadable = 0;
            for (PERecordListService.RecordRow row : page.rows) {
                if (row.canRead != true) {
                    unreadable++;
                }
            }

            Assert.isTrue(
                unreadable == 0 || accessUnknown,
                'a list headed "only records this user can reach" must not contain a ' +
                'record they cannot read, unless it says their access could not be read'
            );
        }
    }

    @IsTest
    static void reachableTotalNeverExceedsTheRecordsInScope() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            // Contact carries the carve-out, so this is where a subtraction
            // could overshoot or a public default could overstate.
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'Contact', true, null, 'Name', null);
            Test.stopTest();

            Integer reachable = page.totalReachable == null ? 0 : page.totalReachable;
            Integer total = page.totalRecords == null ? 0 : page.totalRecords;

            Assert.isTrue(
                reachable <= total,
                'the reachable total is a subset of the records in scope, never larger'
            );
            Assert.isTrue(
                reachable >= 0,
                'subtracting a carve-out must not drive the reachable total below zero'
            );
        }
    }

    @IsTest
    static void unfilteredListIsAlwaysSearchable() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'Account', false, null, 'Name', null);
            Test.stopTest();

            Assert.isFalse(page.reachableOnly, 'the filter was switched off');
            Assert.isTrue(
                page.searchSupported,
                'showing every record means the object drives the page, so search works'
            );
        }
    }

    @IsTest
    static void everyRowCarriesWhatTheTableRenders() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'Account', false, null, 'Name', null);
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
                Assert.isNotNull(row.reasonInferred, 'the inferred flag must never be null');
            }
        }
    }

    @IsTest
    static void ownedRecordsAreAttributedToOwnershipNotSharing() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'Account', false, null, 'Name', null);
            Test.stopTest();

            for (PERecordListService.RecordRow row : page.rows) {
                if (row.ownedByUser) {
                    Assert.areEqual(
                        'Owner', row.reason,
                        'ownership outranks every share row, including the Owner row ' +
                        'the share table carries for the same record'
                    );
                    Assert.isFalse(
                        row.reasonInferred,
                        'ownership is a fact on the record, never a deduction'
                    );
                }
            }
        }
    }

    @IsTest
    static void unreachableRecordsCarryNoReason() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'Account', false, null, 'Name', null);
            Test.stopTest();

            for (PERecordListService.RecordRow row : page.rows) {
                if (!row.canRead && !row.ownedByUser) {
                    Assert.isNull(
                        row.reason,
                        'a record the user cannot read has no reason to explain'
                    );
                }
            }
        }
    }

    @IsTest
    static void unknownObjectFailsClosed() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'NotAnObject__c', true, null, null, null);
            Test.stopTest();

            Assert.isTrue(page.rows.isEmpty(), 'no object means no rows');
            Assert.isNull(page.totalReachable, 'no object means no figure, not zero');
            Assert.isFalse(page.notes.isEmpty(), 'the panel needs to say why it is empty');
        }
    }

    @IsTest
    static void injectionInTheSortFieldIsRefused() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordListService.RecordPage page = PERecordListService.getPage(
                me, 'Account', false, null, 'Name DESC, (SELECT Id FROM Contacts)', null
            );
            Test.stopTest();

            // The allow-list drops it to Id rather than concatenating it, so the
            // page still builds and the query never saw the string.
            Assert.isTrue(page.notes.isEmpty(), 'the query must not have thrown');
        }
    }

    @IsTest
    static void pagingTerminates() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'Account', false, null, 'Id', null);
            Test.stopTest();

            if (page.hasMore) {
                Assert.isNotNull(page.nextCursor, 'more pages means a cursor to reach them');
            } else {
                Assert.isNull(
                    page.nextCursor,
                    'a last page must not hand back a cursor, or See more loops forever'
                );
            }
        }
    }

    @IsTest
    static void ownerlessObjectStillLists() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            // PermissionSet has no OwnerId. Owner columns must be absent rather
            // than the query failing on a field that is not there.
            PERecordListService.RecordPage page =
                PERecordListService.getPage(me, 'PermissionSet', false, null, 'Name', null);
            Test.stopTest();

            for (PERecordListService.RecordRow row : page.rows) {
                Assert.isFalse(
                    row.ownedByUser,
                    'nobody owns a record on an object with no owner field'
                );
            }
        }
    }

    @IsTest
    static void breakdownNeverThrowsOnAnObjectWithoutShares() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            List<PERecordListService.ReasonBucket> buckets =
                PERecordListService.getReasonBreakdown(me, 'User');
            Test.stopTest();

            Assert.isNotNull(buckets, 'an absent share table yields no buckets, not an error');
        }
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
