# ADR-0009 — Approximate record reach, and label the approximation

**Status:** Accepted
**Date:** 2026-10

---

## Context

The most common follow-up to *"what objects can this user see"* is *"and how much of the data?"*
Permission Explorer could not answer it, and the obvious answer was unavailable to us.

Three facts constrain any solution:

1. **Apex runs as the running user.** `with sharing` enforces the administrator's sharing, not the
   subject's. `SELECT COUNT() FROM Account` returns the administrator's view regardless of whose
   name is on screen.
2. **`UserRecordAccess` for another user requires View All Data.** That is exactly the Setup-level
   privilege the product exists to avoid handing out. Using it would make the install instructions
   contradict the product's premise.
3. **Role-hierarchy access writes no share rows.** Ownership and shares are countable. Hierarchy
   access is computed at query time, for the running user only, and leaves nothing to count.

So an exact answer is available in some cases and genuinely unavailable in others. The options were:
answer only the exact cases, answer everything and hide the uncertainty, or answer everything and
expose it.

## Decision

Answer everything, and **carry the basis with every figure**.

- Org-wide default public, or the user holds View All → sharing is bypassed, the org total **is** the
  answer. `isExact = true`.
- Otherwise → owned + shared, deduplicated, reported as a **floor**. `isExact = false`,
  `totalIsFloor = true`.
- The org total is always presented as a **denominator**, never as the subject's reach.
- `UserRecordAccess` is not queried for another user, in any code path.

The flags travel in the transport types and the UI is required to render them. A number without its
qualifier is not a smaller answer — it is a wrong one.

## Consequences

**Good**

- The product answers the question that gets asked, in every org, rather than only in orgs with
  permissive sharing.
- No elevation is requested anywhere. The delegation promise survives intact.
- Honest limits are a differentiator in a category where dashboards quietly round up. An auditor
  trusts a tool that says what it does not know.

**Bad**

- Two display states instead of one. Every component rendering a reach figure has to handle both,
  and a component that drops the flag silently produces a false answer. This is now an explicit
  review item.
- The floor **understates** access, which is the dangerous direction for an access review: it can
  pass something it should not. `PERecordAccessServiceTest` scenario 6 exists specifically to pin
  this behaviour, and the UI copy has to make the at-least framing unmissable.
- Restriction rules and scoping rules remain unmodelled. Even View All Data would not have given a
  complete answer, so this is not a cost of the decision — but it has to be said out loud rather
  than implied by silence.

## Alternatives rejected

| Alternative | Why not |
| --- | --- |
| Require View All Data and use `UserRecordAccess` | Self-defeating. Contradicts the product's entire premise. |
| Only answer where the answer is exact | Leaves private-OWD orgs — the ones that most need the feature — with a blank panel. |
| Report the floor as a total | A confident wrong number. The exact failure mode the product is positioned against. |
| Estimate the hierarchy contribution statistically | An invented number is worse than an acknowledged gap, and impossible to defend at review. |

## See also

- [../RECORD-VISIBILITY.md](../RECORD-VISIBILITY.md)
- [0001-read-only-no-callouts.md](0001-read-only-no-callouts.md)
