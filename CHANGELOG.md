# Changelog

All notable changes to **Who Sees What** are recorded here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows Salesforce 2GP `major.minor.patch.build`.

Package ID: `0HoOW00000000ZV0AY` · Namespace: `twinforce`

---

## [Unreleased]

### Added
- Documentation set extended for 0.6: `docs/RECORD-VISIBILITY.md`, `docs/AUDIT-TRAIL.md`,
  `docs/ROADMAP.md`, `docs/UPGRADE-NOTES.md`, `docs/DEMO-ORG-SEED.md`, `docs/LISTING-COPY.md`.
- Four Architecture Decision Records: ADR-0009 (record reach approximation), ADR-0010 (inspection
  log read path), ADR-0011 (posture signals must be actionable), ADR-0012 (namespace-safe dynamic
  SOQL).
- Two diagrams: `14-sequence-record-reach.md`, `15-inspection-log-read.md`.

### Changed
- `CACHE_PREFIX` references corrected throughout the documentation — the resolver cache namespace is
  `resolvedV4`, not `resolvedV3`.
- `docs/TESTING.md` §3 reworded: the muting matrix is executed, not pending.
- `docs/SECURITY-MODEL.md` extended with the record-reach and log-read paths, and with an honest
  static-analysis table.
- `README.md` roadmap, feature list, limitations and test figures brought to 0.6.

### Outstanding
- **`force-app/main/default/classes/PEInspectionLogService (1).cls`** — a committed browser-download
  duplicate with no `-meta.xml` sidecar. Must be deleted before the next version create.
- **`force-app/main/default/lwc/peBase/`** — CSS and `.js-meta.xml` only, no `.js` or `.html`.
  Salesforce rejects a bundle in this shape.
- One PMD finding: `AvoidHardcodingId`, severity 3, `PEInspectionLogServiceTest` line 390. Outside
  the AppExchange and Security rulesets, so not review-blocking, but `npm run scan` should come back
  empty.
- `code-analyzer-reports/` is committed evidence from 28 September (0.5-era). The current scans are
  untracked at the repository root. Re-run and commit one authoritative set.
- `peGettingStarted` remains unreferenced; `destructive-p3/destructiveChanges.xml` still deprecates
  only `peObjectTable` and `peObjectRow`.
- Checkmarx scan `a0OKX000001JPnJ2AW` predates 0.4. Re-run before resubmission.
- Security review org not yet provisioned with fictional seeded data — see
  [`docs/DEMO-ORG-SEED.md`](docs/DEMO-ORG-SEED.md).
- Record type catalogue is org-wide, not per-user. Deferred to 0.7.

---

## [0.6.0-2] — Beta 6
**Version ID:** `04tOW00000KhHJtYAN` · **Status:** Beta

### Fixed
- `PEInspectionLogService` now builds its query text from `Schema.SObjectType` rather than literal
  identifiers. Dynamic SOQL does not reliably namespace-qualify unqualified custom object and field
  names, so the four static query variants that worked unmanaged would have failed for a subscriber,
  where the names carry the `twinforce__` prefix. See ADR-0012.

---

## [0.6.0-1] — Beta 6
**Version ID:** `04tOW00000Kh4mRYAR` · **Status:** Beta

### Added
- **Data Visibility.** A new tab answering how many records of an object a user reaches, and why.
  - `PERecordAccessService` — reach figures with an explicit basis for each: org-wide default from
    `EntityDefinition`, records owned, records shared, and whether the total is **exact** or a
    **floor**. Exact when the OWD is public or the user holds View All; a floor otherwise, because
    role-hierarchy access produces no share rows to count.
  - `PERecordListService` — one page of records with the subject's access to each, a reason
    breakdown grouped by share cause, and a true total sourced from its own query rather than from
    whichever page is on screen.
  - `peRecordAccessPanel`, `peRecordTable`, `dataVisibility` components.
- **Inspection Log viewer.** `PEInspectionLogService` and `peInspectionLog`. The audit trail has been
  append-only and invisible since it was introduced; a trail nobody can read defends nothing.
  Surfaces recent inspections, activity over the window, busiest inspectors, and filters by inspector
  or subject. Reading the log is gated but deliberately **not** logged.
- **Home.** New `WSW_Home` tab and `peHome` component, now the app's landing page.
  - `PEPostureService` — org-level signals that each come with a remedy: groups awaiting
    recalculation, users holding View All Data or Modify All Data, active users who have never signed
    in, permission sets assigned to nobody. Each query is independently caught; a failed signal
    renders as *unavailable*, never as zero.
  - `PEOrgStatsService` moved here from Permission Explorer and cached org-wide.
- **`PEMutingMatrixTest`.** The ten-scenario correctness matrix from `docs/TESTING.md` §3, executed
  against synthetic Ids with no DML, no SOQL and no org fixtures, so it runs in any org including a
  reviewer's.
- `PEAppVisibilityService` extracted as the app column's data source, with its `AppMenuItem`
  resolution mode disclosed as an estimate rather than presented as fact.
- New test classes: `PERecordAccessServiceTest`, `PERecordListServiceTest`, `PEPostureServiceTest`,
  `PEInspectionLogServiceTest`.

### Fixed
- **Muting scope.** Muting was stored as one flat set with no record of which group each muting set
  belonged to, so scenarios 5, 6 and 8 of the correctness matrix all reported *no access* for users
  who genuinely held the permission. Muting is now scoped to its own group, matching platform
  behaviour. This is the product's core differentiator and was silently wrong.

### Changed
- `CACHE_PREFIX` bumped `resolvedV3` → `resolvedV4` for the new `Resolved` shape.
- `versionName` to Beta 6, `versionNumber` to `0.6.0.NEXT`.
- Community files moved to `.github/`; generated artefacts removed from the tree.

---

## [0.5.0-1] — Beta 5
**Version ID:** `04tOW00000JbggTYAR` · **Status:** Beta

### Added
- License Inspector: user licenses, permission set licenses, package licenses and usage entitlements,
  with per-license user drill-down.
- Access trace — explain-this-access view for a single permission.
- Org stats bar.

### Changed
- `versionName` to Beta 5, `versionNumber` to `0.5.0.NEXT`.
- PMD suppressions and report timestamps adjusted.

---

## [0.4.0-1]
**Version ID:** `04tOW00000JV2sKYAT` · **Status:** Beta

### Changed
- Complete UI redesign. Moved from the dark pine-green brand to enterprise blue (`#1b4db1`,
  deliberately one step darker than SLDS `#0176D3`).
- Three-column WHO | WHERE | WHAT layout with staged accordion navigation: WHO opens first and
  collapses on selection; WHERE splits into app picker and object list; WHAT is terminal and does not
  auto-collapse.
- Typography: Space Grotesk for headings, IBM Plex Sans for body, IBM Plex Mono for data.
- Signal colours standardised — grant `#1F8A6B`, deny `#C0483C`, muted `#B4801F`, not applicable
  `#B4B0A8`.

### Fixed
- Explorer panel height. Replaced hardcoded `calc(100vh - 8.5rem)` with a JS-measured approach using
  `renderedCallback` and `getBoundingClientRect().top`, written to the `--pe-explorer-h` custom
  property. The previous value assumed a fixed header height and broke in orgs with a different one.

---

## [0.3.0-1] — Released
**Version ID:** `04tOW00000Gs9l8YAB` · **Status:** **Promoted / Released**

- 88% Apex coverage, 74 packaged tests passing.
- Checkmarx scan `a0OKX000001JPnJ2AW`: 0 security, 0 quality issues.
- Code Analyzer: 0 violations on the AppExchange and Security rulesets.
- First version submitted toward AppExchange security review.

---

## [0.2.0-1 … 0.2.0-6]
**Version IDs:** `04tOW00000GeDdJYAV`, `04tOW00000GptCgYAJ`, `04tOW00000GqhAyYAJ`,
`04tOW00000GrR7JYAV`, `04tOW00000GrRYkYAN`, `04tOW00000GqxSfYAJ`

- Iterative beta cycle: permission resolution hardening, muting permission set handling, keyset
  pagination, Platform Cache introduction, Code Analyzer and PMD remediation.
- `peObjectTable` and `peObjectRow` deprecated (see `destructive-p3/destructiveChanges.xml`).

---

## [0.1.0-1]
**Version ID:** `04tOW00000GeUz5YAF`

- Initial package version. Permission Explorer with user search, permission resolution and object/
  field access display.

---

## Maintaining this file

- Add an entry in the **same pull request** as the change.
- On release, move `Unreleased` items into a new version section and record the `04t` ID.
- Note anything a subscriber must do on upgrade, and mirror it in
  [`docs/UPGRADE-NOTES.md`](docs/UPGRADE-NOTES.md).
- An entry that only names a class is not an entry. Say what changed and why it mattered.
