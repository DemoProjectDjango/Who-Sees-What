# 03 — C4 Level 3: Apex Components

Decomposition of the Apex layer, with dependency direction.

```mermaid
flowchart TD
    subgraph L1["API layer"]
        CTRL["PermissionExplorerController<br/><i>12 @AuraEnabled methods</i>"]
        EXC["PermissionExplorerException<br/><i>typed, retryable-aware</i>"]
    end

    subgraph L2["Authorisation layer"]
        GATE["PEAccessGate<br/>assertAuthorised · assertAuthorisedAndLog · assertInspectable"]
        AUDIT["PEInspectionAuditLogger<br/><i>buffered, append-only — the only DML</i>"]
    end

    subgraph L3["Domain services"]
        RES["PEPermissionResolver<br/><i>effective parents − muting parents</i>"]
        AQS["PEAccessQueryService<br/><i>app objects, object detail, FLS</i>"]
        AVS["PEAppVisibilityService<br/><i>visible apps via AppMenuItem</i>"]
        USS["PEUserSearchService<br/><i>keyset search + filters</i>"]
        UDS["PEUserDetailService<br/><i>login history, perm sets</i>"]
        LIS["PELicenseInspectorService<br/><i>4 license types</i>"]
        OSS["PEOrgStatsService"]
        FLS["PEFlsClassifier<br/><i>not-applicable verdicts</i>"]
    end

    subgraph L4["Infrastructure"]
        CACHE["PECacheManager<br/><i>org + session, version token, fallback</i>"]
        CAT["PEMetadataCatalog<br/><i>describes, tabs, memoised</i>"]
        CHUNK["PESoqlChunker<br/><i>IN :ids batching, budget assert</i>"]
        CUR["PEKeysetCursor<br/><i>validated opaque cursor</i>"]
    end

    subgraph L5["Types"]
        DTO["PEDto<br/><i>Source, Grant, UserRow, UserSummary,<br/>ObjectRow, ObjectDetail, FieldPerm, …</i>"]
        CONST["PEConstants"]
        LR["PELicenseRow"]
        LUR["PELicenseUserRow"]
    end

    CTRL --> GATE
    CTRL --> RES & AQS & AVS & USS & UDS & LIS & OSS
    CTRL --> EXC
    GATE --> AUDIT
    GATE --> CONST

    RES --> CACHE
    RES --> CHUNK
    RES --> DTO
    AQS --> RES
    AQS --> CAT
    AQS --> FLS
    AQS --> CHUNK
    AVS --> RES
    USS --> CUR
    USS --> CONST
    UDS --> RES
    LIS --> LR & LUR
    OSS --> CACHE

    CACHE --> CONST
    CUR --> EXC
    CHUNK --> EXC

    classDef api fill:#1b4db1,stroke:#123a8a,color:#fff
    classDef auth fill:#C0483C,stroke:#8f342b,color:#fff
    classDef svc fill:#e8eef9,stroke:#1b4db1,color:#15181D
    classDef inf fill:#F5F3EE,stroke:#15181D,color:#15181D
    classDef typ fill:#f4f0e4,stroke:#B4801F,color:#15181D
    class CTRL,EXC api
    class GATE,AUDIT auth
    class RES,AQS,AVS,USS,UDS,LIS,OSS,FLS svc
    class CACHE,CAT,CHUNK,CUR inf
    class DTO,CONST,LR,LUR typ
```

## Dependency rules

1. Dependencies point **downward only**. No infrastructure class knows about a service; no service
   knows about the controller.
2. `PEAccessGate` is the only authorisation authority.
3. `PEInspectionAuditLogger` is the only class performing DML.
4. `PEAccessQueryService`, `PEAppVisibilityService` and `PEUserDetailService` consume
   `PEPermissionResolver.Resolved` rather than re-deriving the permission graph.
