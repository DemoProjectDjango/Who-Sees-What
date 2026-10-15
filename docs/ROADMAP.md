# Roadmap

Sequencing, the reasoning behind it, and the features declined on purpose.

**Rule for every entry:** does it help someone answer an access question *without* being handed
Setup? If the honest answer is no, it does not go on the list, however popular it is in the category.

---

## 1. Shipped

| Version | Scope |
| --- | --- |
| `0.1` – `0.3` | Permission resolution, user search, object and field access, muting subtraction, keyset pagination, Platform Cache. `0.3.0-1` promoted and listed. |
| `0.4` | Full UI redesign. Enterprise blue, three-column WHO / WHERE / WHAT, staged accordion navigation. |
| `0.5` | Access trace, License Inspector, org stats bar. |
| `0.6` | Data Visibility (record reach, reason breakdown, record list) · Inspection Log viewer · Home with posture signals · muting correctness matrix executed. Beta `0.6.0-2`. |

---

## 2. Before anything else ships

These are not features. They gate the next promotion.

| # | Item | Why it blocks |
| --- | --- | --- |
| 1 | Delete `PEInspectionLogService (1).cls` | Committed download duplicate with no `-meta.xml`. Fails or silently skews a build. |
| 2 | Resolve `peBase` | CSS and meta only. Salesforce rejects a bundle in this shape. |
| 3 | Clear the `AvoidHardcodingId` PMD finding | Not review-blocking, but an expected finding trains everyone to ignore scan output. |
| 4 | Re-run Checkmarx and Code Analyzer, commit **one** authoritative report set | Current committed evidence is from 0.5-era, 28 September. |
| 5 | Seed the reviewer org with fictional data | Blocks security-review submission. [DEMO-ORG-SEED.md](DEMO-ORG-SEED.md) |
| 6 | Review the AppExchange listing subtitle against what 0.6 actually does | [LISTING-COPY.md](LISTING-COPY.md) |
| 7 | Confirm Partner Business Org status and Partner Program membership | Blocks listing completion. |

Items 1–3 are hours. Items 4–7 are the real path to promotion.

---

## 3. 0.7 — candidate scope

### Record type and page layout visibility, per user

**Status:** designed, not started. Depends on the Apex Metadata API.

`Profile.recordTypeVisibilities` and `PermissionSet.recordTypeVisibilities` are Metadata API only.
The product currently renders the org-wide `RecordType` catalogue and labels it as such, which is
honest but answers a question nobody asked.

Transport decision is already made: **Apex Metadata API** (`Metadata.Operations.retrieve`), not
Named Credentials and not the Visualforce session-ID pattern. It avoids both a callout declaration
and a credential the subscriber has to configure. See
[adr/0007-defer-record-types-to-metadata-api.md](adr/0007-defer-record-types-to-metadata-api.md).

**Unverified prerequisites — check these before committing the version:**

1. Does `Metadata.Operations.retrieve` support `PermissionSet` and `Profile` types? Write a throwaway
   snippet in `wsw-dev` and confirm before any UI work.
2. Do muting permission sets affect record type visibility? If they do, the resolver needs the same
   subtraction here, and the muting matrix needs new scenarios.
3. What is the retrieve latency on a profile-heavy org? If it is seconds, this needs to be
   asynchronous, which changes the UI pattern.

The same investment unblocks true per-permission-set app visibility, which currently resolves from
`AppMenuItem` and is disclosed as an estimate. Two gaps, one transport.

### Inspection Log export

CSV from the viewer. Low effort; completes the audit-defensibility argument, because "we can show
you" is weaker than "here is the file".

---

## 4. 0.8 and beyond — ordered

| Feature | Fit with delegation | Effort | Note |
| --- | --- | --- | --- |
| **Compare Two Users** | Strong — *"why can she do it and I can't"* is the single most common form of the question | Medium | Reuses the resolver for two subjects and diffs. Nothing new to query. |
| **Access Trace visualisation** | Strong | Medium | The data already exists in `sourcesById`; this is a rendering problem, not a resolution one. |
| **What-If Simulator** — *"if I add this permission set, what changes"* | Strong | High | Must remain read-only: simulate by resolving against a hypothetical parent list, never by assigning anything. |
| **Record Access Diagnosis** — *"can this user see this record, and why"* | **Conflicted** | High | See below. |

### Record Access Diagnosis, and why it is last

`UserRecordAccess` for another user requires **View All Data**. Requiring that to run a tool whose
entire premise is not granting Setup-level privilege is self-defeating.

Three sub-problems, not one:

1. **The access answer itself** — needs View All Data. No way around it today.
2. **Naming the sharing rule responsible** — needs the Metadata API, so it rides on the 0.7
   investment.
3. **Restriction rules and scoping rules** — not exposed to SOQL, and outside `UserRecordAccess`
   too. Even with View All Data the answer would be incomplete.

If this ships, it ships as an **opt-in** capability for administrators who already hold View All
Data, clearly separated from the delegated experience, and labelled as such. It must never become a
reason the product's install instructions say "grant View All Data".

---

## 5. Declined by design

Not "not yet" — **no**, with the reason, so it is not re-litigated every quarter.

| Declined | Reason |
| --- | --- |
| HTTP callouts, Named Credentials | Every external endpoint is a security-review question and a subscriber configuration step. Zero is the cheapest answer and a real differentiator. |
| Writing or modifying permissions | A read-only tool cannot break a subscriber's org. The moment it can grant, it needs a completely different trust conversation. |
| Requiring View All Data or Modify All Data | Contradicts the premise. |
| Custom REST or SOAP endpoints | No external surface area. |
| Deleting from `PE_Inspection_Log__c` | The product does not delete data it did not ask permission to delete — and an erasable trail is not a trail. |
| Storing a copy of any subscriber data | Lookups to `User`, never copies of PII. |
| Scheduled jobs or background processing | Adds a failure mode a subscriber has to monitor, for a tool that is answering a question in front of someone. |

---

## 6. Principles that decide ties

1. **Delegation is the north star.** Evaluate every feature against answering access questions
   without handing over Setup privileges.
2. **Correctness before features.** Ship correctness proofs before expanding scope. The muting matrix
   came before Data Visibility for this reason.
3. **An honest limit beats a confident guess.** A labelled floor is a feature. An unlabelled estimate
   is a defect waiting for a support ticket.
4. **One investment, two gaps, where possible.** The Metadata API unblocks record types *and* true
   app visibility; that is why it outranks features with a single payoff.
