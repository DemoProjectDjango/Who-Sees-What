# Changelog

All notable changes to **Who Sees What** are recorded here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows Salesforce 2GP `major.minor.patch.build`.

Package ID: `0HoOW00000000ZV0AY` · Namespace: `twinforce`

---

## [Unreleased]

### Added
- Full documentation set under `docs/`: architecture, permission resolution, data model, security
  model, API reference, developer guide, testing strategy, release process, troubleshooting and
  glossary.
- Eight Architecture Decision Records under `docs/adr/`.
- Thirteen diagrams under `docs/diagrams/` (C4 context/container/component, LWC tree, sequences, ERD,
  state machine, caching, deployment topology, release pipeline, trust boundaries).
- `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`.

### Changed
- `README.md` replaced — was the stock Salesforce DX template.
- `docs/SALESFORCE-ENVIRONMENTS.md` extended with the GitHub repository and account, Dev Hub details,
  the full org inventory and the wrong-org deploy hazard.
- `.gitignore` de-duplicated.

### Outstanding
- Muting permission set correctness matrix not yet fully verified. Until it passes, the product must
  not claim audit defensibility in listing copy. See `docs/TESTING.md` §3.
- `PE_Inspection_Log__c` has no in-product viewer.
- Record type catalogue is org-wide, not per-user.
- Security review org not yet provisioned with fictional seeded data.

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
- On release, move `Unreleased` items into a new dated version section and record the `04t` ID.
- Note anything a subscriber must do on upgrade.
