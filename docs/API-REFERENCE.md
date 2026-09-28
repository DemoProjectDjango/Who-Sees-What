# API Reference

The complete `@AuraEnabled` surface of the package. **`PermissionExplorerController` is the only
class LWCs may import from.**

All methods:
- call `PEAccessGate` before doing anything else;
- throw `AuraHandledException` carrying a user-facing message and a `retryable` flag;
- return typed `PEDto` classes (or a JSON `String` where noted).

---

## `PermissionExplorerController`

### `getFilterOptions()`

```js
import getFilterOptions from '@salesforce/apex/PermissionExplorerController.getFilterOptions';
```

| | |
| --- | --- |
| Signature | `Map<String, Object> getFilterOptions()` |
| Cacheable | **Yes** (`cacheable=true`) — org-shaped reference data, not user access |
| Returns | Profiles, roles and user types for the search filters |
| Audit | Not logged (no subject user) |

---

### `searchUsers(term, profileId, roleId, userType, sortField, encodedCursor, pageSize)`

| | |
| --- | --- |
| Returns | `PEDto.PagedResult` |
| Cacheable | No |
| Pagination | Keyset. Pass `nextCursor` from the previous response; `null` for the first page. |
| Sort fields | `Name`, `LastLoginDate` — anything else throws |
| Cap | `capReached = true` at `PEConstants.MAX_SEARCH_RESULTS` (200); the UI shows _"refine your search"_ |
| Page size | Defaults to `PEConstants.USER_PAGE_SIZE` (50) |

Only active users are returned. Frozen users are returned with `isFrozen = true`.

---

### `resolveUser(userId, forceRefresh)`

| | |
| --- | --- |
| Returns | `PEDto.UserContext` — summary, counts, outdated group warnings, visible apps |
| `forceRefresh` | `true` bypasses the resolver cache |
| Audit | `RESOLVE_USER` |
| Throws | `NOT_FOUND` (user gone), `INACTIVE_USER`, `NOT_AUTHORISED` |

The first call for a user is the expensive one; subsequent calls hit the org cache partition.

---

### `getLoginHistory(userId, maxRows)`

| | |
| --- | --- |
| Returns | `PEDto.LoginHistoryResult` |
| `maxRows` | Defaults to 50, capped at 200 |
| Audit | Logged |
| Note | Returns an empty, flagged result if the running user cannot read `LoginHistory` — it does not throw |

---

### `getAssignedPermissionSets(userId)`

| | |
| --- | --- |
| Returns | `PEDto.PermSetList` — direct assignments plus a group-derived count |

### `getAssignedPermissionSetGroups(userId)`

| | |
| --- | --- |
| Returns | `List<PEDto.PermSetGroupRow>` — includes `Status`, so outdated groups can be flagged |

---

### `getAppObjects(userId, appDeveloperName)`

| | |
| --- | --- |
| Returns | `List<PEDto.ObjectRow>` |
| Audit | Logged with the app name in `Detail__c` |

Rows are the objects reachable from the app's tabs, **plus** an explicit "access without a tab"
section for objects the user can read but cannot navigate to.

---

### `getObjectDetail(userId, objectApiName)`

| | |
| --- | --- |
| Returns | `PEDto.ObjectDetail` — object grants, field permissions, record types, sharing model |
| Audit | Logged with the object name |

Each `FieldPerm` is `readable`, `editable`, or `notApplicable` with a `reason` supplied by
`PEFlsClassifier`. Record types returned here are **org-wide**, not per-user — see
[ARCHITECTURE.md](ARCHITECTURE.md) §7.

---

### `getLicenses()`

| | |
| --- | --- |
| Returns | `String` — serialised `List<PELicenseRow>` |
| Covers | User licenses, permission set licenses, package licenses, usage entitlements |

### `getLicenseUsers(licenseId, licenseType)`

| | |
| --- | --- |
| Returns | `String` — serialised `List<PELicenseUserRow>` |
| `licenseType` | `UserLicense` · `PermissionSetLicense` · `PackageLicense` · `UsageEntitlement` |

> These two return JSON strings rather than DTOs. When touching them, remember `List<Object>` is not
> serialisable via `@AuraEnabled` — that constraint is why the string form exists.

---

### `getOrgStats()`

| | |
| --- | --- |
| Returns | `PEDto.OrgStats` — user, profile, permission set and group counts |
| Cached | Org partition |

---

### `refreshCache()`

| | |
| --- | --- |
| Returns | `String` — the new version token |
| Effect | `PECacheManager.bumpVersionToken()` — invalidates **all** product cache entries org-wide |
| Audit | Logged |

Backs the UI's refresh control. Because the token participates in every key, one bump invalidates
everything rather than requiring per-key deletion.

---

## Error Contract

`PermissionExplorerException` codes surfaced to the UI:

| Cause | Meaning | Retryable |
| --- | --- | --- |
| `NOT_AUTHORISED` | Missing the `Use_Permission_Explorer` custom permission | No |
| `NOT_FOUND` | Target user no longer exists | No |
| `INACTIVE_USER` | Target user is inactive | No |
| `BAD_CURSOR` | Malformed or tampered pagination cursor | No — the UI resets to page one |
| `QUERY_BUDGET` | Planned SOQL fan-out would breach governor limits | Yes — narrow the scope |
| `UNEXPECTED` | Anything else | Yes |

LWCs read `retryable` to decide between offering a retry and telling the user to contact an
administrator. `peUtils/errors.js` holds the shared mapping.

---

## Adding a Method

1. Add it to `PermissionExplorerController` — nowhere else.
2. First statement: `PEAccessGate.assertAuthorisedAndLog(...)`.
3. Guard the target with `assertInspectable(userId)` if it takes a user.
4. Delegate to a service; keep query logic out of the controller.
5. Return a typed `PEDto` class — never `List<Object>`, never a raw sObject.
6. Wrap in `try/catch` and convert through `toAura`.
7. Add tests for the authorised and unauthorised path.
8. Update this document in the same pull request.
