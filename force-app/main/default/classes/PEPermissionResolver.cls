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
public with sharing class PEPermissionResolver {

    /* ---------------------------------------------------------------
     * Result type
     * --------------------------------------------------------------- */

    public class Resolved {
        /** Every non-muting PermissionSet Id that contributes grants. */
        public Set<Id> effectiveParents = new Set<Id>();
        /** Muting sets that apply, via an assigned group. */
        public Set<Id> mutingParents = new Set<Id>();
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

        public List<Id> parentList { get { return new List<Id>(effectiveParents); } }
    }

    /* ---------------------------------------------------------------
     * Entry point
     * --------------------------------------------------------------- */

    /**
     * Version suffix, not decoration. `Resolved` is serialised into the session
     * partition, so adding fields to it means already-cached instances are the
     * wrong shape. Bumping the prefix retires them instead of reading them.
     */
    private static final String CACHE_PREFIX = 'resolvedV3';

    /** Cached per session. Pass forceRefresh from the refresh button. */
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
     */
    private static void loadProfileAsPermissionSet(Resolved r, User u) {
        if (u.ProfileId == null) return;

        List<PermissionSet> profileSets = [
            SELECT Id, Label, ProfileId, Profile.Name
            FROM PermissionSet
            WHERE IsOwnedByProfile = true AND ProfileId = :u.ProfileId
            LIMIT 1
        ];
        if (profileSets.isEmpty()) return;

        PermissionSet ps = profileSets[0];
        r.profilePermSetId = ps.Id;
        r.effectiveParents.add(ps.Id);

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
     */
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
    private static void loadGroupComponents(Resolved r, Set<Id> groupIds) {
        if (groupIds.isEmpty()) return;

        for (List<Id> batch : PESoqlChunker.chunk(groupIds)) {
            for (PermissionSetGroupComponent c : [
                SELECT PermissionSetId, PermissionSet.Label, PermissionSet.Type,
                       PermissionSetGroupId, PermissionSetGroup.DeveloperName,
                       PermissionSetGroup.Status
                FROM PermissionSetGroupComponent
                WHERE PermissionSetGroupId IN :batch
            ]) {
                if (isMutingType(c.PermissionSet.Type)) {
                    r.mutingParents.add(c.PermissionSetId);

                    // A muting set has no standalone Setup page — it is only
                    // reachable from inside its group, so the group Id is the
                    // only link worth offering. Captured here because this join
                    // is the one place that association is visible.
                    PEDto.Source mSrc = new PEDto.Source(
                        c.PermissionSetId, c.PermissionSet.Label, 'muting'
                    );
                    mSrc.groupId  = c.PermissionSetGroupId;
                    mSrc.linkId   = c.PermissionSetGroupId;
                    mSrc.linkable = c.PermissionSetGroupId != null;
                    mSrc.groupLabel = c.PermissionSetGroup != null
                        ? c.PermissionSetGroup.DeveloperName : null;
                    r.sourcesById.put(c.PermissionSetId, mSrc);
                    continue;
                }

                // Count once per distinct set, not once per group membership —
                // a set in two assigned groups is still one set.
                if (!r.sourcesById.containsKey(c.PermissionSetId)) {
                    r.groupDerivedCount++;
                }

                r.effectiveParents.add(c.PermissionSetId);

                PEDto.Source src = new PEDto.Source(
                    c.PermissionSetId, c.PermissionSet.Label, 'group'
                );
                src.groupLabel = c.PermissionSetGroup != null
                    ? c.PermissionSetGroup.DeveloperName : null;
                src.isOutdatedGroup = c.PermissionSetGroup != null
                    && c.PermissionSetGroup.Status != 'Updated';

                // The chip names the group, so the link should open the group,
                // not the component set buried inside it.
                src.groupId  = c.PermissionSetGroupId;
                src.linkId   = c.PermissionSetGroupId;
                src.linkable = c.PermissionSetGroupId != null
                    && String.isNotBlank(c.PermissionSet.Label);
                r.sourcesById.put(c.PermissionSetId, src);
            }
        }
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
    private static void loadMutingSets(Resolved r, Set<Id> groupIds) {
        if (groupIds.isEmpty() || r.mutingParents.isEmpty()) return;

        for (List<Id> batch : PESoqlChunker.chunk(r.mutingParents)) {
            for (PermissionSet ps : [
                SELECT Id, Label
                FROM PermissionSet
                WHERE Id IN :batch
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
     * OR the permission across effective parents, then subtract muting.
     *
     * `grantedByParent` maps parentId → whether that parent grants the
     * permission. `mutedByParent` is the same over muting sets. Callers build
     * both from ObjectPermissions / FieldPermissions rows they already have,
     * so this method does no querying — it is pure logic, and cheap to test.
     */
    public static PEDto.Grant applyGrant(
        String permName,
        String permLabel,
        Resolved r,
        Map<Id, Boolean> grantedByParent,
        Map<Id, Boolean> mutedByParent
    ) {
        PEDto.Grant g = new PEDto.Grant(permName, permLabel);

        for (Id parentId : r.effectiveParents) {
            if (grantedByParent.get(parentId) == true) {
                g.granted = true;
                PEDto.Source src = r.sourcesById.get(parentId);
                if (src != null) g.sources.add(src);
            }
        }

        if (g.granted && mutedByParent != null) {
            for (Id mutingId : r.mutingParents) {
                if (mutedByParent.get(mutingId) == true) {
                    g.granted = false;
                    g.muted = true;
                    PEDto.Source src = r.sourcesById.get(mutingId);
                    if (src != null) g.sources.add(src);
                    break;
                }
            }
        }

        return g;
    }
}
