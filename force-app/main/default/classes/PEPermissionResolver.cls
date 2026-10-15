/**
 * Resolves a user's effective permission-set parents, with muting applied.
 *
 * Everything downstream is wrong if this is wrong, so it runs once per user
 * selection — never per modal open — and the result is cached in the session
 * partition. On an org with 200 permission sets, recomputing per click is
 * exactly where CPU time disappears.
 *
 * Salesforce permissions are additive across all sources, with muting as the
 * only subtractive mechanism. A resolver that simply ORs everything together
 * will confidently display incorrect permissions, which is worse than
 * displaying nothing.
 *
 * SPIKE DEPENDENCY (Phase 0, item 3): the exact shape of muting-set
 * association to a permission set group is confirmed in `loadMutingSets()`.
 * That method is deliberately the only place that knowledge lives, so the
 * spike outcome changes one method rather than the class.
 */
// Total complexity reflects one multi-pass pipeline (assignments, groups,
// muting) that must run as a unit against a cached result; splitting the class
// would fragment the single source of truth for effective access.
@SuppressWarnings('PMD.CognitiveComplexity,PMD.CyclomaticComplexity')
public with sharing class PEPermissionResolver {

    /* ---------------------------------------------------------------
     * Cache
     * --------------------------------------------------------------- */

    /**
     * Version suffix, not decoration. `Resolved` is serialised into the session
     * partition, so adding fields to it means already-cached instances are the
     * wrong shape. Bumping the prefix retires them instead of reading them.
     */
    private static final String CACHE_PREFIX = 'resolvedV4';

    /* ---------------------------------------------------------------
     * Result type
     * --------------------------------------------------------------- */

    /** Resolved permission context reused by all columns after an admin selects a user. */
    public class Resolved {
        /** Every non-muting PermissionSet Id that contributes grants. */
        public Set<Id> effectiveParents = new Set<Id>();
        /** Muting sets that apply, via an assigned group. */
        public Set<Id> mutingParents = new Set<Id>();

        /**
         * Permission sets assigned to the user directly, plus the profile set.
         *
         * Muting is a property of a permission set group: it suppresses what
         * that group's own components grant. It never reaches a profile or a
         * direct assignment. Holding those Ids here is what lets `applyGrant`
         * refuse to subtract from a source no group can touch.
         */
        public Set<Id> immuneParents = new Set<Id>();

        /**
         * groupId -> the muting sets that group contains.
         *
         * Without this, every muting set in the org looked global and a group's
         * mute silently revoked grants that came from somewhere else entirely.
         */
        public Map<Id, Set<Id>> mutingSetsByGroup = new Map<Id, Set<Id>>();

        /**
         * component permission set Id -> the assigned groups it arrived through.
         *
         * A set can sit in two groups. It is only muted when *every* group it
         * came through mutes the permission; one unmuted group still grants it.
         */
        public Map<Id, Set<Id>> groupsByComponent = new Map<Id, Set<Id>>();
        /** parentId → display source, for chip rendering without re-querying. */
        public Map<Id, PEDto.Source> sourcesById = new Map<Id, PEDto.Source>();
        /** Groups whose Status is not 'Updated' — their effective perms are not settled. */
        public List<String> outdatedGroups = new List<String>();
        public Id profilePermSetId;
        public Integer permSetCount = 0;
        public Integer unreadableCount = 0;
        public Integer permSetGroupCount = 0;
        public Datetime resolvedAt;

        /**
         * Directly assigned permission sets, in the same pass that produced
         * `permSetCount`. Held here rather than re-queried by the drill-down
         * modal, because two queries with drifting predicates is exactly how a
         * header that says 42 ends up above a list of 43.
         */
        public List<PEDto.PermSetRow> directPermSets = new List<PEDto.PermSetRow>();
        /** Assigned permission set groups, deduplicated. */
        public List<PEDto.PermSetGroupRow> assignedGroups = new List<PEDto.PermSetGroupRow>();
        /** Sets that contribute only because a group containing them is assigned. */
        public Integer groupDerivedCount = 0;

        /** Effective parent Ids as a list for SOQL bind contexts that cannot use the backing set directly. */
        public List<Id> parentList { get { return new List<Id>(effectiveParents); } }
    }

    /* ---------------------------------------------------------------
     * Entry point
     * --------------------------------------------------------------- */

    /**
     * Cached per session. Pass forceRefresh from the refresh button.
     *
     * @param userId User whose effective permissions are being inspected.
     * @param forceRefresh True when the admin explicitly refreshes and cached resolver data should be ignored.
     * @return Effective permission context for the selected user.
     */
    // forceRefresh is the existing refresh contract (true rebuilds the cache);
    // replacing it with a wrapper type would change every resolveUser call site.
    @SuppressWarnings('PMD.AvoidBooleanMethodParameters')
    public static Resolved resolve(Id userId, Boolean forceRefresh) {
        String key = CACHE_PREFIX + String.valueOf(userId).right(15);

        if (!forceRefresh) {
            Object cached = PECacheManager.sessionGet(key);
            if (cached instanceof Resolved) {
                return (Resolved) cached;
            }
        }

        Resolved r = compute(userId);
        PECacheManager.sessionPut(key, r, 900);   // 15 minutes
        return r;
    }

    /**
     * Resolves the selected user's effective permissions using the cached path used by normal UI navigation.
     *
     * @param userId User whose effective permissions are being inspected.
     * @return Effective permission context for the selected user.
     */
    public static Resolved resolve(Id userId) {
        return resolve(userId, false);
    }

    /* ---------------------------------------------------------------
     * Computation
     * --------------------------------------------------------------- */

    private static Resolved compute(Id userId) {
        Resolved r = new Resolved();
        r.resolvedAt = System.now();

        User u = PEAccessGate.assertInspectable(userId);

        loadProfileAsPermissionSet(r, u);
        Set<Id> assignedGroupIds = loadAssignments(r, userId);
        loadGroupComponents(r, assignedGroupIds);
        loadMutingSets(r, assignedGroupIds);

        return r;
    }

    /**
     * Since profiles became permission-set-backed, the profile is just another
     * parent Id. This is the key that makes unioning tractable in SOQL.
     *
     * @param r Resolver result being populated for the selected user.
     * @param u Active user record whose profile permission set contributes baseline access.
     */
    private static void loadProfileAsPermissionSet(Resolved r, User u) {
        if (u.ProfileId == null) {
            return;
        }

        List<PermissionSet> profileSets = [
            SELECT Id, Label, ProfileId, Profile.Name
            FROM PermissionSet
            WHERE IsOwnedByProfile = true AND ProfileId = :u.ProfileId
            WITH USER_MODE
            LIMIT 1
            
        ];
        if (profileSets.isEmpty()) {
            return;
        }

        PermissionSet ps = profileSets[0];
        r.profilePermSetId = ps.Id;
        r.effectiveParents.add(ps.Id);
        r.immuneParents.add(ps.Id);

        String label = ps.Profile != null && ps.Profile.Name != null ? ps.Profile.Name : ps.Label;
        PEDto.Source src = new PEDto.Source(ps.Id, label, 'profile');

        // parentId stays the 0PS Id — that is what ObjectPermissions joins on.
        // linkId is the 00e Id, which is what Setup addresses.
        src.linkId   = ps.ProfileId;
        src.linkable = ps.ProfileId != null;
        r.sourcesById.put(ps.Id, src);
    }

    /**
     * Direct assignments and group-derived assignments arrive in the same
     * object. PermissionSetGroupId being non-null is what distinguishes them,
     * and it is what lets us label the chip "via <group>" instead of showing a
     * permission set the admin never assigned directly.
     *
     * @param r Resolver result being populated for the selected user.
     * @param userId User whose direct permission set assignments are being inspected.
     * @return Permission set group Ids assigned to the user so component and muting sets can be expanded.
     */
    // Single pass over assignments with group bookkeeping; extracting branches
    // would split the count/list consistency contract this method guarantees.
    @SuppressWarnings('PMD.CognitiveComplexity,PMD.CyclomaticComplexity')
    private static Set<Id> loadAssignments(Resolved r, Id userId) {
        // Map rather than Set: the drill-down needs the group's label and
        // status, not just its Id, and one group can back several assignments.
        Map<Id, PEDto.PermSetGroupRow> groupsById = new Map<Id, PEDto.PermSetGroupRow>();

        for (PermissionSetAssignment psa : [
            SELECT PermissionSetId, PermissionSet.Label, PermissionSet.Name,
                   PermissionSet.IsOwnedByProfile, PermissionSet.Type,
                   PermissionSetGroupId, PermissionSetGroup.DeveloperName,
                   PermissionSetGroup.MasterLabel, PermissionSetGroup.Status
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
            WITH USER_MODE
        ]) {
            if (psa.PermissionSet.IsOwnedByProfile == true) {
                continue;   // already handled, and would double-count
            }

            if (psa.PermissionSetGroupId != null) {
                if (!groupsById.containsKey(psa.PermissionSetGroupId)) {
                    groupsById.put(
                        psa.PermissionSetGroupId,
                        buildGroupRow(psa.PermissionSetGroupId, psa.PermissionSetGroup)
                    );
                }

                if (psa.PermissionSetGroup != null
                        && psa.PermissionSetGroup.Status != 'Updated'
                        && !r.outdatedGroups.contains(psa.PermissionSetGroup.DeveloperName)) {
                    r.outdatedGroups.add(psa.PermissionSetGroup.DeveloperName);
                }
                continue;
            }
            r.effectiveParents.add(psa.PermissionSetId);

            // Directly assigned: no group owns this grant, so no group's muting
            // set can take it away.
            r.immuneParents.add(psa.PermissionSetId);

            // Some assignments come back with a null parent — protected
            // permission sets from managed packages the running user cannot
            // introspect. A blank source chip is worse than an honest one, so
            // the gap is named and counted rather than rendered empty.
            Boolean readable = String.isNotBlank(psa.PermissionSet.Label);
            PEDto.Source src = new PEDto.Source(
                psa.PermissionSetId,
                readable ? psa.PermissionSet.Label : 'Protected permission set',
                'permset'
            );
            // Same rule the perm-set modal already uses: an unreadable managed
            // set has no Setup page the admin can open.
            src.linkable = readable;
            r.sourcesById.put(psa.PermissionSetId, src);
            if (!readable) {
                r.unreadableCount++;
            }
            r.permSetCount++;

            // Same branch, same predicate, same increment — so the list and the
            // count cannot drift apart.
            PEDto.PermSetRow row = new PEDto.PermSetRow();
            row.permSetId  = psa.PermissionSetId;
            row.label      = readable ? psa.PermissionSet.Label : 'Protected permission set';
            row.apiName    = psa.PermissionSet.Name;
            row.setType    = psa.PermissionSet.Type;
            row.isReadable = readable;
            r.directPermSets.add(row);
        }

        r.assignedGroups = groupsById.values();
        r.permSetGroupCount = groupsById.size();
        return groupsById.keySet();
    }

    private static PEDto.PermSetGroupRow buildGroupRow(Id groupId, PermissionSetGroup g) {
        PEDto.PermSetGroupRow row = new PEDto.PermSetGroupRow();
        row.groupId       = groupId;
        row.developerName = g != null ? g.DeveloperName : null;
        row.masterLabel   = g != null ? g.MasterLabel : null;
        row.status        = g != null ? g.Status : null;
        row.isOutdated    = g != null && g.Status != null && g.Status != 'Updated';
        return row;
    }

    /**
     * Expand each assigned group into its component permission sets. The group
     * itself carries no ObjectPermissions rows — the components do.
     */
    /**
     * Expands assigned permission set groups into component permission sets so effective access includes group grants.
     *
     * @param r Resolver result being populated with group-derived grants and muting sources.
     * @param groupIds Permission set group Ids assigned to the selected user.
     */
    // Chunked SOQL over assigned groups is the deliberate batching strategy;
    // the per-chunk query keeps governor limits bounded and must stay in the loop.
    @SuppressWarnings('PMD.CognitiveComplexity,PMD.OperationWithLimitsInLoop')
    private static void loadGroupComponents(Resolved r, Set<Id> groupIds) {
        if (groupIds.isEmpty()) {
            return;
        }

        for (List<Id> batch : PESoqlChunker.chunk(groupIds)) {
            for (PermissionSetGroupComponent c : [
                SELECT PermissionSetId, PermissionSet.Label, PermissionSet.Type,
                       PermissionSetGroupId, PermissionSetGroup.DeveloperName,
                       PermissionSetGroup.Status
                FROM PermissionSetGroupComponent
                WHERE PermissionSetGroupId IN :batch
                WITH USER_MODE
            ]) {
                if (isMutingType(c.PermissionSet.Type)) {
                    recordMutingComponent(r, c);
                } else {
                    recordGrantingComponent(r, c);
                }
            }
        }
    }

    /**
     * Files a muting set found inside an assigned group.
     *
     * The group association this join exposes is visible nowhere else, and
     * dropping it is what once made muting look org-wide: a mute in one group
     * silently revoked grants that came from somewhere else entirely.
     *
     * @param r Resolved context being built, mutated in place.
     * @param c Component row joining a muting set to its group.
     */
    private static void recordMutingComponent(Resolved r, PermissionSetGroupComponent c) {
        r.mutingParents.add(c.PermissionSetId);

        if (c.PermissionSetGroupId != null) {
            if (!r.mutingSetsByGroup.containsKey(c.PermissionSetGroupId)) {
                r.mutingSetsByGroup.put(c.PermissionSetGroupId, new Set<Id>());
            }
            r.mutingSetsByGroup.get(c.PermissionSetGroupId).add(c.PermissionSetId);
        }

        // A muting set has no standalone Setup page - it is only reachable from
        // inside its group, so the group Id is the only link worth offering.
        PEDto.Source mSrc = new PEDto.Source(
            c.PermissionSetId, c.PermissionSet.Label, 'muting'
        );
        mSrc.groupId    = c.PermissionSetGroupId;
        mSrc.linkId     = c.PermissionSetGroupId;
        mSrc.linkable   = c.PermissionSetGroupId != null;
        mSrc.groupLabel = c.PermissionSetGroup != null
            ? c.PermissionSetGroup.DeveloperName : null;
        r.sourcesById.put(c.PermissionSetId, mSrc);
    }

    /**
     * Files a granting component set found inside an assigned group.
     *
     * @param r Resolved context being built, mutated in place.
     * @param c Component row joining a permission set to its group.
     */
    private static void recordGrantingComponent(Resolved r, PermissionSetGroupComponent c) {
        // Count once per distinct set, not once per group membership - a set in
        // two assigned groups is still one set.
        if (!r.sourcesById.containsKey(c.PermissionSetId)) {
            r.groupDerivedCount++;
        }

        r.effectiveParents.add(c.PermissionSetId);

        // Which groups this component arrived through. Accumulated, not
        // overwritten: a set in two groups survives a mute in one.
        if (c.PermissionSetGroupId != null) {
            if (!r.groupsByComponent.containsKey(c.PermissionSetId)) {
                r.groupsByComponent.put(c.PermissionSetId, new Set<Id>());
            }
            r.groupsByComponent.get(c.PermissionSetId).add(c.PermissionSetGroupId);
        }

        PEDto.Source src = new PEDto.Source(
            c.PermissionSetId, c.PermissionSet.Label, 'group'
        );
        src.groupLabel = c.PermissionSetGroup != null
            ? c.PermissionSetGroup.DeveloperName : null;
        src.isOutdatedGroup = c.PermissionSetGroup != null
            && c.PermissionSetGroup.Status != 'Updated';

        // The chip names the group, so the link should open the group, not the
        // component set buried inside it.
        src.groupId  = c.PermissionSetGroupId;
        src.linkId   = c.PermissionSetGroupId;
        src.linkable = c.PermissionSetGroupId != null
            && String.isNotBlank(c.PermissionSet.Label);
        r.sourcesById.put(c.PermissionSetId, src);
    }

    /**
     * PHASE 0 SPIKE SURFACE.
     *
     * Muting sets are collected in loadGroupComponents by type, and this method
     * exists to catch any that the component join does not surface. Verify
     * against an org with a group + muting set that the totals here match what
     * the standard Setup UI reports, then delete or complete this method
     * according to the finding.
     */
    /**
     * Completes muting-set source labels when the component pass found applicable muting parents.
     *
     * @param r Resolver result whose muting source labels may need completion.
     * @param groupIds Permission set group Ids assigned to the selected user.
     */
    // Same chunked batching as loadGroupComponents; the label-completion loop
    // queries within the call to keep muting source fills under governor limits.
    @SuppressWarnings('PMD.OperationWithLimitsInLoop')
    private static void loadMutingSets(Resolved r, Set<Id> groupIds) {
        if (groupIds.isEmpty() || r.mutingParents.isEmpty()) {
            return;
        }

        for (List<Id> batch : PESoqlChunker.chunk(r.mutingParents)) {
            for (PermissionSet ps : [
                SELECT Id, Label
                FROM PermissionSet
                WHERE Id IN :batch
                WITH USER_MODE
            ]) {
                // Fill in a label only. Never replace the source wholesale —
                // loadGroupComponents already attached the group Id, which is
                // the only thing that makes a muting chip linkable, and this
                // query cannot see that association.
                PEDto.Source existing = r.sourcesById.get(ps.Id);
                if (existing == null) {
                    PEDto.Source orphan = new PEDto.Source(ps.Id, ps.Label, 'muting');
                    orphan.linkId   = null;
                    orphan.linkable = false;
                    r.sourcesById.put(ps.Id, orphan);
                } else if (String.isBlank(existing.label)) {
                    existing.label = ps.Label;
                }
            }
        }
    }

    private static Boolean isMutingType(String type) {
            return type != null && type.equalsIgnoreCase(PEConstants.MUTING_TYPE);
    }

    /* ---------------------------------------------------------------
     * Applying the result
     * --------------------------------------------------------------- */

    /**
     * OR the permission across effective parents, then subtract muting that
     * actually reaches the parent which granted it.
     *
     * `grantedByParent` maps parentId -> whether that parent grants the
     * permission. `mutedByParent` is the same over muting sets. Callers build
     * both from ObjectPermissions / FieldPermissions rows they already have,
     * so this method does no querying - it is pure logic, and cheap to test.
     *
     * Muting is scoped to its own permission set group. A muting set suppresses
     * what the components of *that* group grant; it cannot touch a profile, a
     * direct assignment, or a component of a different group. Subtracting any
     * mute from any grant - which is what this did before - reports users as
     * lacking access they actually hold, the one direction an access audit must
     * never get wrong.
     *
     * Back-compatible on purpose: a muting set with no known group (an orphan,
     * or a synthetic fixture) still applies globally, because an unexplained
     * mute is safer treated as real than discarded.
     *
     * @param permName Salesforce permission API name being evaluated.
     * @param permLabel Admin-facing label for the permission result.
     * @param r Effective permission context for the selected user.
     * @param grantedByParent Permission grant flags keyed by effective parent Id.
     * @param mutedByParent Permission mute flags keyed by muting permission set Id.
     * @return Grant row that explains whether the permission applies and which sources caused the result.
     */
    // applyGrant is the single tested decision point: OR grants, subtract muting.
    // The 5 parameters mirror the contract every caller already passes, and the
    // nested source lookups are the muting flow itself, not accidental nesting.
    @SuppressWarnings('PMD.ExcessiveParameterList,PMD.CognitiveComplexity,PMD.AvoidDeeplyNestedIfStmts')
    public static PEDto.Grant applyGrant(
        String permName,
        String permLabel,
        Resolved r,
        Map<Id, Boolean> grantedByParent,
        Map<Id, Boolean> mutedByParent
    ) {
        PEDto.Grant g = new PEDto.Grant(permName, permLabel);

        List<Id> grantingParents = new List<Id>();
        for (Id parentId : r.effectiveParents) {
            if (grantedByParent != null && grantedByParent.get(parentId) == true) {
                grantingParents.add(parentId);
            }
        }

        // Nothing granted it, so there is nothing for muting to take away.
        // Flagging `muted` here would invent a revocation that never happened.
        if (grantingParents.isEmpty()) {
            return g;
        }

        MuteScope scope = buildMuteScope(r, mutedByParent);

        List<Id> survivors = new List<Id>();
        if (!scope.hasGlobalMute) {
            for (Id parentId : grantingParents) {
                if (survivesMuting(r, parentId, scope.mutingGroupIds)) {
                    survivors.add(parentId);
                }
            }
        }

        if (!survivors.isEmpty()) {
            g.granted = true;
            addSources(g, r, survivors);
            return g;
        }

        // Granted somewhere, and every granting source was reachable by a mute.
        // Both halves are shown: a revoke decision needs the grant and the mute.
        g.granted = false;
        g.muted   = true;
        addSources(g, r, grantingParents);
        addSources(g, r, scope.responsibleMutingSets);
        return g;
    }

    /** Which muting sets fired for this permission, and how far each one reaches. */
    private class MuteScope {
        /** Muting sets with no known group - treated as applying everywhere. */
        Boolean hasGlobalMute = false;
        /** Groups whose muting sets suppress this permission. */
        Set<Id> mutingGroupIds = new Set<Id>();
        /** Muting sets that actually fired, for source chips. */
        List<Id> responsibleMutingSets = new List<Id>();
    }

    /**
     * Works out which groups mute this permission, from the muting sets that fired.
     *
     * @param r Effective permission context for the selected user.
     * @param mutedByParent Permission mute flags keyed by muting permission set Id.
     * @return The reach of every muting set that mutes this permission.
     */
    private static MuteScope buildMuteScope(Resolved r, Map<Id, Boolean> mutedByParent) {
        MuteScope scope = new MuteScope();
        if (mutedByParent == null || r.mutingParents == null || r.mutingParents.isEmpty()) {
            return scope;
        }

        Map<Id, Set<Id>> byGroup = r.mutingSetsByGroup == null
            ? new Map<Id, Set<Id>>()
            : r.mutingSetsByGroup;

        for (Id mutingId : r.mutingParents) {
            if (mutedByParent.get(mutingId) != true) {
                continue;
            }
            scope.responsibleMutingSets.add(mutingId);

            Boolean placed = false;
            for (Id groupId : byGroup.keySet()) {
                if (byGroup.get(groupId).contains(mutingId)) {
                    scope.mutingGroupIds.add(groupId);
                    placed = true;
                }
            }
            if (!placed) {
                scope.hasGlobalMute = true;
            }
        }
        return scope;
    }

    /**
     * Decides whether one granting parent keeps its grant once muting is applied.
     *
     * @param r Effective permission context for the selected user.
     * @param parentId Permission set Id that granted the permission.
     * @param mutingGroupIds Groups whose muting sets suppress this permission.
     * @return True when the grant stands, false when a group that owns it mutes it.
     */
    private static Boolean survivesMuting(Resolved r, Id parentId, Set<Id> mutingGroupIds) {
        // Profile and direct assignments: outside every group's reach.
        if (r.immuneParents != null && r.immuneParents.contains(parentId)) {
            return true;
        }

        Set<Id> owningGroups = r.groupsByComponent == null
            ? null
            : r.groupsByComponent.get(parentId);

        // No group association recorded. Pre-group callers and synthetic fixtures
        // land here, and so would a resolver pass that failed to capture the join -
        // in which case the mute is the safer answer than silently keeping access.
        if (owningGroups == null || owningGroups.isEmpty()) {
            return mutingGroupIds.isEmpty();
        }

        // One unmuted group is enough. The user is assigned to both.
        for (Id groupId : owningGroups) {
            if (!mutingGroupIds.contains(groupId)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Appends source chips for the given parents, skipping ones already credited.
     *
     * @param g Grant row being explained, mutated in place.
     * @param r Effective permission context holding the source chips.
     * @param parentIds Permission set Ids to credit on the grant.
     */
    private static void addSources(PEDto.Grant g, Resolved r, List<Id> parentIds) {
        Set<Id> already = new Set<Id>();
        for (PEDto.Source existing : g.sources) {
            already.add(existing.parentId);
        }
        for (Id parentId : parentIds) {
            if (already.contains(parentId)) {
                continue;
            }
            PEDto.Source src = r.sourcesById.get(parentId);
            if (src != null) {
                g.sources.add(src);
                already.add(parentId);
            }
        }
    }
}
