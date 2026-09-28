# 06 — Sequence: Build Object Detail and Field-Level Security

The WHAT column: from an object click to a classified field table with attribution.

```mermaid
sequenceDiagram
    autonumber
    actor A as Administrator
    participant OL as peObjectList
    participant WC as peWhatColumn
    participant C as PermissionExplorerController
    participant G as PEAccessGate
    participant Q as PEAccessQueryService
    participant R as PEPermissionResolver
    participant M as PEMetadataCatalog
    participant F as PEFlsClassifier
    participant CH as PESoqlChunker
    participant DB as Salesforce Platform

    A->>OL: select object
    OL->>WC: objectselected
    WC->>C: getObjectDetail(userId, objectApiName)

    C->>G: assertAuthorisedAndLog('OBJECT_DETAIL', userId, objectApiName)
    C->>G: assertInspectable(userId)
    C->>Q: getObjectDetail(userId, objectApiName, Resolved)

    Q->>R: resolve(userId)
    R-->>Q: Resolved (effectiveParents, mutingParents, sourcesById)

    Q->>M: fieldMap(objectApiName)
    M->>DB: Schema.getGlobalDescribe() (memoised per request)
    M-->>Q: Map<String, SObjectField>
    Q->>Q: seedFieldRows — every field starts as "no access"

    Q->>CH: chunk(effectiveParents ∪ mutingParents)
    CH-->>Q: batches of 100 IDs
    CH->>CH: assertQueryBudget(plannedQueries)

    loop per batch
        Q->>DB: ObjectPermissions WHERE ParentId IN :batch AND SobjectType = :obj
        Q->>DB: FieldPermissions WHERE ParentId IN :batch AND SobjectType = :obj
    end

    Q->>Q: mergeCrud across effective parents
    Q->>Q: applyGrant → granted / muted per permission
    Q->>Q: buildObjectGrants with sources from sourcesById

    loop per field
        Q->>F: classify(DescribeFieldResult)
        alt formula / auto-number / system audit / master-detail key
            F-->>Q: Verdict(notApplicable=true, reason)
        else FLS applies
            F-->>Q: Verdict(notApplicable=false)
            Q->>Q: readable / editable from merged FieldPermissions
        end
    end

    Q->>DB: RecordType WHERE SobjectType = :obj (org-wide, labelled as such)
    Q->>M: sharingModel(objectApiName)
    Q-->>C: PEDto.ObjectDetail
    C-->>WC: ObjectDetail
    WC-->>A: CRUD chips + field table + attribution chips
```

## Notes

- **Fields are seeded from the describe, not from `FieldPermissions`.** A field with no row in
  `FieldPermissions` means *no access*, not *absent*. Seeding first is what prevents silently
  dropping inaccessible fields from the table.
- `PESoqlChunker` batches `ParentId IN :ids` at 100 and asserts the query budget before fan-out, so a
  user with many permission sets fails loudly rather than hitting a governor limit mid-render.
- Record types returned here are **org-wide**. See
  [ADR-0007](../adr/0007-defer-record-types-to-metadata-api.md).
