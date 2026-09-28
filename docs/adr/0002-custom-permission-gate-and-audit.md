# ADR-0002: Custom-permission gate coupled to an append-only audit trail

- **Status:** Accepted
- **Date:** Project inception

## Context

The product's entire premise is that non-Setup users can answer access questions. That means people
without Setup access will read other users' permission metadata — which is precisely the capability a
security reviewer, and a subscriber's own security team, will question.

"It's read-only" is a necessary answer but not a sufficient one. The remaining questions are *who*
may do it, and *can anyone tell that they did*.

## Decision

Two controls, deliberately coupled so neither can be used without the other.

1. **Explicit gate.** A packaged custom permission, `Use_Permission_Explorer`, checked in Apex via
   `FeatureManagement.checkPermission`. Enforced in `PEAccessGate`, called as the first statement of
   every `@AuraEnabled` method. Never enforced in the UI alone.

2. **Append-only audit.** Every inspection writes a `PE_Inspection_Log__c` row: inspector, subject,
   action, detail, timestamp. The packaged permission set grants **Create and Read only** — Edit,
   Delete, View All and Modify All are withheld.

They are coupled through `PEAccessGate.assertAuthorisedAndLog(...)`, the single entry point every
controller method uses. An inspection cannot occur without producing a log row, because the same call
does both.

The authorisation check is **deliberately uncached**. A decision held in a mutable static outlives
the context that produced it — `System.runAs` changes the user but not the static — and
`checkPermission` is cheap enough that the guarantee is worth more than the microseconds.

## Consequences

**Positive**

- Subscribers control exactly who inspects, using a native Salesforce mechanism they already
  understand.
- The trail is tamper-resistant: an inspector cannot edit or erase their own history.
- The coupling removes the most likely implementation error — remembering to gate but forgetting to
  log, or vice versa.
- Turns a product liability into a differentiator: native User Access Summary leaves no trace.

**Negative**

- One DML statement per request. Mitigated by buffering in `PEInspectionAuditLogger` and flushing
  once.
- `PE_Inspection_Log__c` grows unbounded. The package deliberately does not prune data it did not ask
  permission to delete; subscribers apply their own retention.
- The audit trail is currently write-only from the UI's perspective — a differentiator the user
  cannot see. A viewer is scheduled.
