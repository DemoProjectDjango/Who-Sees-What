# Testing

---

## 1. Layers

| Layer | Framework | Command |
| --- | --- | --- |
| Apex unit and integration | Salesforce test framework | `sf apex run test --target-org wsw-dev --code-coverage --result-format human` |
| LWC unit | Jest via `sfdx-lwc-jest` | `npm run test:unit` |
| Static analysis | Code Analyzer (PMD, SFGE) | `npm run scan` |
| Lint | ESLint | `npm run lint` |

**Current state: 11 Apex test classes, 135 test methods in source.**

Coverage was last recorded at **88%** against `0.3.0-1`. Do not quote that figure as current —
measure it with `--code-coverage` at every version create. Salesforce requires 75% for a managed
package version. Coverage is a floor, not a goal; the correctness matrix in §3 matters more than the
percentage.

---

## 2. Apex Test Classes

| Class | Covers |
| --- | --- |
| `PermissionExplorerTest` | Controller happy paths and DTO mapping |
| `PermissionExplorerControllerTest` | Authorisation, error mapping, argument validation |
| `PermissionExplorerFlowTest` | End-to-end: search → resolve → app objects → object detail, with governor-limit assertions |
| `PEPermissionResolverTest` | Resolution, muting subtraction, outdated groups, caching |
| `PEUserSearchServiceTest` | Keyset pagination, filters, sort whitelist, result cap |
| `PEUserDetailServiceTest` | Login history limits and permission set listing |
| `PEMutingMatrixTest` | The §3 correctness matrix, all ten scenarios, pure logic against synthetic Ids |
| `PERecordAccessServiceTest` | Reach under public, View All, controlled-by-parent and private OWDs; the exact-vs-floor flag |
| `PERecordListServiceTest` | Paging, reason buckets, true totals independent of page, `totalIsFloor` |
| `PEPostureServiceTest` | Each signal computes; a failed signal yields null, never zero |
| `PEInspectionLogServiceTest` | Log read, filters, clamping, the not-readable path |

`PEUserDetailService` caps near 57% by design, not by omission: the not-readable branch cannot be
reached from a test (`System.runAs` enforces sharing, not CRUD) and `LoginHistory` rows cannot be
inserted. Note it rather than chasing it.

### Conventions

- `@isTest` with `@TestSetup` for shared fixtures.
- `System.runAs` for every authorisation path — both granted and denied.
- Assert on **behaviour**, not row counts that shift with org configuration.
- Never assume seed data exists in the org; create fixtures.

---

## 3. The Muting Correctness Matrix

> **Status: passing as of 0.6.** Executed by `PEMutingMatrixTest`.

This is the product's core differentiator and its most likely silent failure. Before that class
existed, scenarios **5, 6 and 8** all reported *no access* for users who genuinely held the
permission, because muting was stored as one flat set with no record of which group each muting set
belonged to.

The matrix runs as **pure logic against synthetic Ids** — no DML, no SOQL, no org fixtures — so it
executes in any org, including a reviewer's, without seeding two groups and three component sets
first. The fixture requirements below therefore apply only to the manual walkthrough in §5 and to
the demo org.

| # | Scenario | Expected `granted` | Expected `muted` | Expected effective access |
| --- | --- | --- | --- | --- |
| 1 | Permission granted by profile only | `true` | `false` | Has it |
| 2 | Granted by a direct permission set only | `true` | `false` | Has it |
| 3 | Granted by a group component set only | `true` | `false` | Has it |
| 4 | Granted by a group component, muted by that group's muting set | `true` | **`true`** | **Does not have it** |
| 5 | Granted by a direct assignment; an unrelated group's muting set mutes the same permission | `true` | `false` | **Has it** — muting is scoped to its own group |
| 6 | Granted by profile; a group's muting set mutes the same permission | `true` | `false` | Has it — muting does not reach the profile |
| 7 | Granted by two component sets in one group, muted once | `true` | `true` | Does not have it |
| 8 | Granted by a component set in group A and a component set in group B; only A is muted | `true` | `false` | Has it via B |
| 9 | Muting set present but the permission was never granted | `false` | `false` | Does not have it |
| 10 | Group `Status != Updated` | as computed | as computed | Computed **and flagged** in `outdatedGroups` |

### Structural invariants

- A muting permission set **never** appears in `effectiveParents`.
- Every ID in `mutingParents` has `PermissionSet.Type = 'Muting'`.
- `sourcesById` contains an entry for every ID in `effectiveParents` and `mutingParents`.
- An outdated group's components are **included** and flagged — never silently dropped.

### Fixture requirements — manual verification only

`PEMutingMatrixTest` needs none of this. To walk the same scenarios by hand, or to build the demo
org ([DEMO-ORG-SEED.md](DEMO-ORG-SEED.md)), you need:

- a profile,
- at least two standalone permission sets,
- two permission set groups,
- at least three component sets distributed across those groups,
- at least two muting permission sets.

> Salesforce rejects `editable=true` on required fields in permission sets. When seeding
> `FieldPermissions` fixtures, use non-required custom fields.

---

## 3b. Record Reach Correctness

Data Visibility's failure mode is not a crash — it is a plausible number under the wrong label.
`PERecordAccessServiceTest` and `PERecordListServiceTest` must cover each basis **separately**:

| # | Condition | Expected `isExact` | Expected figure |
| --- | --- | --- | --- |
| 1 | OWD Public Read or Public Read/Write | `true` | Org total is the answer |
| 2 | User holds View All on the object | `true` | Org total is the answer |
| 3 | OWD Controlled by Parent | per parent OWD | Resolved against the parent |
| 4 | OWD Private, user owns records only | `false` | Owned count, as a floor |
| 5 | OWD Private, owned + manual shares + rule shares | `false` | Deduplicated owned + shared, as a floor |
| 6 | OWD Private, access only via the role hierarchy | `false` | Floor **excludes** it — no share rows exist |
| 7 | Object with no name field | — | `hasNameField = false`, `searchSupported = false` |

### Structural invariants

- `totalRecords` is never used as the subject's reach. It is the running user's view.
- `totalReachable` comes from its own query and does not change with the page on screen.
- `isExact = false` implies the UI renders an at-least qualifier. A test that asserts the number
  without asserting the flag is not testing this subsystem.
- Reason buckets never sum above the floor.

Scenario 6 is the one to write first. It is the case where a tool that rounds up becomes dangerous,
because understating someone's access is how an access review passes something it should not.

---

## 4. LWC Tests

```powershell
npm run test:unit
npm run test:unit:watch
npm run test:unit:coverage
```

- Mock `@salesforce/apex/...` imports; never hit a real org from Jest.
- Assert rendered output, not internal component state.
- `peUtils` helpers (`urlState`, `cursorStack`, `accessLabels`, `errors`) are pure and should be
  tested directly — they are cheap, high-value tests.

---

## 5. Manual Test Script (pre-release)

1. Assign `PermissionCheckerPermissionSet`; confirm the app appears.
2. **Remove** the permission set; confirm every tab returns the "ask an administrator" message and
   no data is rendered.
3. Search users with and without filters; page forward and back; confirm the 200-row cap message.
4. Select a user with a permission set group containing a muting set; verify the amber
   granted-then-muted state renders and attribution names both the granting and the muting set.
5. Select a user with an outdated group; confirm the warning appears.
6. Walk an app → object → field table; confirm the "access without a tab" section populates.
7. Confirm formula, auto-number and system audit fields render as **not applicable with a reason**,
   not as "hidden".
8. Copy the URL, open it in a fresh tab, confirm the same view restores.
9. Trigger refresh; confirm data re-resolves.
10. Query `PE_Inspection_Log__c`; confirm one row per action, correct inspector and subject.
11. Attempt to edit and delete an inspection row as the inspector; both must be denied.
12. Open **Data Visibility** on a public-read object; confirm the figure is labelled exact.
13. Open it on a private object where the subject owns and is shared records; confirm the figure is
    labelled a floor, and that the reason breakdown shows more than one bucket.
14. Confirm the org total is presented as a denominator, never as the subject's reach.
15. Page the record list; confirm the footer total does not change with the page.
16. Open the **Inspection Log**; confirm the paging in step 15 produced one row per page, not one
    row for the session.
17. Confirm reading the log wrote **no** row of its own.
18. On **Home**, confirm each posture signal shows its remedy text, and that a signal that cannot
    compute reads *unavailable* rather than 0.
19. Run in an org with **no** Platform Cache allocation; confirm correct (slower) behaviour.

---

## 6. Definition of Done

- [ ] Apex tests pass; coverage ≥ 80% on changed classes
- [ ] Jest tests pass
- [ ] `npm run lint` clean
- [ ] `npm run scan` reports zero violations on the AppExchange and Security rulesets
- [ ] Any new figure that may be incomplete returns its basis, and the UI renders it
- [ ] No stray files under `force-app/`; every LWC bundle is complete
- [ ] Muting matrix passes if the resolver was touched
- [ ] Documentation updated in the same pull request
- [ ] No real user data in fixtures, screenshots or test payloads
