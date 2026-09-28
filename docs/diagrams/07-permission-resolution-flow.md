# 07 — Permission Resolution Flow

How grants and muting combine into an answer. This is the product's core logic; see
[PERMISSION-RESOLUTION.md](../PERMISSION-RESOLUTION.md) for the narrative.

```mermaid
flowchart TD
    START([resolve userId]) --> CACHE{"Cache hit?<br/>resolvedV3:token:userId"}
    CACHE -->|yes| DONE([return Resolved])

    CACHE -->|no| PROF["Load profile as PermissionSet<br/>WHERE ProfileId = user.ProfileId"]
    PROF --> P1["effectiveParents += profileSetId<br/>kind = 'profile'"]

    P1 --> ASSIGN["Query PermissionSetAssignment<br/>WHERE AssigneeId = :userId"]
    ASSIGN --> SPLIT{"PermissionSetGroupId<br/>present?"}

    SPLIT -->|no| DIRECT["effectiveParents += permissionSetId<br/>kind = 'permset'"]
    SPLIT -->|yes| GRP["Collect groupId<br/>build PermSetGroupRow"]

    GRP --> COMP["Query PermissionSetGroupComponent<br/>WHERE PermissionSetGroupId IN :groupIds"]
    COMP --> TYPE{"component PermissionSet.Type<br/>= 'Muting'?"}

    TYPE -->|no| CG["effectiveParents += componentSetId<br/>kind = 'group', groupLabel set"]
    TYPE -->|yes| MUTE["mutingParents += componentSetId<br/>effectiveParents -= componentSetId<br/>kind = 'muting'"]

    DIRECT --> STATUS
    CG --> STATUS
    MUTE --> STATUS
    STATUS{"PermissionSetGroup.Status<br/>= 'Updated'?"}
    STATUS -->|no| FLAG["outdatedGroups += groupLabel<br/><i>include the grants, flag the answer</i>"]
    STATUS -->|yes| STORE
    FLAG --> STORE["Write Resolved to org cache<br/>under CACHE_PREFIX"]
    STORE --> DONE

    DONE --> APPLY

    subgraph APPLY["applyGrant(permissionName)"]
        direction TB
        Q1{"Any parent in effectiveParents<br/>has this permission = true?"}
        Q1 -->|no| NOTG["granted = false<br/>muted = false"]
        Q1 -->|yes| Q2{"Any parent in mutingParents<br/>has this permission = true?"}
        Q2 -->|no| G["granted = true<br/>muted = false"]
        Q2 -->|yes| GM["granted = true<br/>muted = true"]
    end

    NOTG --> RED["🔴 Not granted<br/>#C0483C"]
    G --> GREEN["🟢 Granted<br/>#1F8A6B"]
    GM --> AMBER["🟠 Granted then muted —<br/>user does NOT have it<br/>#B4801F"]

    classDef danger fill:#fbeceb,stroke:#C0483C,color:#15181D
    classDef good fill:#e6f4ef,stroke:#1F8A6B,color:#15181D
    classDef warn fill:#faf1de,stroke:#B4801F,color:#15181D
    class MUTE,AMBER warn
    class GM warn
    class GREEN,G good
    class RED,NOTG danger
    class FLAG warn
```

## The rule that is easy to get wrong

Muting is **scoped to its own permission set group**. A muting set in group A does not cancel a
permission granted by a *direct* assignment or by the profile, nor one granted by group B. A resolver
that treats `mutingParents` as an org-wide subtraction set will under-report access — the opposite
error to the union bug, and just as wrong.

Scenarios 4, 5, 6 and 8 in [TESTING.md](../TESTING.md) §3 exist to pin this down.
