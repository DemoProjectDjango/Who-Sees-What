# Developer Guide

Setting up a machine and working day to day on Who Sees What.

---

## 1. Prerequisites

| Tool | Version | Check |
| --- | --- | --- |
| Node.js | 18+ | `node --version` |
| npm | 9+ | `npm --version` |
| Salesforce CLI | latest | `sf --version` |
| Git | any recent | `git --version` |
| VS Code + Salesforce Extension Pack | latest | — |

Access required: the `WSWDevHub` Dev Hub and the `wsw-dev` development org. See
[SALESFORCE-ENVIRONMENTS.md](SALESFORCE-ENVIRONMENTS.md).

---

## 2. First-Time Setup

```powershell
git clone https://github.com/DemoProjectDjango/Who-Sees-What.git
cd Who-Sees-What
npm install

# Authorise orgs
sf org login web --alias WSWDevHub --set-default-dev-hub
sf org login web --alias wsw-dev --set-default

# Pin targets so a stray deploy cannot reach an unrelated org
sf config set target-org=wsw-dev
sf config set target-dev-hub=WSWDevHub
sf config get target-org --verbose

# Deploy and open
sf project deploy start --target-org wsw-dev
sf org assign permset --name PermissionCheckerPermissionSet --target-org wsw-dev
sf org open --target-org wsw-dev
```

> **Do this.** `vscodeOrg` resolves to `saiful@momentum-worldwide.com`, an unrelated org. Deploying
> there has happened before. Pin the target and pass `--target-org wsw-dev` explicitly anyway.

Then allocate Platform Cache in the org (Setup → Platform Cache → `PermissionExplorer` partition:
2 MB org, 1 MB session). The app works without it, just slower.

---

## 3. Daily Loop

```powershell
git switch -c fix/short-description

# ... edit ...

npm run lint
npm run prettier
sf project deploy start --target-org wsw-dev
sf apex run test --target-org wsw-dev --code-coverage --result-format human
npm run test:unit
npm run scan

git add -A
git commit -m "fix: describe the change"
git push -u origin fix/short-description
```

The Husky `pre-commit` hook runs `lint-staged`: Prettier on changed files, ESLint on changed LWC
JavaScript, related Jest tests with `--bail --findRelatedTests --passWithNoTests`.

### Deploying a single component

```powershell
sf project deploy start --source-dir force-app/main/default/classes/PEPermissionResolver.cls --target-org wsw-dev
sf project deploy start --source-dir force-app/main/default/lwc/peFieldTable --target-org wsw-dev
```

**LWC bundles deploy whole or not at all.** Always point at the bundle *folder*, never at individual
files. Shipping only the changed `.js` produces:

```
Error: <component> named in package.xml, but was not found in zip directory
```

All four files — `.html`, `.js`, `.css`, `.js-meta.xml` — must travel together.

---

## 4. Writing Files on Windows

Encoding matters. Prefer:

```powershell
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText("D:\Product\PermissionChecker\PermissionChecker\force-app\main\default\classes\PEExample.cls", $content, $utf8NoBom)
```

`Set-Content` and `Out-File` add a BOM by default; a BOM in a `.cls` or `-meta.xml` file causes
deployment errors that read as unrelated parse failures.

---

## 5. Coding Conventions

### Apex

- Prefix every class `PE` except `PermissionExplorer*`.
- Declare `with sharing`. No exceptions.
- Use `WITH USER_MODE` on user-facing queries.
- Bind all variables. Compose dynamic SOQL from constant fragments only.
- Return typed DTOs. `List<Object>` is not serialisable via `@AuraEnabled`.
- ApexDoc on every public method. Under PMD's ApexDoc rule, **void methods need only `@param`
  tags — no `@return`.**
- Reserved words to avoid as identifiers: `desc`, `where`.
- `|=` is not valid for Apex Booleans. Write `x = x || y;`.
- Never write a static property getter that reads its own property — infinite recursion. Use an
  explicit `*Resolved` boolean, as `PECacheManager` does.

### LWC

- Component folder names use the `pe` prefix; markup uses `<c-pe-…>`.
- Shared styles live in `peBase` and are pulled in with `@import 'c/peBase';`. `peBase` is a
  CSS-only bundle — it has no `.js` or `.html` by design.
- Keep Apex imports confined to `PermissionExplorerController`.
- Shared helpers live in `peUtils/` (`accessLabels`, `constants`, `cursorStack`, `errors`,
  `urlState`).
- Measure layout heights in `renderedCallback` via `getBoundingClientRect().top` and write the result
  to the `--pe-explorer-h` custom property. Hardcoded `calc(100vh - …)` values break on orgs with a
  different header height.

### Caching

- Bump `CACHE_PREFIX` in `PEPermissionResolver` whenever the shape of a cached object changes.
- Sanitise every key through `PECacheManager.safeKey` — Platform Cache keys are alphanumeric only.

---

## 6. Static Resources

- Keep each image under roughly 300 KB, or use WebP.
- Every static resource needs its `.resource-meta.xml` sidecar or deployment fails.
- Images shipped in the package must contain **fictional data only**.

---

## 7. Scratch Orgs

```powershell
sf org create scratch --definition-file config/project-scratch-def.json --alias wsw-scratch --duration-days 7 --target-dev-hub WSWDevHub
sf project deploy start --target-org wsw-scratch
sf org assign permset --name PermissionCheckerPermissionSet --target-org wsw-scratch
sf org list --clean   # remove expired authorisations
```

---

## 8. Branching and Commits

| Prefix | Use |
| --- | --- |
| `feat/` | New capability |
| `fix/` | Defect fix |
| `style/` | UI, CSS, copy |
| `docs/` | Documentation only |
| `chore/` | Tooling, dependencies, cleanup |
| `refactor/` | Behaviour-preserving restructure |

Commits follow Conventional Commits: `type: imperative summary`. See
[`../CONTRIBUTING.md`](../CONTRIBUTING.md).

---

## 9. Working Practice

- **Analysis before implementation.** Feasibility and design discussion precede code. A Salesforce
  platform constraint discovered after implementation is expensive; discovered before, it is free.
- **Complete file replacements, not partial diffs.** Whole files, always.
- **Scope discipline.** When a workstream is narrowed, excluded material stays excluded.
- **Record the platform lessons.** If a constraint costs you an afternoon, it goes in
  [TROUBLESHOOTING.md](TROUBLESHOOTING.md) so it costs nobody else one.
