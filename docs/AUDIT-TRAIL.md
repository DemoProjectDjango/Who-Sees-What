# Audit Trail

What `PE_Inspection_Log__c` records, what it deliberately does not, and why the distinction is the
whole value of the object.

---

## 1. Why it exists

The product's premise is delegation: a non-admin answers access questions without being handed
Setup. That is only defensible if the answering is **accountable** — someone can later establish who
looked at whose access, when, and for what.

An audit trail nobody can read defends nothing. Until 0.6 the object was append-only and invisible:
every inspection wrote a row, and no part of the product ever showed one. The Inspection Log viewer
closes that.

---

## 2. What is written

One row per inspection action, via `PEInspectionAuditLogger`.

| Field | Holds |
| --- | --- |
| `Inspector_User__c` | Who performed the inspection |
| `Subject_User__c` | Whose access was inspected (null for org-level actions) |
| `Action__c` | Which entry point |
| `Detail__c` | Context — app name, object API name, licence key |
| `Inspected_At__c` | When |

### Actions

| Action | Written by | Subject |
| --- | --- | --- |
| `RESOLVE_USER` | `resolveUser` | Yes |
| `OBJECT_DETAIL` | `getObjectDetail` | Yes |
| `APP_OBJECTS` | `getAppObjects` | Yes |
| `LOGIN_HISTORY` | `getLoginHistory` | Yes |
| `VIEW_RECORD_REACH` | `getRecordReach` | Yes |
| `VIEW_RECORD_LIST` | `getRecordPage` | Yes |
| `VIEW_LICENSE_USERS` | `getLicenseUsers` | No — org-level |
| `REFRESH_CACHE` | `refreshCache` | No |

`VIEW_RECORD_LIST` is written **once per page**, not once per session. Paging through someone's
visible data is the same act as inspecting it, and a trail that recorded only the first page would
understate what was looked at.

---

## 3. What is not written

| Not logged | Why |
| --- | --- |
| `getRecentInspections` — reading the log | A trail that records its own observation is noise, not evidence. The read is gated; it is not logged. |
| `getPosture`, `getOrgStats` | Org-level configuration counts. There is no subject, so there is nothing to attribute. |
| `getFilterOptions`, `searchUsers` | Reference data and search. Searching is not inspecting; the inspection is logged at `RESOLVE_USER`. |
| `getReasonBreakdown` | Follows a `VIEW_RECORD_REACH` on the same user and object, already logged. Logging it again would double-count one act. |

The rule: **log an act of inspecting a person.** Not navigation, not reference data, not the audit
read itself.

---

## 4. Write path

`PEInspectionAuditLogger` buffers rows in a static list and flushes once per request, so a request
touching several services produces a single DML statement.

This is the **only** DML in the codebase.

Gate and log are coupled: `PEAccessGate.assertAuthorisedAndLog(action, subjectId, detail)` does both,
so an inspection cannot occur without a row. A method that calls `assertAuthorised()` alone is
asserting, explicitly, that it is not an inspection — and that choice should be defended in a comment.

---

## 5. Read path

`PEInspectionLogService.getRecent(inspectorId, subjectId, rowLimit)` returns a `LogPage`:

| Field | Holds |
| --- | --- |
| `rows` | The inspection rows, newest first |
| `totalCount` | Rows readable by the running user, or `null` if the count failed |
| `last7Days` | Rows written in the last seven days, or `null` |
| `readable` | `false` when the running user cannot read the object at all |
| `notice` | Set when the panel has something to say about why it is empty |
| `activity` | One entry per day in the window, zero-filled |
| `topInspectors` | Busiest inspectors in the window, descending |

Read-only by construction. There is no update or delete path in the class, and the packaged
permission set grants Read and Create but not Edit or Delete — an inspector can see history without
being able to rewrite it.

A `null` count renders as *unavailable*, never as zero. On an audit panel a fabricated zero reads as
"nothing happened".

### Namespace safety

The query is built from `Schema.SObjectType` rather than literal identifiers:

```apex
String objectName   = Schema.SObjectType.PE_Inspection_Log__c.getName();
String actionField  = Schema.SObjectType.PE_Inspection_Log__c.fields.Action__c.getName();
String inspectorRel = Schema.SObjectType.PE_Inspection_Log__c
                          .fields.Inspector_User__c.getRelationshipName();
```

Dynamic SOQL does not reliably prefix unqualified custom names with the package namespace, so the
earlier static variants would have compiled in the dev org and failed for every subscriber. See
[adr/0012-namespace-safe-dynamic-soql.md](adr/0012-namespace-safe-dynamic-soql.md).

---

## 6. Access posture

| Operation | Granted by `PermissionCheckerPermissionSet` |
| --- | --- |
| Create | Yes — the product must be able to write the trail |
| Read | Yes — the viewer needs it |
| Edit | **No** |
| Delete | **No** |
| View All / Modify All | **No** |

A subscriber administrator can of course grant more through their own permission sets. That is their
decision, and it is worth saying plainly in a deployment conversation: granting Delete on this object
removes the only reason the object is worth keeping.

---

## 7. Retention and growth

The package writes one row per inspection action and **never prunes**. A heavily used org will
accumulate rows.

The package deliberately does not delete data it did not ask permission to delete. Subscribers who
need a retention limit should apply their own scheduled deletion — a scheduled Apex job or a
Flow-based batch over `Inspected_At__c` is sufficient. That job needs Delete on the object, which
means it needs a permission set the product does not ship.

Rough sizing for a capacity conversation: a row is small, but an org with 20 inspectors each
performing 50 inspections a working day accumulates on the order of a quarter of a million rows a
year. That is well within storage limits for most orgs and worth mentioning before it surprises
anyone.

---

## 8. Export

Not shipped. Planned for 0.7 — see [ROADMAP.md](ROADMAP.md). Until then, the object is queryable by
any subscriber tool: a report, a list view, or the Data Loader all work, because the object is
packaged with Read and nothing in the product hides it.
