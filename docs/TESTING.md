# Testing

---

## 1. Layers

| Layer | Framework | Command |
| --- | --- | --- |
| Apex unit and integration | Salesforce test framework | `sf apex run test --target-org wsw-dev --code-coverage --result-format human` |
| LWC unit | Jest via `sfdx-lwc-jest` | `npm run test:unit` |
| Static analysis | Code Analyzer (PMD, SFGE) | `npm run scan` |
| Lint | ESLint | `npm run lint` |

**Current packaged state: 88% Apex coverage, 74 packaged tests passing.**

Salesforce requires 75% for a managed package version. Coverage is a floor, not a goal — the
resolver correctness matrix below matters more than the percentage.

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

### Conventions

- `@isTest` with `@TestSetup` for shared fixtures.
- `System.runAs` for every authorisation path — both granted and denied.
- Assert on **behaviour**, not row counts that shift with org configuration.
- Never assume seed data exists in the org; create fixtures.

---

## 3. The Muting Correctness Matrix

> **This matrix must pass before any release claims audit defensibility.** It is the product's core
> differentiator and its most likely silent failure.

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

### Fixture requirements

Building this fixture set requires, in the test org or scratch org:

- a profile,
- at least two standalone permission sets,
- two permission set groups,
- at least three component sets distributed across those groups,
- at least two muting permission sets.

> Salesforce rejects `editable=true` on required fields in permission sets. When seeding
> `FieldPermissions` fixtures, use non-required custom fields.

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
12. Run in an org with **no** Platform Cache allocation; confirm correct (slower) behaviour.

---

## 6. Definition of Done

- [ ] Apex tests pass; coverage ≥ 80% on changed classes
- [ ] Jest tests pass
- [ ] `npm run lint` clean
- [ ] `npm run scan` reports zero violations
- [ ] Muting matrix passes if the resolver was touched
- [ ] Documentation updated in the same pull request
- [ ] No real user data in fixtures, screenshots or test payloads
