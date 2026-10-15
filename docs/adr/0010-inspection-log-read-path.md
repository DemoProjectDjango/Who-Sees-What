# ADR-0010 — Make the inspection log readable, and do not log the read

**Status:** Accepted
**Date:** 2026-10

---

## Context

`PE_Inspection_Log__c` has existed since 0.1. Every inspection wrote a row, and nothing in the
product ever showed one.

That is the wrong shape for the delegation argument. The trail is what makes handing inspection
rights to a non-admin defensible — and a trail nobody can read defends nothing. A subscriber could
build a report over the object, but "you can build a report" is not the same claim as "the product
shows you who looked at whom".

Making it readable raises a second question immediately: is reading the log itself an inspection?

## Decision

Ship an in-product viewer, `PEInspectionLogService` and `peInspectionLog`, and:

1. **Read-only by construction.** No update or delete path exists in the class. The packaged
   permission set grants Read and Create, never Edit or Delete.
2. **Gate the read, do not log it.** `getRecentInspections` calls `assertAuthorised()` and writes no
   row.
3. **Not cacheable.** An audit panel exists to reflect what just happened; a client-cached page would
   show an administrator a trail predating their own last inspection.
4. **Null means unavailable, not zero.** A count that fails renders as unavailable. On an audit panel
   a fabricated zero reads as "nothing happened".

## Rationale for not logging the read

An audit trail that records its own observation grows every time someone looks at it. Within a week
the trail is mostly reads of itself, and the signal — who inspected whom — is buried in noise.

The counter-argument is real: in some compliance regimes, access to an audit log is itself auditable.
The position here is that the Salesforce platform already records this. Field History, Event
Monitoring and the setup audit trail are the subscriber's instruments for watching their own
administrators. Duplicating that inside the product buys noise, not assurance.

If a subscriber needs it, they have the platform tools. The product will not manufacture a second,
worse version of them.

## Consequences

**Good**

- The delegation USP is now demonstrable rather than asserted. This was the highest-leverage,
  lowest-effort item on the roadmap for exactly that reason.
- The audit-defensibility claim in listing copy becomes supportable — paired with the muting matrix
  passing.
- The read path is trivially defensible at security review: no write, no elevation, `WITH USER_MODE`.

**Bad**

- One more place the log object's shape matters, so a schema change now has two consumers.
- A deliberate asymmetry — some gated methods log, some do not — that a future contributor will read
  as an oversight unless it is written down. It is written down here, in
  [../AUDIT-TRAIL.md](../AUDIT-TRAIL.md) §3, and in a comment on the method itself.
- The viewer makes retention visible, which usually prompts a subscriber question the product has no
  built-in answer to. See [../AUDIT-TRAIL.md](../AUDIT-TRAIL.md) §7.

## See also

- [0002-custom-permission-gate-and-audit.md](0002-custom-permission-gate-and-audit.md)
- [0012-namespace-safe-dynamic-soql.md](0012-namespace-safe-dynamic-soql.md)
