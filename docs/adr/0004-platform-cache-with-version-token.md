# ADR-0004: Platform Cache with a single version token and graceful fallback

- **Status:** Accepted
- **Date:** Performance work

## Context

Resolving one user's effective permissions costs several SOQL queries across `PermissionSet`,
`PermissionSetAssignment`, `PermissionSetGroup` and `PermissionSetGroupComponent`. Administrators
commonly inspect the same handful of users repeatedly, and org-shaped data (stats, licenses) changes
rarely.

Two constraints shape the answer: Platform Cache allocation is a **subscriber** decision the package
cannot make, and cached permission data going stale produces wrong answers rather than slow ones.

## Decision

`PECacheManager` wraps Platform Cache with three properties:

1. **Two partitions.** Org partition for data shared across administrators (resolved graphs, org
   stats, licenses); session partition for per-user working state. The package ships a
   `PermissionExplorer` partition definition with a 2 MB org / 1 MB session recommendation.

2. **A single version token.** One org-scoped token participates in every cache key. `refreshCache()`
   bumps it, invalidating the entire product cache in one operation instead of enumerating and
   deleting keys — which Platform Cache makes awkward and slow.

3. **Graceful fallback.** When the partition is unavailable (not allocated in the subscriber org),
   reads and writes degrade to a request-scoped `Map`. The product works correctly; it is only
   slower. Cache is an optimisation, never a source of truth.

Partition availability is resolved lazily and memoised using explicit `*Resolved` booleans rather
than static property getters — a property getter that reads its own property recurses infinitely,
which this codebase encountered once already.

Cached object shapes are versioned by `CACHE_PREFIX` (currently `resolvedV4`), which **must** be
bumped whenever the shape of a cached object changes.

## Consequences

**Positive**

- Repeat inspections are fast.
- Installation cannot fail because a subscriber has not allocated cache.
- One-operation invalidation gives the UI a refresh control that genuinely works.

**Negative**

- Cached results can be up to one TTL stale. `forceRefresh` and the UI refresh control exist for
  this.
- **`CACHE_PREFIX` discipline is a standing hazard.** A changed shape with an unchanged prefix
  deserialises without error and silently loses fields — which reads as "this user has no muting
  sets". This is the single most dangerous known failure mode in the codebase.
- Cache keys must be sanitised: Platform Cache keys are alphanumeric only.
