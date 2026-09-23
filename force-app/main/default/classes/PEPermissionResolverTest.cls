/**
 * Covers PEPermissionResolver, including the group and muting paths.
 *
 * Why this class exists separately from PermissionExplorerTest: the resolver
 * scored 83% in a dev org but only 59% during package validation. That 24-point
 * gap was not a missing assertion — it was that loadGroupComponents() and
 * loadMutingSets() never executed, because package validation runs in a fresh
 * scratch org with no permission set groups in it. Tests that read whatever the
 * org happens to contain pass locally and cover nothing on a clean build.
 *
 * So this class builds its own permission sets, group, group components, and
 * assignments in @TestSetup. Everything it asserts, it created.
 *
 * One platform note: a freshly inserted PermissionSetGroup has Status
 * 'Outdated' until Salesforce recalculates it, which conveniently exercises the
 * outdatedGroups branch. Test.calculatePermissionSetGroup() forces the
 * recalculation so the settled branch can be reached too.
 */
@IsTest
// Every method is a unit test against data this class creates in @TestSetup:
// either pure applyGrant logic on synthetic Ids or resolve() assertions about
// the inspected subject user's assignments and groups. The running user's own
// context is never asserted, and a runAs user would not see the subject's
// PermissionSetAssignment or group rows through the USER_MODE queries, so no
// meaningful runAs exists without changing the scenario.
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
private class PEPermissionResolverTest {

    private static final String SUBJECT_ALIAS = 'perSubj';
    private static final String SET_A = 'PE_Test_Set_A';
    private static final String SET_B = 'PE_Test_Set_B';
    private static final String GROUP_NAME = 'PE_Test_Group';

    @TestSetup
    static void makeData() {
        Profile admin = [
            SELECT Id FROM Profile WHERE Name = 'System Administrator' WITH USER_MODE LIMIT 1
        ];
        String stamp = String.valueOf(Datetime.now().getTime());

        User subject = new User(
            FirstName = 'Resolver',
            LastName  = 'Subject',
            Alias     = SUBJECT_ALIAS,
            Email     = 'persubj@example.invalid',
            Username  = 'persubj.' + stamp + '@example.invalid',
            ProfileId = admin.Id,
            TimeZoneSidKey    = 'GMT',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert subject;

        // Two custom permission sets: A assigned directly, B only via the group.
        List<PermissionSet> sets = new List<PermissionSet>{
            new PermissionSet(Name = SET_A, Label = 'PE Test Set A'),
            new PermissionSet(Name = SET_B, Label = 'PE Test Set B')
        };
        insert sets;

        PermissionSetGroup grp = new PermissionSetGroup(
            DeveloperName = GROUP_NAME,
            MasterLabel   = 'PE Test Group'
        );
        insert grp;

        // B contributes only because the group containing it is assigned.
        insert new PermissionSetGroupComponent(
            PermissionSetGroupId = grp.Id,
            PermissionSetId      = sets[1].Id
        );

        // A group must be recalculated before a user can be assigned to it:
        // Salesforce rejects the assignment with INVALID_CROSS_REFERENCE_KEY
        // while Status is still 'Outdated'. This is also why no test can create
        // an assigned-and-outdated group directly - see
        // addingAComponentCanMarkAnAssignedGroupOutdated() for how that state is
        // reached the way a real org reaches it.
        Test.calculatePermissionSetGroup(grp.Id);

        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(
                AssigneeId = subject.Id, PermissionSetId = sets[0].Id
            ),
            new PermissionSetAssignment(
                AssigneeId = subject.Id, PermissionSetGroupId = grp.Id
            )
        };
    }

    private static Id subjectId() {
        return [SELECT Id FROM User WHERE Alias = :SUBJECT_ALIAS WITH USER_MODE LIMIT 1].Id;
    }

    private static Id groupId() {
        return [
            SELECT Id FROM PermissionSetGroup
            WHERE DeveloperName = :GROUP_NAME WITH USER_MODE LIMIT 1
        ].Id;
    }

    /* ---------------------------------------------------------------
     * Direct assignment and profile-as-permission-set
     * --------------------------------------------------------------- */

    @IsTest
    static void resolveFindsTheDirectlyAssignedSet() {
        Id uid = subjectId();

        Test.startTest();
        PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(uid, true);
        Test.stopTest();

        Assert.isNotNull(r, 'resolve must never return null');
        Assert.isFalse(r.effectiveParents.isEmpty(), 'at least the profile set must contribute');
        Assert.isTrue(r.permSetCount >= 1, 'the directly assigned set must be counted');
        Assert.isFalse(r.directPermSets.isEmpty(), 'the direct set list must be populated');
        Assert.isNotNull(r.resolvedAt, 'resolution must be timestamped');
    }

    @IsTest
    static void profileIsResolvedAsAPermissionSet() {
        Id uid = subjectId();

        Test.startTest();
        PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(uid, true);
        Test.stopTest();

        Assert.isNotNull(
            r.profilePermSetId,
            'the profile-owned permission set is the base of every grant and must resolve'
        );
        Assert.isTrue(
            r.effectiveParents.contains(r.profilePermSetId),
            'the profile set must be among the effective parents'
        );
    }

    @IsTest
    static void directSetIsNotDoubleCountedAsGroupDerived() {
        Id uid = subjectId();

        Test.startTest();
        PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(uid, true);
        Test.stopTest();

        Assert.areEqual(
            r.directPermSets.size(), r.permSetCount,
            'the header count and the drill-down list must be produced by the same pass'
        );
    }

    /* ---------------------------------------------------------------
     * Group paths — the methods that never ran during package validation
     * --------------------------------------------------------------- */

    @IsTest
    static void assignedGroupIsReported() {
        Id uid = subjectId();

        Test.startTest();
        PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(uid, true);
        Test.stopTest();

        Assert.areEqual(1, r.permSetGroupCount, 'one group is assigned to the subject');
        Assert.areEqual(1, r.assignedGroups.size(), 'the group row must be built');
        Assert.isNotNull(
            r.assignedGroups[0].masterLabel,
            'buildGroupRow must populate a label'
        );
    }

    @IsTest
    static void groupMemberSetContributesGrants() {
        Id uid = subjectId();
        Id setB = [
            SELECT Id FROM PermissionSet WHERE Name = :SET_B WITH USER_MODE LIMIT 1
        ].Id;

        Test.startTest();
        PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(uid, true);
        Test.stopTest();

        Assert.isTrue(
            r.effectiveParents.contains(setB),
            'a set inside an assigned group must contribute, or grants are understated'
        );
        Assert.isTrue(
            r.groupDerivedCount >= 1,
            'the group-derived count must acknowledge the set it pulled in'
        );
    }

    @IsTest
    static void recalculatedGroupIsNotFlaggedAsOutdated() {
        // makeData already recalculated the group, because the assignment would
        // otherwise have been rejected. So the settled state is the baseline.
        Id uid = subjectId();

        Test.startTest();
        PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(uid, true);
        Test.stopTest();

        Assert.isNotNull(r.outdatedGroups, 'the outdated list must never be null');
        Assert.isTrue(
            r.outdatedGroups.isEmpty(),
            'a recalculated group must not be reported as outdated'
        );
        Assert.isFalse(
            r.assignedGroups[0].isOutdated,
            'the row the UI renders must agree with the outdated list'
        );
    }

    @IsTest
    static void addingAComponentCanMarkAnAssignedGroupOutdated() {
        // This is how a real org ends up with an assigned-but-unsettled group:
        // an admin adds a permission set to a group that users are already
        // assigned to, and recalculation has not caught up. The resolver must
        // report that rather than presenting the grants as authoritative.
        Id uid = subjectId();
        Id gid = groupId();

        PermissionSet extra = new PermissionSet(
            Name = 'PE_Test_Set_C', Label = 'PE Test Set C'
        );
        insert extra;

        Test.startTest();
        insert new PermissionSetGroupComponent(
            PermissionSetGroupId = gid, PermissionSetId = extra.Id
        );

        String status = [
            SELECT Status FROM PermissionSetGroup WHERE Id = :gid WITH USER_MODE LIMIT 1
        ].Status;

        PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(uid, true);
        Test.stopTest();

        Assert.isNotNull(r.outdatedGroups, 'the outdated list must never be null');

        // Whether adding a component flips Status synchronously in a test
        // context is Salesforce's choice, not ours. Assert against the status we
        // actually observed so this test states a truth rather than a hope.
        if (status != 'Updated') {
            Assert.isFalse(
                r.outdatedGroups.isEmpty(),
                'a group reporting Status ' + status + ' must be flagged as outdated'
            );
            Assert.isTrue(
                r.assignedGroups[0].isOutdated,
                'the rendered row must carry the outdated flag too'
            );
        } else {
            Assert.isTrue(
                r.outdatedGroups.isEmpty(),
                'a group still reporting Updated must not be flagged'
            );
        }
    }

    /* ---------------------------------------------------------------
     * Caching
     * --------------------------------------------------------------- */

    @IsTest
    static void cachedResolveAgreesWithForcedResolve() {
        Id uid = subjectId();

        Test.startTest();
        PEPermissionResolver.Resolved cold = PEPermissionResolver.resolve(uid, true);
        PEPermissionResolver.Resolved warm = PEPermissionResolver.resolve(uid);
        Test.stopTest();

        Assert.areEqual(
            cold.effectiveParents.size(), warm.effectiveParents.size(),
            'the cached read must not disagree with the computed one'
        );
        Assert.areEqual(
            cold.profilePermSetId, warm.profilePermSetId,
            'caching must not change which profile set was resolved'
        );
    }

    @IsTest
    static void parentListExposesEffectiveParentsForBinding() {
        Id uid = subjectId();

        Test.startTest();
        PEPermissionResolver.Resolved r = PEPermissionResolver.resolve(uid, true);
        List<Id> asList = r.parentList;
        Test.stopTest();

        Assert.areEqual(
            r.effectiveParents.size(), asList.size(),
            'parentList must expose every effective parent for SOQL binding'
        );
        for (Id parentId : asList) {
            Assert.isTrue(
                r.effectiveParents.contains(parentId),
                'parentList must not invent a parent'
            );
        }
    }

    /* ---------------------------------------------------------------
     * applyGrant — additive union, muting subtracts
     * --------------------------------------------------------------- */

    @IsTest
    static void grantIsUnionedAcrossEffectiveParents() {
        PEPermissionResolver.Resolved r = new PEPermissionResolver.Resolved();
        Id p1 = fakeSetId(1);
        Id p2 = fakeSetId(2);
        r.effectiveParents.addAll(new List<Id>{ p1, p2 });

        Test.startTest();
        PEDto.Grant g = PEPermissionResolver.applyGrant(
            'PermissionsViewAllData', 'View All Data', r,
            new Map<Id, Boolean>{ p1 => false, p2 => true },
            new Map<Id, Boolean>()
        );
        Test.stopTest();

        Assert.isTrue(g.granted, 'a grant from any one parent must apply');
    }

    @IsTest
    static void absentParentEntryIsNotAGrant() {
        PEPermissionResolver.Resolved r = new PEPermissionResolver.Resolved();
        r.effectiveParents.add(fakeSetId(1));

        Test.startTest();
        PEDto.Grant g = PEPermissionResolver.applyGrant(
            'PermissionsModifyAllData', 'Modify All Data', r,
            new Map<Id, Boolean>(), new Map<Id, Boolean>()
        );
        Test.stopTest();

        Assert.isFalse(
            g.granted,
            'a missing row means not granted, and must never read as unknown'
        );
    }

    @IsTest
    static void mutingRemovesAnOtherwiseGrantedPermission() {
        PEPermissionResolver.Resolved r = new PEPermissionResolver.Resolved();
        Id parentId = fakeSetId(1);
        Id mutingId = fakeSetId(9);
        r.effectiveParents.add(parentId);
        r.mutingParents.add(mutingId);

        Test.startTest();
        PEDto.Grant g = PEPermissionResolver.applyGrant(
            'PermissionsViewAllData', 'View All Data', r,
            new Map<Id, Boolean>{ parentId => true },
            new Map<Id, Boolean>{ mutingId => true }
        );
        Test.stopTest();

        Assert.isFalse(
            g.granted,
            'muting is the only subtractive mechanism and must win over a grant'
        );
    }

    @IsTest
    static void mutingAnUngrantedPermissionInventsNothing() {
        PEPermissionResolver.Resolved r = new PEPermissionResolver.Resolved();
        Id parentId = fakeSetId(1);
        Id mutingId = fakeSetId(9);
        r.effectiveParents.add(parentId);
        r.mutingParents.add(mutingId);

        Test.startTest();
        PEDto.Grant g = PEPermissionResolver.applyGrant(
            'PermissionsViewAllData', 'View All Data', r,
            new Map<Id, Boolean>{ parentId => false },
            new Map<Id, Boolean>{ mutingId => true }
        );
        Test.stopTest();

        Assert.isFalse(g.granted, 'muting something never granted must stay not granted');
    }

    /* ---------------------------------------------------------------
     * Helpers
     * --------------------------------------------------------------- */

    /**
     * Synthetic PermissionSet Ids. applyGrant only uses them as map keys.
     *
     * @param n Numeric suffix used solely to keep generated Ids distinct.
     * @return Synthetic PermissionSet Id used only as a map key.
     */
    private static Id fakeSetId(Integer n) {
        return Id.valueOf('0PS000000000' + String.valueOf(n).leftPad(3, '0'));
    }
}