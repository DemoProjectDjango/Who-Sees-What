# ADR-0003: Subtract muting permission sets rather than unioning grants

- **Status:** Accepted
- **Date:** Resolver design

## Context

The obvious implementation of permission resolution is a union:

```
effective = profile ∪ permSet₁ ∪ … ∪ groupComponents
```

This is wrong in any org using permission set groups with muting permission sets. A muting set exists
specifically to remove a permission its sibling component sets grant. A union-only resolver reports
that permission as held. The user does not hold it.

For a convenience tool, that is a bug. For a tool that claims audit defensibility, it is
disqualifying — and it fails *silently*, with a confident green tick.

Muting subtraction is the most common correctness failure in this product category, which makes
getting it right the strongest available differentiator.

## Decision

`PEPermissionResolver` maintains two disjoint sets:

- `effectiveParents` — permission set IDs that grant.
- `mutingParents` — permission set IDs where `PermissionSet.Type = 'Muting'`, which subtract.

Muting sets are **removed from** `effectiveParents` when detected. They never contribute grants.

`applyGrant` produces a `PEDto.Grant` carrying **two** flags rather than one effective boolean:

| `granted` | `muted` | Meaning |
| --- | --- | --- |
| true | false | Held |
| true | **true** | Granted then muted — **not** held |
| false | false | Not held |

Reporting a muted permission as simply `granted = false` would be the correct effective answer but a
poor diagnostic one. The administrator needs to see that a grant exists *and* that something cancels
it, or they will add a grant that is already there.

Additionally, groups with `Status != 'Updated'` are included **and flagged** in `outdatedGroups`. An
unflagged stale answer is worse than a flagged uncertain one.

## Consequences

**Positive**

- Answers are correct in orgs that use muting, which are exactly the complex orgs this product
  targets.
- The amber "granted then muted" state is genuinely diagnostic, not just accurate.
- Supports the audit-defensibility claim in the product positioning.

**Negative**

- Additional queries against `PermissionSetGroupComponent` and `PermissionSet.Type`.
- More resolution states for the UI to render and for users to learn — mitigated by the persistent
  legend and plain-language labels.
- Correctness now depends on a scenario matrix that must be maintained and must pass before any
  release claims defensibility. See [../TESTING.md](../TESTING.md) §3.

## Obligation

Until the full matrix passes, the product must not claim audit defensibility in marketing or listing
copy. Correctness claims that are not verified are worse than no claim.
