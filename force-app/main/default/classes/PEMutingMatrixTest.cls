/**
 * The muting correctness matrix from `docs/TESTING.md` section 3, executed.
 *
 * Muting is the product's only subtractive mechanism and its most likely silent
 * failure. Before this class existed, scenarios 5, 6 and 8 all returned "no
 * access" for users who held the permission, because muting was stored as one
 * flat set with no record of which group each muting set belonged to.
 *
 * Pure logic against synthetic Ids: no DML, no SOQL, no org fixtures. That is
 * deliberate - the matrix has to be runnable in any org, including a reviewer's,
 * without seeding two groups and three component sets first.
 */
@IsTest
private class PEMutingMatrixTest {

    private static final String PERM  = 'PermissionsRead';
    private static final String LABEL = 'Read';

    /* ---------------------------------------------------------------
     * 1-3: additive sources, no muting involved
     * --------------------------------------------------------------- */

    @IsTest
    static void row1_profileOnly() {
        PEPermissionResolver.Resolved r = newResolved();
        Id profileSet = addProfile(r, 1);

        PEDto.Grant g = run(r, granted(profileSet), noMutes());

        assertHasIt(g, 'profile grant with no muting in play');
    }

    @IsTest
    static void row2_directPermissionSetOnly() {
        PEPermissionResolver.Resolved r = newResolved();
        Id direct = addDirect(r, 2);

        PEDto.Grant g = run(r, granted(direct), noMutes());

        assertHasIt(g, 'direct assignment with no muting in play');
    }

    @IsTest
    static void row3_groupComponentOnly() {
        PEPermissionResolver.Resolved r = newResolved();
        Id groupA    = fakeGroupId(1);
        Id component = addComponent(r, 3, groupA);

        PEDto.Grant g = run(r, granted(component), noMutes());

        assertHasIt(g, 'group component grant with no muting set present');
    }

    /* ---------------------------------------------------------------
     * 4: the case that must subtract
     * --------------------------------------------------------------- */

    @IsTest
    static void row4_componentMutedByItsOwnGroup() {
        PEPermissionResolver.Resolved r = newResolved();
        Id groupA    = fakeGroupId(1);
        Id component = addComponent(r, 3, groupA);
        Id muting    = addMuting(r, 9, groupA);

        PEDto.Grant g = run(r, granted(component), mutes(muting));

        assertDeniedByMuting(g, 'a group muting its own component must subtract');
        Assert.areEqual(
            2, g.sources.size(),
            'a revoke decision needs the granting source and the muting source'
        );
    }

    /* ---------------------------------------------------------------
     * 5-6: muting must not reach outside its group
     * --------------------------------------------------------------- */

    @IsTest
    static void row5_unrelatedGroupMutingCannotTouchDirectAssignment() {
        PEPermissionResolver.Resolved r = newResolved();
        Id direct = addDirect(r, 2);
        Id groupA = fakeGroupId(1);
        Id muting = addMuting(r, 9, groupA);

        PEDto.Grant g = run(r, granted(direct), mutes(muting));

        assertHasIt(
            g,
            'muting is scoped to its own group and cannot revoke a direct assignment'
        );
    }

    @IsTest
    static void row6_groupMutingCannotTouchTheProfile() {
        PEPermissionResolver.Resolved r = newResolved();
        Id profileSet = addProfile(r, 1);
        Id groupA     = fakeGroupId(1);
        Id muting     = addMuting(r, 9, groupA);

        PEDto.Grant g = run(r, granted(profileSet), mutes(muting));

        assertHasIt(g, 'muting does not reach the profile');
    }

    /* ---------------------------------------------------------------
     * 7-8: several components, one mute
     * --------------------------------------------------------------- */

    @IsTest
    static void row7_twoComponentsInOneGroupMutedOnce() {
        PEPermissionResolver.Resolved r = newResolved();
        Id groupA = fakeGroupId(1);
        Id compA1 = addComponent(r, 3, groupA);
        Id compA2 = addComponent(r, 4, groupA);
        Id muting = addMuting(r, 9, groupA);

        Map<Id, Boolean> grants = granted(compA1);
        grants.put(compA2, true);

        PEDto.Grant g = run(r, grants, mutes(muting));

        assertDeniedByMuting(
            g, 'one mute covers every component of the group that owns it'
        );
    }

    @IsTest
    static void row8_mutedInGroupAButStillGrantedViaGroupB() {
        PEPermissionResolver.Resolved r = newResolved();
        Id groupA = fakeGroupId(1);
        Id groupB = fakeGroupId(2);
        Id compA  = addComponent(r, 3, groupA);
        Id compB  = addComponent(r, 4, groupB);
        Id muting = addMuting(r, 9, groupA);

        Map<Id, Boolean> grants = granted(compA);
        grants.put(compB, true);

        PEDto.Grant g = run(r, grants, mutes(muting));

        assertHasIt(g, 'group B still grants it; group A muting its own copy is irrelevant');
        Assert.areEqual(
            1, g.sources.size(),
            'only the surviving grant should be credited'
        );
        Assert.areEqual(
            compB, g.sources[0].parentId,
            'the muted component must not be shown as the reason the user has access'
        );
    }

    /* ---------------------------------------------------------------
     * 9: nothing to subtract from
     * --------------------------------------------------------------- */

    @IsTest
    static void row9_mutingSomethingNeverGranted() {
        PEPermissionResolver.Resolved r = newResolved();
        Id groupA    = fakeGroupId(1);
        Id component = addComponent(r, 3, groupA);
        Id muting    = addMuting(r, 9, groupA);

        PEDto.Grant g = run(
            r,
            new Map<Id, Boolean>{ component => false },
            mutes(muting)
        );

        Assert.isFalse(g.granted, 'never granted, so still not granted');
        Assert.isFalse(
            g.muted,
            'flagging a mute here would claim a revocation that never happened'
        );
    }

    /* ---------------------------------------------------------------
     * A component in two groups, muted in both
     * --------------------------------------------------------------- */

    @IsTest
    static void componentInTwoGroupsMutedInBothIsRevoked() {
        PEPermissionResolver.Resolved r = newResolved();
        Id groupA = fakeGroupId(1);
        Id groupB = fakeGroupId(2);

        Id shared = addComponent(r, 3, groupA);
        r.groupsByComponent.get(shared).add(groupB);

        Id mutingA = addMuting(r, 9, groupA);
        Id mutingB = addMuting(r, 10, groupB);

        Map<Id, Boolean> muteFlags = mutes(mutingA);
        muteFlags.put(mutingB, true);

        PEDto.Grant g = run(r, granted(shared), muteFlags);

        assertDeniedByMuting(
            g, 'every group the set arrived through mutes it, so nothing survives'
        );
    }

    /* ---------------------------------------------------------------
     * Back-compatibility: a muting set with no known group still applies
     * --------------------------------------------------------------- */

    @IsTest
    static void orphanMutingSetWithNoGroupStillApplies() {
        PEPermissionResolver.Resolved r = newResolved();
        Id component = addComponent(r, 3, fakeGroupId(1));

        // Registered as muting, but never associated with a group - the shape
        // loadMutingSets() produces for an orphan it cannot place.
        Id orphan = fakeSetId(11);
        r.mutingParents.add(orphan);
        r.sourcesById.put(orphan, new PEDto.Source(orphan, 'Orphan Mute', 'muting'));

        PEDto.Grant g = run(r, granted(component), mutes(orphan));

        assertDeniedByMuting(
            g,
            'an unexplained mute is safer treated as real than silently discarded'
        );
    }

    /* ---------------------------------------------------------------
     * Structural invariants
     * --------------------------------------------------------------- */

    @IsTest
    static void mutingSetsNeverAppearAsEffectiveParents() {
        PEPermissionResolver.Resolved r = newResolved();
        Id groupA = fakeGroupId(1);
        addComponent(r, 3, groupA);
        Id muting = addMuting(r, 9, groupA);

        Assert.isFalse(
            r.effectiveParents.contains(muting),
            'a muting set grants nothing and must never be treated as a grant source'
        );
        Assert.isTrue(
            r.sourcesById.containsKey(muting),
            'every muting parent needs a source chip for the revoke explanation'
        );
    }

    @IsTest
    static void mutingDoesNotLeakAcrossPermissions() {
        PEPermissionResolver.Resolved r = newResolved();
        Id groupA    = fakeGroupId(1);
        Id component = addComponent(r, 3, groupA);
        Id muting    = addMuting(r, 9, groupA);

        PEDto.Grant edit = PEPermissionResolver.applyGrant(
            'PermissionsEdit', 'Edit', r,
            new Map<Id, Boolean>{ component => true },
            new Map<Id, Boolean>{ muting => false }
        );

        Assert.isTrue(edit.granted, 'muting Read must not affect Edit');
        Assert.isFalse(edit.muted, 'Edit was never muted');
    }

    /* ---------------------------------------------------------------
     * Helpers
     * --------------------------------------------------------------- */

    private static PEPermissionResolver.Resolved newResolved() {
        return new PEPermissionResolver.Resolved();
    }

    private static PEDto.Grant run(
        PEPermissionResolver.Resolved r,
        Map<Id, Boolean> grantedByParent,
        Map<Id, Boolean> mutedByParent
    ) {
        return PEPermissionResolver.applyGrant(
            PERM, LABEL, r, grantedByParent, mutedByParent
        );
    }

    private static Id addProfile(PEPermissionResolver.Resolved r, Integer n) {
        Id profileSet = fakeSetId(n);
        r.profilePermSetId = profileSet;
        r.effectiveParents.add(profileSet);
        r.immuneParents.add(profileSet);
        r.sourcesById.put(profileSet, new PEDto.Source(profileSet, 'System Admin', 'profile'));
        return profileSet;
    }

    private static Id addDirect(PEPermissionResolver.Resolved r, Integer n) {
        Id direct = fakeSetId(n);
        r.effectiveParents.add(direct);
        r.immuneParents.add(direct);
        r.sourcesById.put(direct, new PEDto.Source(direct, 'Direct Set ' + n, 'permset'));
        return direct;
    }

    private static Id addComponent(PEPermissionResolver.Resolved r, Integer n, Id groupId) {
        Id component = fakeSetId(n);
        r.effectiveParents.add(component);
        if (!r.groupsByComponent.containsKey(component)) {
            r.groupsByComponent.put(component, new Set<Id>());
        }
        r.groupsByComponent.get(component).add(groupId);

        PEDto.Source src = new PEDto.Source(component, 'Component ' + n, 'group');
        src.groupId = groupId;
        r.sourcesById.put(component, src);
        return component;
    }

    private static Id addMuting(PEPermissionResolver.Resolved r, Integer n, Id groupId) {
        Id muting = fakeSetId(n);
        r.mutingParents.add(muting);
        if (!r.mutingSetsByGroup.containsKey(groupId)) {
            r.mutingSetsByGroup.put(groupId, new Set<Id>());
        }
        r.mutingSetsByGroup.get(groupId).add(muting);

        PEDto.Source src = new PEDto.Source(muting, 'Muting ' + n, 'muting');
        src.groupId = groupId;
        r.sourcesById.put(muting, src);
        return muting;
    }

    private static Map<Id, Boolean> granted(Id parentId) {
        return new Map<Id, Boolean>{ parentId => true };
    }

    private static Map<Id, Boolean> mutes(Id mutingId) {
        return new Map<Id, Boolean>{ mutingId => true };
    }

    private static Map<Id, Boolean> noMutes() {
        return new Map<Id, Boolean>();
    }

    private static void assertHasIt(PEDto.Grant g, String why) {
        Assert.isTrue(g.granted, why);
        Assert.isFalse(g.muted, 'nothing was effectively muted: ' + why);
    }

    private static void assertDeniedByMuting(PEDto.Grant g, String why) {
        Assert.isFalse(g.granted, why);
        Assert.isTrue(g.muted, 'the denial must be attributed to muting, not absence: ' + why);
    }

    /**
     * Synthetic PermissionSet Ids. applyGrant only uses them as map keys.
     *
     * @param n Numeric suffix used solely to keep generated Ids distinct.
     * @return Synthetic PermissionSet Id.
     */
    private static Id fakeSetId(Integer n) {
        return Id.valueOf('0PS000000000' + String.valueOf(n).leftPad(3, '0'));
    }

    /**
     * Synthetic PermissionSetGroup Ids, used only as map keys.
     *
     * @param n Numeric suffix used solely to keep generated Ids distinct.
     * @return Synthetic PermissionSetGroup Id.
     */
    private static Id fakeGroupId(Integer n) {
        return Id.valueOf('0PG000000000' + String.valueOf(n).leftPad(3, '0'));
    }
}
