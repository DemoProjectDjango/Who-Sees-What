# 14 — Sequence: Record Reach

How Data Visibility decides a reach figure, and where the exact-versus-floor branch happens.

The branch is the point of the diagram. Everything else is plumbing.

```mermaid
sequenceDiagram
    autonumber
    participant U as Administrator
    participant LWC as dataVisibility
    participant C as PermissionExplorerController
    participant G as PEAccessGate
    participant R as PEPermissionResolver
    participant RA as PERecordAccessService
    participant DB as Salesforce Platform

    U->>LWC: pick user, pick object
    LWC->>C: getRecordReach(userId, objectApiName)
    C->>G: assertAuthorisedAndLog('VIEW_RECORD_REACH', userId, objectApiName)
    C->>G: assertInspectable(userId)
    C->>RA: getReach(userId, objectApiName)

    RA->>DB: EntityDefinition — internal / external sharing model
    RA->>R: resolve(userId) — does the user hold View All?

    alt OWD is public, or user holds View All
        Note over RA: Sharing is bypassed.<br/>The org total IS the answer.
        RA->>DB: SELECT COUNT() FROM the object WITH USER_MODE
        RA-->>C: Reach { isExact = true, reachableRecords = total }
    else OWD is Controlled by Parent
        RA->>DB: EntityDefinition for the parent
        Note over RA: Re-enter this branch against<br/>the parent's OWD.
    else OWD is private
        RA->>DB: COUNT() WHERE OwnerId = :subjectId
        RA->>DB: COUNT() over the object share table for the user and their groups
        Note over RA: Role-hierarchy access writes<br/>no share rows. Nothing to count.
        RA-->>C: Reach { isExact = false, reachableRecords = owned + shared }
    end

    C-->>LWC: Reach
    LWC->>LWC: isExact ? render total : render "at least N"
    LWC-->>U: figure WITH its basis
```

## The two things this diagram exists to pin

**Step 6.** `totalRecords` is counted `WITH USER_MODE` as the **running** administrator. It is a
denominator. Rendering it as the subject's access is wrong, and it is wrong in the direction that
overstates.

**The final step.** `isExact` is not optional metadata. A client that renders `reachableRecords`
without consulting it turns a careful answer into a false one — and under a private org-wide default
the error **understates** access, which is how an access review passes something it should not.

## See also

- [../RECORD-VISIBILITY.md](../RECORD-VISIBILITY.md)
- [../adr/0009-record-reach-approximation.md](../adr/0009-record-reach-approximation.md)
- [../TESTING.md](../TESTING.md) §3b — the correctness matrix for this branch
