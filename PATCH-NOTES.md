# Patch Contents

Apply by copying these files over your working tree at
`D:\Product\PermissionChecker\PermissionChecker`, preserving the folder structure.

Every file here is either **new** or a **complete replacement**. No partial diffs.

## Replaces existing files

| Path | Note |
| --- | --- |
| `README.md` | Was the stock Salesforce DX template. Fully rewritten. |
| `docs/SALESFORCE-ENVIRONMENTS.md` | Extended, not rewritten — all original content retained. |
| `.gitignore` | De-duplicated. Same effective rules plus `.env.*`, `*.key`, `*.pem`. Review before applying. |

## New files

```
CHANGELOG.md
CONTRIBUTING.md
SECURITY.md
PATCH-NOTES.md                        (this file — delete after applying)

docs/README.md                        documentation index
docs/ARCHITECTURE.md
docs/PERMISSION-RESOLUTION.md
docs/DATA-MODEL.md
docs/SECURITY-MODEL.md
docs/API-REFERENCE.md
docs/DEVELOPER-GUIDE.md
docs/TESTING.md
docs/RELEASE-PROCESS.md
docs/TROUBLESHOOTING.md
docs/GLOSSARY.md
docs/CLEANUP-CANDIDATES.md            answers "what can I delete?"

docs/adr/README.md
docs/adr/0001-read-only-no-callouts.md
docs/adr/0002-custom-permission-gate-and-audit.md
docs/adr/0003-muting-permission-set-subtraction.md
docs/adr/0004-platform-cache-with-version-token.md
docs/adr/0005-keyset-pagination.md
docs/adr/0006-single-auraenabled-controller.md
docs/adr/0007-defer-record-types-to-metadata-api.md
docs/adr/0008-2gp-shared-namespace.md

docs/diagrams/README.md
docs/diagrams/01-c4-context.md
docs/diagrams/02-c4-container.md
docs/diagrams/03-c4-component-apex.md
docs/diagrams/04-lwc-component-tree.md
docs/diagrams/05-sequence-resolve-user.md
docs/diagrams/06-sequence-object-detail.md
docs/diagrams/07-permission-resolution-flow.md
docs/diagrams/08-entity-relationship.md
docs/diagrams/09-ui-state-machine.md
docs/diagrams/10-caching-dataflow.md
docs/diagrams/11-deployment-topology.md
docs/diagrams/12-release-pipeline.md
docs/diagrams/13-security-trust-boundaries.md
```

## Nothing under `force-app/` is touched

No Apex, no LWC, no metadata. This patch is documentation only and cannot affect a deployment.

## Applying

```powershell
cd D:\Product\PermissionChecker\PermissionChecker
git switch -c docs/documentation-overhaul

# extract the patch zip over the project root, then
Remove-Item PATCH-NOTES.md
git add -A
git status          # confirm only docs, README, CHANGELOG, CONTRIBUTING, SECURITY, .gitignore
git commit -m "docs: add architecture documentation, ADRs and diagrams"
git push -u origin docs/documentation-overhaul
```

## Verifying the diagrams

All thirteen diagrams are Mermaid inside Markdown. GitHub renders them on push. To check locally,
use the Markdown Preview Mermaid Support extension in VS Code, or paste a block into
<https://mermaid.live>.

## Two things to correct before committing

1. `docs/SALESFORCE-ENVIRONMENTS.md` §7 — the security review org rows are placeholders.
2. `CHANGELOG.md` — the 0.1 and 0.2 entries were reconstructed from `packageAliases` and commit
   history, not from release notes. Correct them against your own records.
