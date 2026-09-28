# 10 — Caching and Invalidation

Where data comes from, how long it lives, and how it is invalidated.

```mermaid
flowchart TD
    REQ([Apex request]) --> SVC["Domain service<br/>needs data"]
    SVC --> AVAIL{"PECacheManager<br/>partition available?"}

    AVAIL -->|no| FALL["Request-scoped Map fallback<br/><i>correct, just slower</i>"]
    FALL --> QUERY

    AVAIL -->|yes| TOKEN["Read orgVersionToken"]
    TOKEN --> KEY["Build key:<br/>safeKey(prefix : token : subject)"]
    KEY --> SCOPE{"Shared across<br/>administrators?"}

    SCOPE -->|yes| ORGP["Org partition<br/>resolvedV3, orgStats, licenses"]
    SCOPE -->|no| SESSP["Session partition<br/>per-user working state"]

    ORGP --> HIT{"Hit?"}
    SESSP --> HIT
    HIT -->|yes| RETURN([Return cached value])
    HIT -->|no| QUERY["SOQL / Schema describe"]
    QUERY --> PUT["Write to partition with TTL"]
    PUT --> RETURN

    subgraph INVAL["Invalidation"]
        direction TB
        UIREF["Administrator clicks Refresh"] --> BUMP["PECacheManager.bumpVersionToken()"]
        FORCE["resolveUser(forceRefresh = true)"] --> SKIP["Bypass read, recompute, overwrite"]
        SHAPE["Cached object's shape changed"] --> PREFIX["<b>Bump CACHE_PREFIX</b><br/>resolvedV3 → resolvedV4"]
        BUMP --> ALLGONE["Every key containing the old token<br/>becomes unreachable at once"]
        PREFIX --> ALLGONE
    end

    ALLGONE -.->|"next request rebuilds"| QUERY

    classDef danger fill:#fbeceb,stroke:#C0483C,color:#15181D
    classDef warn fill:#faf1de,stroke:#B4801F,color:#15181D
    classDef good fill:#e6f4ef,stroke:#1F8A6B,color:#15181D
    class SHAPE,PREFIX danger
    class FALL warn
    class RETURN good
```

## Key inventory

| Key shape | Partition | Holds | Invalidated by |
| --- | --- | --- | --- |
| `orgVersionToken` | Org | The token itself | `bumpVersionToken()` |
| `resolvedV3:<token>:<userId>` | Org | `PEPermissionResolver.Resolved` | token bump · `forceRefresh` · TTL |
| `orgStats:<token>` | Org | `PEDto.OrgStats` | token bump · TTL |
| `licenses:<token>` | Org | Serialised license rows | token bump · TTL |

## Rules

1. **Cache is an optimisation, never a source of truth.** Fallback must always produce the same
   answer, only slower.
2. **The version token participates in every key.** One bump invalidates everything, which is why the
   refresh control can be a single button rather than a per-key purge.
3. **Bump `CACHE_PREFIX` whenever the shape of a cached object changes.** A payload of the old shape
   deserialises *without error* and silently loses fields — a resolved graph missing its
   `mutingParents` reads as "this user has no muting sets", which is exactly the wrong answer
   delivered confidently. This is the most dangerous known failure mode in the codebase.
4. **Sanitise every key.** Platform Cache keys are alphanumeric only; raw object API names and
   usernames will throw.
5. **Never resolve partition availability through a self-referencing static property getter.** Use an
   explicit `*Resolved` boolean — the recursion has bitten this codebase once already.
