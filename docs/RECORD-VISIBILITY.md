# Record Visibility

How Data Visibility works out *how many records a user reaches*, and when that number is the whole
answer rather than a lower bound.

**Audience:** engineers changing `PERecordAccessService` or `PERecordListService`, AppExchange
security reviewers, anyone about to write a claim about this feature in listing copy.

---

## 1. The constraint everything else follows from

Apex runs as the **running** user. `with sharing` enforces *your* sharing, not theirs. So:

```apex
SELECT COUNT() FROM Account
```

returns what the administrator on screen can see, no matter whose name is in the WHO column. That
figure is a **denominator** — useful context, never the answer.

The honest version of the question is therefore not *"what can they see"* but *"what can we prove
they can see, and how much is left over that we cannot count?"*

---

## 2. Four cases, in the order the service checks them

| # | Condition | Result | Basis |
| --- | --- | --- | --- |
| 1 | Org-wide default is **Public Read** or **Public Read/Write** | Every user with object read reaches every record — the org total **is** the answer | `EntityDefinition`, authoritative |
| 2 | User holds **View All** on the object | Same — sharing is bypassed | `ObjectPermissions` via the resolved graph |
| 3 | Object is **Controlled by Parent** | Resolve against the parent's OWD | `EntityDefinition` |
| 4 | Anything else (private, or public read with a restricting rule) | Owned + shared, deduplicated — a **floor** | `OwnerId` count + share-object rows |

Cases 1 and 2 are **exact**: one query, complete, no further work. The panel says so.

Case 4 is where the honesty lives. See §3.

---

## 3. Why case 4 is a floor and not a total

Under a private org-wide default a user reaches a record through one of:

- **Ownership** — countable exactly, `WHERE OwnerId = :subjectId`.
- **A share row** — manual shares, sharing-rule shares, team shares, all land in the object's share
  table (`AccountShare`, `Custom__Share`, …) and are countable.
- **The role hierarchy** — **not countable.** No share row is written. The platform computes
  hierarchy access at query time, for the running user, and there is no supported way to ask it the
  question on someone else's behalf without **View All Data**.

`UserRecordAccess` would answer it, and is deliberately not used: querying it for another user
requires View All Data, which is exactly the Setup-level privilege this product exists to avoid
handing out. Granting it to use a tool whose premise is *not* granting it would be self-defeating.

So the service reports **owned + shared**, deduplicated, and labels it:

> **At least 3,412 records.** A manager above this user in the role hierarchy reaches more; hierarchy
> access leaves no rows to count.

A floor is never rendered as a total, never used as the numerator of a percentage, and never rounded
up in copy.

---

## 4. The reason breakdown

`PERecordListService.getReasonBreakdown` groups the share rows by `RowCause` and returns buckets,
largest first. Typical causes:

| `RowCause` | Reads as |
| --- | --- |
| `Owner` | Owns the record |
| `Manual` | Shared directly with this user |
| `Rule` | Shared by a sharing rule |
| `Team` / `AccountTeam` / `SalesTeam` | On the record's team |
| `ImplicitChild`, `ImplicitParent` | Inherited from a related record |

Buckets are a decomposition of the countable part only. They never sum to more than the floor, and
the panel does not imply they sum to the user's true access.

---

## 5. The record list

`getPage` returns one page of actual records with the subject's access to each.

- **One list with a filter, not two modes.** An earlier design had a "reachable only" mode and an
  "all records" mode because a filtered list was assumed unable to report a true total. That was
  wrong: the total comes from its own query and has nothing to do with which page is on screen. The
  footer can always say something true — *"Showing 200 of 3,412 reachable"*.
- **Paging depends on the basis.** When sharing is bypassed (case 1 or 2) the page is driven
  straight off the object. Otherwise it is driven off the share rows and the owned set.
- **`totalIsFloor`** travels with the page so the footer can qualify the number without the client
  re-deriving why.
- **`hasNameField`, `searchSupported`** are explicit: some objects have no name field, and free-text
  search is only offered in ALL mode against that field.

---

## 6. Security posture

Three points a reviewer will ask about, answered in the design rather than in a reply:

1. **Nothing is rendered that the running user cannot already query.** Every query runs
   `WITH USER_MODE` as the running administrator. The subject's access is *described*, never
   *exercised*. If the administrator cannot see a record, it does not appear, regardless of whether
   the subject could.
2. **The org total is the administrator's view**, not the subject's, and is labelled a denominator.
3. **No elevation is requested anywhere.** View All Data and Modify All Data are not required, not
   checked for, and not recommended in any install instruction.

See [SECURITY-MODEL.md](SECURITY-MODEL.md) §5.

---

## 7. Transport types

| Type | Key fields |
| --- | --- |
| `PERecordAccessService.Reach` | `internalSharing`, `externalSharing`, `sharingLabel`, `isPublic`, `totalRecords`, `ownedRecords`, `sharedRecords`, `reachableRecords`, `isExact` |
| `PERecordListService.RecordPage` | `rows`, `nextCursor`, `hasMore`, `totalReachable`, `totalRecords`, `totalIsFloor`, `reachableOnly`, `sharingBypassed`, `hasNameField`, `searchSupported` |
| `PERecordListService.ReasonBucket` | share cause, label, count |

`isExact` and `totalIsFloor` are the two flags the UI must never drop. A page that renders the number
without the qualifier turns a careful answer into a false one.

---

## 8. What this does not do

| Not done | Why |
| --- | --- |
| Count hierarchy-derived access | No share rows exist; `UserRecordAccess` needs View All Data |
| Evaluate restriction rules | Not exposed to SOQL; outside `UserRecordAccess` too |
| Evaluate scoping rules | Same |
| Answer "can this user see *this specific* record" | Would need `UserRecordAccess` for another user |
| Write, reassign or reshare anything | The product is read-only |

Each of these is a candidate for a future version only if it can be done without View All Data. If it
cannot, it stays out — see [ROADMAP.md](ROADMAP.md).

---

## 9. Changing this subsystem

- [ ] Any new figure carries an explicit basis — exact, floor, or unavailable
- [ ] No figure is presented as a total unless the service proved it is one
- [ ] Every query runs `WITH USER_MODE`
- [ ] Object, field and relationship names come from `Schema.SObjectType`, never literals (ADR-0012)
- [ ] `PERecordAccessServiceTest` and `PERecordListServiceTest` cover the exact and floor paths
      separately
- [ ] Copy in the UI is re-read after the change — a correct number under a wrong label is a wrong
      answer
