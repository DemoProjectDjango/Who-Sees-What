# 05 — Sequence: Resolve a User

From search result click to a rendered access summary.

```mermaid
sequenceDiagram
    autonumber
    actor A as Administrator
    participant UC as peUserColumn
    participant PX as permissionExplorer
    participant C as PermissionExplorerController
    participant G as PEAccessGate
    participant AL as PEInspectionAuditLogger
    participant R as PEPermissionResolver
    participant K as PECacheManager
    participant AV as PEAppVisibilityService
    participant DB as Salesforce Platform

    A->>UC: type search term
    UC->>C: searchUsers(term, filters, cursor, pageSize)
    C->>G: assertAuthorised()
    G-->>C: ok
    C->>DB: SELECT User … bound filters, keyset WHERE, LIMIT
    DB-->>C: rows
    C-->>UC: PEDto.PagedResult (hasMore, nextCursor, capReached)
    UC-->>A: render list

    A->>UC: select a user
    UC->>PX: userselected event
    PX->>C: resolveUser(userId, forceRefresh=false)

    C->>G: assertAuthorisedAndLog('RESOLVE_USER', userId, detail)
    G->>G: FeatureManagement.checkPermission('Use_Permission_Explorer')
    alt not authorised
        G-->>C: throw NOT_AUTHORISED (retryable=false)
        C-->>PX: AuraHandledException
        PX-->>A: "Ask an administrator to assign the permission set"
    else authorised
        G->>AL: buffer audit row
        C->>G: assertInspectable(userId)
        G->>DB: SELECT User … WITH USER_MODE
        alt user missing or inactive
            G-->>C: throw NOT_FOUND / INACTIVE_USER
        else ok
            G-->>C: User
            C->>R: resolve(userId, false)
            R->>K: orgGet('resolvedV4:<token>:<userId>')
            alt cache hit
                K-->>R: Resolved
            else cache miss
                R->>DB: PermissionSet WHERE ProfileId = :pid
                R->>DB: PermissionSetAssignment WHERE AssigneeId = :uid
                R->>DB: PermissionSetGroup WHERE Id IN :groupIds
                R->>DB: PermissionSetGroupComponent WHERE PermissionSetGroupId IN :groupIds
                R->>R: effectiveParents += components
                R->>R: mutingParents += Type='Muting'; remove from effectiveParents
                R->>R: outdatedGroups += Status != 'Updated'
                R->>K: orgPut(key, Resolved, ttl)
            end
            R-->>C: Resolved
            C->>AV: getVisibleApps(userId, Resolved)
            AV->>DB: AppMenuItem
            AV-->>C: PEDto.AppList
            C-->>PX: PEDto.UserContext
            PX-->>A: summary header, app column, outdated-group warning
        end
    end

    AL->>DB: insert PE_Inspection_Log__c (single flush)
```

## Notes

- The gate runs **before** anything else, including the target-user lookup.
- The audit row is buffered and flushed once, so a multi-service request still costs one DML.
- `capReached` drives the "refine your search" message rather than letting the administrator page
  through thousands of rows.
- A cache miss costs four queries; a hit costs none. This is why the first inspection of a user feels
  slower than the rest.
