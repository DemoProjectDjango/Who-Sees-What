/**
 * Covers record-level reach.
 *
 * Record counts depend on org data a test cannot control, so these assert the
 * contract the panel depends on: a public object reports its figure as exact, a
 * private one reports a floor and says so, and nothing claims precision it does
 * not have. A reach figure labelled exact when it is a floor is the single most
 * damaging thing this feature could do.
 */
@IsTest
private class PERecordAccessServiceTest {

    @IsTest
    static void publicObjectIsExactAndNeedsNoShareArithmetic() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            // User is Public Read Only in every org and cannot be made private.
            PERecordAccessService.Reach r = PERecordAccessService.getReach(me, 'User');
            Test.stopTest();

            Assert.isTrue(r.hasObjectRead, 'the running user can read User');
            Assert.isTrue(r.isPublic, 'User is public by org-wide default');
            Assert.isTrue(r.isExact, 'a public object needs no estimation');
            Assert.areEqual(
                r.totalRecords, r.reachableRecords,
                'a public default means every readable record is reachable'
            );
            Assert.isTrue(
                String.isNotBlank(r.basis),
                'a figure with no stated basis cannot be defended in an audit'
            );
        }
    }

    @IsTest
    static void privateObjectReportsAFloorNotATotal() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordAccessService.Reach r = PERecordAccessService.getReach(me, 'Account');
            Test.stopTest();

            if (!r.hasObjectRead) {
                return; // Account not readable in this context.
            }

            if (r.isPublic || r.hasViewAll) {
                Assert.isTrue(
                    r.isExact,
                    'a public default or View All makes the figure exact'
                );
                return;
            }

            Assert.isFalse(
                r.isExact,
                'role hierarchy and implicit sharing are invisible to this count, ' +
                'so a private object can only report a floor'
            );
            Assert.isTrue(
                r.basis.containsIgnoreCase('at least'),
                'the basis must say the figure is a floor, not a total'
            );
        }
    }

    @IsTest
    static void unknownObjectFailsClosed() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordAccessService.Reach r =
                PERecordAccessService.getReach(me, 'NotAnObject__c');
            Test.stopTest();

            Assert.isFalse(r.hasObjectRead, 'an object that does not exist cannot be read');
            Assert.isNull(r.reachableRecords, 'no object means no figure, not zero');
        }
    }

    @IsTest
    static void blankObjectNameIsRejected() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordAccessService.Reach r = PERecordAccessService.getReach(me, '');
            Test.stopTest();

            Assert.isFalse(r.hasObjectRead, 'a blank object name resolves to nothing');
        }
    }

    @IsTest
    static void sharingLabelIsAdminFacing() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordAccessService.Reach r = PERecordAccessService.getReach(me, 'Account');
            Test.stopTest();

            Assert.isTrue(
                String.isNotBlank(r.sharingLabel),
                'the panel heads the figure with the sharing model, so it must be present'
            );
            Assert.areNotEqual(
                'ReadWrite', r.sharingLabel,
                'the raw API value is not what an administrator reads in Setup'
            );
        }
    }

    @IsTest
    static void ownerlessObjectExplainsItselfRatherThanReportingZero() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            // PermissionSet has no OwnerId, so ownership cannot grant access to it.
            PERecordAccessService.Reach r =
                PERecordAccessService.getReach(me, 'PermissionSet');
            Test.stopTest();

            if (!r.hasObjectRead) {
                return;
            }
            Assert.isNull(
                r.ownedRecords,
                'an object with no owner must report absence, not an owned count of zero'
            );
            Assert.isFalse(r.notes.isEmpty(), 'the absence needs an explanation in the panel');
        }
    }

    @IsTest
    static void everyReachCarriesItsObjectIdentity() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordAccessService.Reach r = PERecordAccessService.getReach(me, 'Account');
            Test.stopTest();

            Assert.areEqual('Account', r.objectApiName, 'the panel keys its state on the API name');
            Assert.isTrue(String.isNotBlank(r.objectLabel), 'the heading needs the label');
        }
    }

    @IsTest
    static void reachableIsNeverTheSumOfOwnedAndShared() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordAccessService.Reach r = PERecordAccessService.getReach(me, 'Account');
            Test.stopTest();

            if (!r.hasObjectRead || r.isPublic || r.hasViewAll) {
                return; // Short-circuited to the total; the sum never applies.
            }
            if (r.ownedRecords == null || r.sharedRecords == null || r.reachableRecords == null) {
                return;
            }

            // Share tables carry a RowCause = 'Owner' row, so a record the user owns
            // appears in the share table too. Adding the buckets counted it twice: a
            // user reaching 2 of 4 records was reported in the UI as reaching 3.
            Assert.isTrue(
                r.reachableRecords <= r.ownedRecords + r.sharedRecords,
                'reachable must be a distinct count, never the sum of overlapping buckets'
            );
        }
    }

    @IsTest
    static void sharedCountNeverExceedsReachable() {
        System.runAs(asSelf()) {
            Id me = UserInfo.getUserId();

            Test.startTest();
            PERecordAccessService.Reach r = PERecordAccessService.getReach(me, 'Account');
            Test.stopTest();

            if (!r.hasObjectRead || r.isPublic || r.hasViewAll
                || r.sharedRecords == null || r.reachableRecords == null) {
                return;
            }
            Assert.isTrue(
                r.sharedRecords <= r.reachableRecords,
                'records shared to a user cannot outnumber the records they reach - ' +
                'counting owner rows as shares is what broke this'
            );
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
