# Documentation Patch — 0.6.0-2

Docs-only. **Nothing under `force-app/` is touched**, and no file in this patch changes product
behaviour.

Extract over the repository root. Do not copy `00_PATCH-NOTES.md` itself into the repo.

All files are UTF-8 without BOM, CRLF line endings, matching the existing tree.

---

## 1. Apply

```powershell
cd D:\Product\WhoSeesWhat\Who-Sees-What
git checkout -b docs/0.6-refresh
# extract the zip over the repo root, excluding 00_PATCH-NOTES.md
git status
git add -A
git commit -m "docs: bring documentation to 0.6 — Data Visibility, audit trail, roadmap, cleanup"
```

Then confirm nothing outside documentation moved:

```powershell
git diff --stat HEAD~1 -- force-app
# expect: no output
```

---

## 2. Files in this patch

### Updated (23)

| File | What changed |
| --- | --- |
| `README.md` | Badges, 0.6 features (Data Visibility, Home/posture, log viewer), architecture diagram, test figures, static-analysis table, limitations, roadmap, docs index |
| `CHANGELOG.md` | `0.6.0-1` and `0.6.0-2` sections added; `Unreleased → Outstanding` rewritten against the actual tree |
| `docs/README.md` | Index rebuilt; new "Start here" routes |
| `docs/ARCHITECTURE.md` | Status to 0.6; four new services in the layer map and component section; open-risk table — two risks closed, three new ones recorded |
| `docs/API-REFERENCE.md` | Six new methods documented; logging behaviour stated per method; rules 8–10 added to "Adding a Method" |
| `docs/DATA-MODEL.md` | Log read path; `EntityDefinition` and share objects; service-owned transport types; `postureV1`; retention sizing |
| `docs/PERMISSION-RESOLUTION.md` | §7 record-level row reframed; §8 states the matrix **passes** and explains what was wrong before |
| `docs/TESTING.md` | Test figures corrected; five new test classes; §3 status; **new §3b** record-reach correctness matrix; manual script extended to 19 steps |
| `docs/SECURITY-MODEL.md` | Record-reach and log-read sections; injection surface extended; honest static-analysis table; two checklist items |
| `docs/RELEASE-PROCESS.md` | Version facts; four pre-release checklist items including the stray-file and LWC-bundle checks |
| `docs/TROUBLESHOOTING.md` | New: stray `(1)` class, incomplete LWC bundle, **namespace section** on dynamic SOQL, `AvoidHardcodingId` |
| `docs/GLOSSARY.md` | Ten new terms — reach, exact vs floor, denominator, posture signal, and others |
| `docs/CLEANUP-CANDIDATES.md` | Re-reviewed 15 Oct; new blocking section A; report-duplication section B |
| `docs/adr/README.md` | Index extended to ADR-0012 |
| `docs/adr/0004-...md` | `resolvedV3` → `resolvedV4` |
| `docs/diagrams/README.md` | Index extended to diagram 15 |
| `docs/diagrams/05`, `07`, `10` | `resolvedV3` → `resolvedV4` |

### New (11)

| File | Why |
| --- | --- |
| `docs/RECORD-VISIBILITY.md` | Data Visibility is the largest subsystem added since 0.3 and had no document. Covers the four OWD cases, why a private-OWD figure is a floor, and the security posture a reviewer will ask about. |
| `docs/AUDIT-TRAIL.md` | What is logged, what deliberately is not, write and read paths, access posture, retention sizing. |
| `docs/ROADMAP.md` | The roadmap lived only as a README table. Adds blocking prerequisites, the unverified Metadata API questions for 0.7, and **features declined by design** so they stop being re-litigated. |
| `docs/UPGRADE-NOTES.md` | Written for the subscriber. Leads with the muting fix, which changes answers they may have acted on. |
| `docs/DEMO-ORG-SEED.md` | Closes the long-open reviewer-org blocker: twelve things the org must prove, a fictional cast, permission scaffolding, record seeding, build order, sign-off checklist. |
| `docs/LISTING-COPY.md` | The claim rule, the unresolved subtitle question, and which claims 0.6 now makes supportable. |
| `docs/adr/0009-record-reach-approximation.md` | Why reach is approximated and labelled rather than elevated or omitted. |
| `docs/adr/0010-inspection-log-read-path.md` | Why the log is readable and why reading it is not logged. |
| `docs/adr/0011-posture-signals-must-be-actionable.md` | Why a count without a remedy does not ship. |
| `docs/adr/0012-namespace-safe-dynamic-soql.md` | The `0.6.0-1` → `0.6.0-2` fix, generalised into a rule. |
| `docs/diagrams/14`, `15` | Record-reach branch; inspection-log read. |

---

## 3. Facts corrected

Each of these was wrong in the tree before this patch.

| Was | Now |
| --- | --- |
| `CACHE_PREFIX` documented as `resolvedV3` in 7 places | `resolvedV4`, matching `PEPermissionResolver` |
| "Muting matrix must pass before any release claims audit defensibility" | It passes — `PEMutingMatrixTest` |
| "`PE_Inspection_Log__c` has no in-product viewer" | It has one |
| "88% coverage, 74 packaged tests" presented as current | Recorded against `0.3.0-1`; 11 classes / 135 methods in source; re-measure at version create |
| README badge: "code analyzer — 0 violations" | Per-ruleset table; the full PMD ruleset has 1 finding |
| Release commands referencing `0.5.0-1` | `0.6.0-2` |
| ARCHITECTURE status "current as of version 0.5" | 0.6 |
| Record types "replaced in 0.6 via Metadata API" | 0.7 — it did not happen in 0.6 |

---

## 4. Decisions left to you

Flagged in the documents, not decided in them.

1. **The listing subtitle.** `docs/LISTING-COPY.md` §2 — 0.6 makes "Record Visibility Explorer"
   closer to true, but the call is yours and the reasoning should be recorded with a date.
2. **Scan reports.** `docs/CLEANUP-CANDIDATES.md` §B — keep committed evidence or gitignore it, but
   stale-committed-plus-current-untracked should not continue.
3. **Security review document sets.** Two full sets exist, in three formats each, disagreeing on
   test counts. Pick one before submission.
4. **`peBase`.** Complete the bundle or remove it — it is a packaged component, so removal needs a
   `destructiveChanges.xml` entry.

---

## 5. Not in this patch

`docs/COMMANDS.md`, `docs/PIPELINE.md`, `docs/DEVELOPER-GUIDE.md`,
`docs/SALESFORCE-ENVIRONMENTS.md`, `.github/CONTRIBUTING.md` and `.github/SECURITY.md` were reviewed
and are still accurate at 0.6. They are not included rather than being shipped unchanged.

`docs/security-review-docs/` and `docs/who-sees-what-security-review/` are untouched — see decision 3
above; editing either before you pick one would make the duplication worse.
