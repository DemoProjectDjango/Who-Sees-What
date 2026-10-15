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

## Data Visibility

These three back the `dataVisibility` tab. Methodology, and the meaning of every flag they return,
is in [RECORD-VISIBILITY.md](RECORD-VISIBILITY.md).

### `getRecordReach(userId, objectApiName)`

| | |
| --- | --- |
| Returns | `PERecordAccessService.Reach` |
| Cacheable | No |
| Audit | `VIEW_RECORD_REACH` |
| Key flags | `isExact` — `true` when `reachableRecords` is the complete answer, `false` when it is a floor |

`totalRecords` is the org count **as the running user sees it**. It is a denominator, never the
subject's answer. A client that renders it as the subject's access is wrong.

---

### `getReasonBreakdown(userId, objectApiName)`

| | |
| --- | --- |
| Returns | `List<PERecordListService.ReasonBucket>` — largest first |
| Cacheable | No |
| Audit | **Not logged** — always follows a logged `VIEW_RECORD_REACH` on the same user and object; logging it again double-counts one act |

Buckets decompose the **countable** part only. They do not sum to the subject's true access under a
private org-wide default.

---

### `getRecordPage(userId, objectApiName, reachableOnly, searchTerm, sortField, cursor)`

| | |
| --- | --- |
| Returns | `PERecordListService.RecordPage` |
| Cacheable | No |
| Pagination | Cursor. Pass `nextCursor` from the previous response; `null` for the first page. |
| `searchTerm` | ALL mode only, against the name field. Ignored when `searchSupported = false`. |
| Audit | `VIEW_RECORD_LIST` — **once per page**, because paging through someone's data is the same act as inspecting it |
| Key flags | `totalIsFloor`, `sharingBypassed`, `hasNameField`, `searchSupported` |

`totalReachable` comes from its own query and does not depend on which page is on screen, so the
footer can always say something true. Carry `totalIsFloor` into that footer — a floor rendered as a
total turns a careful answer into a false one.

Six parameters, one of them a Boolean: both PMD findings are suppressed with a comment. This is the
wire contract the record list calls with, and every argument is a control the administrator can see
on screen. Wrapping them would mean the LWC builds an object whose shape is defined nowhere.

---

## Posture and Audit

### `getPosture()` · `refreshPosture()`

| | |
| --- | --- |
| Returns | `PEPostureService.Posture` — signals, licence utilisation, active user count |
| Cached | Org partition, key `postureV1`. `refreshPosture()` bypasses it. |
| Audit | **Not logged** — org-level configuration counts, no subject to attribute |

Each signal is a count with a `remedy`. A signal whose query failed comes back with a null count and
**must** render as *unavailable*, never as zero.

---

### `getRecentInspections(inspectorId, subjectId, rowLimit)`

| | |
| --- | --- |
| Returns | `PEInspectionLogService.LogPage` |
| Cacheable | **No** — an audit panel exists to reflect what just happened; a client-cached page would show an admin a trail predating their own last inspection |
| Filters | Both optional; omit for the whole readable trail |
| `rowLimit` | Clamped by the service |
| Audit | **Not logged.** Gated, but reading the log is not itself an inspection — a trail that records its own observation is noise, not evidence. |

Returns `readable = false` with a `notice` rather than throwing when the running user cannot read
`PE_Inspection_Log__c`. `totalCount` and `last7Days` are null when the count failed; null means
unavailable, not zero.

See [AUDIT-TRAIL.md](AUDIT-TRAIL.md).

---

### `getOrgStats()`

| | |
| --- | --- |
| Returns | `PEDto.OrgStats` — active users, profiles, permission sets, groups, reachable apps, objects with at least one grant |
| Cached | Org partition, key `orgStatsV1`. `refreshOrgStats()` bypasses it. |
| Audit | Not logged — org-level counts, no subject |

Each of the six counts runs in its own try/catch. These are unrelated queries against objects of
varying obscurity, and one being unavailable in a given org is not a reason to blank the other five.

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
2. First statement: `PEAccessGate.assertAuthorisedAndLog(...)` if the method inspects a **person**.
   If it does not — org-level counts, reference data, or a read of the log itself — use
   `assertAuthorised()` and say in a comment why no row is written. Silence there reads as an
   oversight.
3. Guard the target with `assertInspectable(userId)` if it takes a user.
4. Delegate to a service; keep query logic out of the controller.
5. Return a typed `PEDto` class — never `List<Object>`, never a raw sObject.
6. Wrap in `try/catch` and convert through `toAura`.
7. Add tests for the authorised and unauthorised path.
8. If it returns a figure that may be incomplete, return the basis alongside it. A number without
   its qualifier is not a smaller answer, it is a wrong one.
9. If it builds dynamic SOQL, resolve object, field and relationship names through
   `Schema.SObjectType` so it survives the namespace (ADR-0012).
10. Update this document in the same pull request.
