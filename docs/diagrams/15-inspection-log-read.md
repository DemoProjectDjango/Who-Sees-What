# 15 — Sequence: Inspection Log Read

How the audit trail is read back, and why this is the one gated path that writes nothing.

```mermaid
sequenceDiagram
    autonumber
    participant U as Administrator
    participant LWC as peInspectionLog
    participant C as PermissionExplorerController
    participant G as PEAccessGate
    participant S as PEInspectionLogService
    participant SC as Schema.SObjectType
    participant DB as Salesforce Platform

    U->>LWC: open Home, or filter by inspector / subject
    LWC->>C: getRecentInspections(inspectorId, subjectId, rowLimit)

    C->>G: assertAuthorised()
    Note over C,G: assertAuthorisedAndLog is NOT used.<br/>A trail that records its own observation<br/>is noise, not evidence.

    C->>S: getRecent(inspectorId, subjectId, rowLimit)

    S->>SC: getName() for object, fields, relationships
    Note over S,SC: Dynamic SOQL is not reliably<br/>namespace-qualified. Literals would<br/>work here and fail for every subscriber.
    SC-->>S: twinforce__-qualified names

    S->>S: compose query text, bind predicates and limit
    S->>DB: Database.queryWithBinds(..., AccessLevel.USER_MODE)

    alt running user cannot read the object
        DB-->>S: access error
        S-->>C: LogPage { readable = false, notice }
    else readable
        DB-->>S: rows
        S->>DB: COUNT() total, COUNT() last 7 days
        Note over S: A count that fails leaves null.<br/>Null renders as "unavailable".<br/>Never as zero.
        S->>S: zero-fill the activity series, rank top inspectors
        S-->>C: LogPage { rows, counts, activity, topInspectors }
    end

    C-->>LWC: LogPage
    LWC-->>U: trail — and no new row written
```

## Three design points

**No row is written.** This is the only gated method in the product that deliberately does not log.
The asymmetry is intentional and will otherwise read as an oversight — see
[../adr/0010-inspection-log-read-path.md](../adr/0010-inspection-log-read-path.md).

**Names come from describe.** The class originally used four literal static SOQL variants. They
compiled in the dev org and would have failed for every subscriber, where the object is
`twinforce__PE_Inspection_Log__c`. Fixed in `0.6.0-2`; recorded as
[../adr/0012-namespace-safe-dynamic-soql.md](../adr/0012-namespace-safe-dynamic-soql.md).

**There is no write path in the class at all.** No update, no delete — not disabled, not present.
Combined with the packaged permission set withholding Edit and Delete, an inspector can read history
without being able to rewrite it. That is the whole reason the object is worth keeping.

## See also

- [../AUDIT-TRAIL.md](../AUDIT-TRAIL.md)
- [13-security-trust-boundaries.md](13-security-trust-boundaries.md)
