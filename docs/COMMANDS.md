# Command Warehouse

Every command used across the Salesforce DX / 2GP / AppExchange lifecycle, grouped by task.
Copy, substitute the placeholders, run.

PowerShell line continuation is a backtick `` ` ``. On macOS/Linux use a backslash `\`.

| Placeholder | Meaning |
| --- | --- |
| `<DEVHUB_ALIAS>` | Dev Hub org alias |
| `<DEV_ALIAS>` | Development org alias |
| `<TEST_ALIAS>` | Package install-test org alias |
| `<PACKAGE_NAME>` | Package name from `sfdx-project.json` |
| `<PACKAGE_ID>` | `0Ho...` |
| `<VERSION_ID>` | `04t...` |
| `<VERSION>` | e.g. `1.2.0-1` |
| `<PERMSET_NAME>` | Packaged permission set API name |
| `<CLASS>` | Apex class name |
| `<BUNDLE>` | LWC bundle folder name |

---

## Contents

- [1 · CLI setup and diagnostics](#1--cli-setup-and-diagnostics)
- [2 · Authorisation and org management](#2--authorisation-and-org-management)
- [3 · Configuration and target pinning](#3--configuration-and-target-pinning)
- [4 · Scratch orgs](#4--scratch-orgs)
- [5 · Project and metadata generation](#5--project-and-metadata-generation)
- [6 · Deploy and retrieve](#6--deploy-and-retrieve)
- [7 · Source tracking](#7--source-tracking)
- [8 · Destructive changes](#8--destructive-changes)
- [9 · Permission sets and user setup](#9--permission-sets-and-user-setup)
- [10 · Data — query, import, export](#10--data--query-import-export)
- [11 · Apex — run, test, log](#11--apex--run-test-log)
- [12 · Node tooling — lint, format, Jest](#12--node-tooling--lint-format-jest)
- [13 · Static analysis](#13--static-analysis)
- [14 · Packaging — 2GP](#14--packaging--2gp)
- [15 · Package install and uninstall](#15--package-install-and-uninstall)
- [16 · Git](#16--git)
- [17 · PowerShell file handling](#17--powershell-file-handling)
- [18 · Sequences — full runs](#18--sequences--full-runs)

---

## 1 · CLI setup and diagnostics

```powershell
# Version and environment
sf --version
sf version --verbose

# Update the CLI
sf update

# Plugins
sf plugins
sf plugins install @salesforce/plugin-packaging
sf plugins install code-analyzer
sf plugins update

# Health check
sf doctor

# Help for any command
sf help
sf project deploy start --help
```

---

## 2 · Authorisation and org management

```powershell
# Log in (browser)
sf org login web --alias <DEV_ALIAS>
sf org login web --alias <DEVHUB_ALIAS> --set-default-dev-hub
sf org login web --alias <DEV_ALIAS> --set-default

# Sandbox login
sf org login web --alias my-sandbox --instance-url https://test.salesforce.com

# JWT login (CI)
sf org login jwt --username <USERNAME> --jwt-key-file server.key --client-id <CONSUMER_KEY> --alias ci-org

# SFDX auth URL login (CI) — file contains the URL, never commit it
sf org login sfdx-url --sfdx-url-file authurl.txt --alias ci-org

# List and inspect
sf org list
sf org list --all
sf org list --clean                     # remove expired scratch org authorisations
sf org display --target-org <DEV_ALIAS>
sf org display --target-org <DEV_ALIAS> --verbose   # includes the auth URL — treat as a secret

# Open
sf org open --target-org <DEV_ALIAS>
sf org open --target-org <DEV_ALIAS> --path lightning/setup/SetupOneHome/home
sf org open --target-org <DEV_ALIAS> --path lightning/n/<TAB_NAME>

# Aliases
sf alias list
sf alias set <DEV_ALIAS>=user@example.com
sf alias unset <DEV_ALIAS>

# Log out
sf org logout --target-org <DEV_ALIAS>
sf org logout --all
```

---

## 3 · Configuration and target pinning

```powershell
# Set (local to the project)
sf config set target-org=<DEV_ALIAS>
sf config set target-dev-hub=<DEVHUB_ALIAS>
sf config set org-api-version=62.0

# Set globally
sf config set target-org=<DEV_ALIAS> --global

# Read
sf config get target-org --verbose
sf config get target-dev-hub --verbose
sf config list

# Unset
sf config unset target-org
```

> Pin the target, **and** still pass `--target-org` explicitly on every deploy.

---

## 4 · Scratch orgs

```powershell
# Create
sf org create scratch --definition-file config/project-scratch-def.json `
  --alias scratch-1 --duration-days 7 --target-dev-hub <DEVHUB_ALIAS>

# Create and set as default, with a namespace
sf org create scratch --definition-file config/project-scratch-def.json `
  --alias scratch-1 --duration-days 30 --set-default --target-dev-hub <DEVHUB_ALIAS>

# No namespace (useful for testing unmanaged behaviour)
sf org create scratch --definition-file config/project-scratch-def.json `
  --alias scratch-nons --no-namespace --duration-days 7 --target-dev-hub <DEVHUB_ALIAS>

# Generate a password
sf org generate password --target-org scratch-1
sf org display --target-org scratch-1

# Delete
sf org delete scratch --target-org scratch-1 --no-prompt

# Active scratch org usage against your limits
sf org list limits --target-org <DEVHUB_ALIAS>
sf data query --query "SELECT Id, SignupUsername, ExpirationDate, Status FROM ActiveScratchOrg" --target-org <DEVHUB_ALIAS>

# Sandbox
sf org create sandbox --name dev1 --license-type Developer --target-org <PROD_ALIAS> --wait 60
sf org refresh sandbox --name dev1 --target-org <PROD_ALIAS>
```

---

## 5 · Project and metadata generation

```powershell
# New project
sf project generate --name my-project --template standard

# Apex
sf apex generate class --name <CLASS> --output-dir force-app/main/default/classes
sf apex generate trigger --name MyTrigger --sobject Account --output-dir force-app/main/default/triggers

# LWC / Aura
sf lightning generate component --name <BUNDLE> --type lwc --output-dir force-app/main/default/lwc
sf lightning generate component --name myCmp --type aura --output-dir force-app/main/default/aura

# Other
sf schema generate sobject --label "My Object"
sf schema generate field --label "My Field" --object force-app/main/default/objects/My_Object__c
sf org generate permissionset --name <PERMSET_NAME>
sf project generate manifest --source-dir force-app --name package
sf project generate manifest --from-org <DEV_ALIAS> --output-dir manifest
```

---

## 6 · Deploy and retrieve

```powershell
# Deploy everything
sf project deploy start --target-org <DEV_ALIAS>

# Deploy a directory or a single component
sf project deploy start --source-dir force-app/main/default/classes --target-org <DEV_ALIAS>
sf project deploy start --source-dir force-app/main/default/classes/<CLASS>.cls --target-org <DEV_ALIAS>
sf project deploy start --source-dir force-app/main/default/lwc/<BUNDLE> --target-org <DEV_ALIAS>

# Deploy by metadata type
sf project deploy start --metadata ApexClass --target-org <DEV_ALIAS>
sf project deploy start --metadata "ApexClass:<CLASS>" --target-org <DEV_ALIAS>
sf project deploy start --metadata LightningComponentBundle --target-org <DEV_ALIAS>

# Deploy from a manifest
sf project deploy start --manifest manifest/package.xml --target-org <DEV_ALIAS>

# Validate only (no commit) — required for production
sf project deploy start --source-dir force-app --dry-run --target-org <PROD_ALIAS>
sf project deploy validate --source-dir force-app --test-level RunLocalTests --target-org <PROD_ALIAS>
sf project deploy quick --job-id <JOB_ID> --target-org <PROD_ALIAS>

# Test levels
sf project deploy start --source-dir force-app --test-level NoTestRun --target-org <DEV_ALIAS>
sf project deploy start --source-dir force-app --test-level RunSpecifiedTests --tests <CLASS>Test --target-org <DEV_ALIAS>
sf project deploy start --source-dir force-app --test-level RunLocalTests --target-org <DEV_ALIAS>

# Ignore conflicts / force
sf project deploy start --source-dir force-app --ignore-conflicts --target-org <DEV_ALIAS>

# Monitor, resume, cancel
sf project deploy report --target-org <DEV_ALIAS>
sf project deploy resume --job-id <JOB_ID>
sf project deploy cancel --job-id <JOB_ID>

# Retrieve
sf project retrieve start --target-org <DEV_ALIAS>
sf project retrieve start --metadata "ApexClass:<CLASS>" --target-org <DEV_ALIAS>
sf project retrieve start --manifest manifest/package.xml --target-org <DEV_ALIAS>
sf project retrieve start --package-name "Some Managed Package" --target-org <DEV_ALIAS>
```

> **LWC bundles deploy whole.** Always target the bundle folder, never an individual file, or you get
> _"named in package.xml, but was not found in zip directory"_.

---

## 7 · Source tracking

```powershell
sf project retrieve preview --target-org <DEV_ALIAS>
sf project deploy preview --target-org <DEV_ALIAS>

# Reset tracking
sf project reset tracking --target-org <DEV_ALIAS>
sf project reset tracking --revision 0 --target-org <DEV_ALIAS>
```

---

## 8 · Destructive changes

`destructive/destructiveChanges.xml` plus an empty `destructive/package.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>ObsoleteClass</members>
        <name>ApexClass</name>
    </types>
    <version>62.0</version>
</Package>
```

```powershell
sf project deploy start `
  --metadata-dir destructive `
  --target-org <DEV_ALIAS> `
  --ignore-warnings

# Pre-destructive / post-destructive with a normal deploy
sf project deploy start `
  --manifest manifest/package.xml `
  --pre-destructive-changes destructive/destructiveChanges.xml `
  --target-org <DEV_ALIAS>
```

---

## 9 · Permission sets and user setup

```powershell
sf org assign permset --name <PERMSET_NAME> --target-org <DEV_ALIAS>
sf org assign permset --name <PERMSET_NAME> --on-behalf-of user@example.com --target-org <DEV_ALIAS>
sf org assign permsetlicense --name <PSL_NAME> --target-org <DEV_ALIAS>

# Create a test user from a definition file
sf org create user --definition-file config/user-def.json --set-alias testuser --target-org <DEV_ALIAS>
sf org create user --set-alias testuser2 profileName="Standard User" --target-org <DEV_ALIAS>

sf org list users --target-org <DEV_ALIAS>
```

---

## 10 · Data — query, import, export

```powershell
# Query
sf data query --query "SELECT Id, Name FROM Account LIMIT 10" --target-org <DEV_ALIAS>
sf data query --query "SELECT Id FROM ApexClass" --use-tooling-api --target-org <DEV_ALIAS>
sf data query --query "SELECT Id, Name FROM Account" --result-format csv --target-org <DEV_ALIAS> > accounts.csv
sf data query --query "SELECT Id FROM Account" --result-format json --target-org <DEV_ALIAS>

# Bulk query for large result sets
sf data query --query "SELECT Id, Name FROM Contact" --bulk --wait 10 --target-org <DEV_ALIAS>

# Single-record CRUD
sf data create record --sobject Account --values "Name='Acme' Industry='Technology'" --target-org <DEV_ALIAS>
sf data get record --sobject Account --record-id 001... --target-org <DEV_ALIAS>
sf data update record --sobject Account --record-id 001... --values "Industry='Finance'" --target-org <DEV_ALIAS>
sf data delete record --sobject Account --record-id 001... --target-org <DEV_ALIAS>

# Tree export / import (seed data)
sf data export tree --query "SELECT Id, Name FROM Account" --output-dir data --plan --target-org <DEV_ALIAS>
sf data import tree --plan data/Account-plan.json --target-org <DEV_ALIAS>

# Bulk CSV
sf data import bulk --file data/accounts.csv --sobject Account --wait 10 --target-org <DEV_ALIAS>
sf data export bulk --query "SELECT Id, Name FROM Account" --output-file out.csv --result-format csv --wait 10 --target-org <DEV_ALIAS>
sf data delete bulk --file data/ids.csv --sobject Account --wait 10 --target-org <DEV_ALIAS>
sf data upsert bulk --file data/accounts.csv --sobject Account --external-id Ext_Id__c --wait 10 --target-org <DEV_ALIAS>

# Resume a bulk job
sf data import resume --job-id <JOB_ID> --target-org <DEV_ALIAS>
```

---

## 11 · Apex — run, test, log

```powershell
# Anonymous Apex
sf apex run --file scripts/apex/script.apex --target-org <DEV_ALIAS>
sf apex run --target-org <DEV_ALIAS>          # reads from stdin

# Tests — all
sf apex run test --target-org <DEV_ALIAS> --code-coverage --result-format human --wait 20

# Tests — specific class / method / suite
sf apex run test --tests <CLASS>Test --target-org <DEV_ALIAS> --code-coverage --result-format human
sf apex run test --tests <CLASS>Test.myMethod --target-org <DEV_ALIAS>
sf apex run test --class-names <CLASS>Test --class-names OtherTest --target-org <DEV_ALIAS>
sf apex run test --suite-names MySuite --target-org <DEV_ALIAS>

# Test levels
sf apex run test --test-level RunLocalTests --target-org <DEV_ALIAS> --code-coverage --wait 30
sf apex run test --test-level RunAllTestsInOrg --target-org <DEV_ALIAS> --code-coverage --wait 60

# Machine-readable output for CI
sf apex run test --test-level RunLocalTests --code-coverage `
  --result-format junit --output-dir test-results --wait 30 --target-org <DEV_ALIAS>

sf apex get test --test-run-id <RUN_ID> --code-coverage --target-org <DEV_ALIAS>

# Logs
sf apex tail log --target-org <DEV_ALIAS>
sf apex tail log --color --target-org <DEV_ALIAS>
sf apex list log --target-org <DEV_ALIAS>
sf apex get log --log-id <LOG_ID> --target-org <DEV_ALIAS>
sf apex get log --number 5 --target-org <DEV_ALIAS>

# Trace flags / debug levels
sf apex list log --target-org <DEV_ALIAS>
```

### Coverage check by query

```powershell
sf data query --use-tooling-api --target-org <DEV_ALIAS> --query `
  "SELECT ApexClassOrTrigger.Name, NumLinesCovered, NumLinesUncovered FROM ApexCodeCoverageAggregate ORDER BY ApexClassOrTrigger.Name"
```

---

## 12 · Node tooling — lint, format, Jest

```powershell
npm install
npm ci                              # CI — exact lockfile install

npm run lint
npx eslint force-app --fix

npm run prettier
npm run prettier:verify
npx prettier --write "force-app/**/*.{cls,js,html,css,xml}"

npm run test:unit
npm run test:unit:watch
npm run test:unit:debug
npm run test:unit:coverage
npx sfdx-lwc-jest -- --findRelatedTests force-app/main/default/lwc/<BUNDLE>/<BUNDLE>.js

# Husky
npx husky init
npx lint-staged
```

---

## 13 · Static analysis

```powershell
# Install
sf plugins install code-analyzer

# The rulesets that mirror the AppExchange review
sf code-analyzer run `
  --workspace force-app `
  --rule-selector AppExchange `
  --rule-selector Recommended:Security `
  --output-file analyzer.html

# With a config file
sf code-analyzer run --workspace force-app --config-file code-analyzer.yml --output-file analyzer.html

# Detail view and multiple formats
sf code-analyzer run --workspace force-app --rule-selector Recommended --view detail --output-file analyzer.html
sf code-analyzer run --workspace force-app --output-file results.json --output-file results.csv

# Fail the build on severity
sf code-analyzer run --workspace force-app --rule-selector AppExchange --severity-threshold 3

# Inspect available rules
sf code-analyzer rules --rule-selector AppExchange
sf code-analyzer rules --rule-selector all --view detail

# Generate a starter config
sf code-analyzer config --output-file code-analyzer.yml
```

> Do **not** use `--rule-selector all` for review preparation — it buries real findings in noise.

---

## 14 · Packaging — 2GP

```powershell
# One-time: create the package
sf package create --name "<PACKAGE_NAME>" --package-type Managed --path force-app --target-dev-hub <DEVHUB_ALIAS>
sf package create --name "My Unlocked" --package-type Unlocked --path force-app --target-dev-hub <DEVHUB_ALIAS>

sf package list --target-dev-hub <DEVHUB_ALIAS>
sf package list --verbose --target-dev-hub <DEVHUB_ALIAS>

# Create a version
sf package version create `
  --package "<PACKAGE_NAME>" `
  --installation-key-bypass `
  --code-coverage `
  --wait 90 `
  --target-dev-hub <DEVHUB_ALIAS>

# With an installation key
sf package version create --package "<PACKAGE_NAME>" --installation-key "secret" --code-coverage --wait 90 --target-dev-hub <DEVHUB_ALIAS>

# Skip validation (faster, cannot be promoted)
sf package version create --package "<PACKAGE_NAME>" --installation-key-bypass --skip-validation --wait 90 --target-dev-hub <DEVHUB_ALIAS>

# From a specific branch / with a tag
sf package version create --package "<PACKAGE_NAME>" --branch main --tag v1.2.0 --installation-key-bypass --code-coverage --wait 90 --target-dev-hub <DEVHUB_ALIAS>

# Monitor
sf package version create report --package-create-request-id <08c...> --target-dev-hub <DEVHUB_ALIAS>
sf package version create list --target-dev-hub <DEVHUB_ALIAS>
sf package version create list --status Error --target-dev-hub <DEVHUB_ALIAS>

# List and inspect versions
sf package version list --packages "<PACKAGE_NAME>" --target-dev-hub <DEVHUB_ALIAS>
sf package version list --packages "<PACKAGE_NAME>" --verbose --target-dev-hub <DEVHUB_ALIAS>
sf package version list --released --target-dev-hub <DEVHUB_ALIAS>
sf package version report --package <VERSION_ID> --verbose --target-dev-hub <DEVHUB_ALIAS>

# Promote — IRREVERSIBLE
sf package version promote --package "<PACKAGE_NAME>@<VERSION>" --target-dev-hub <DEVHUB_ALIAS>
sf package version promote --package <VERSION_ID> --no-prompt --target-dev-hub <DEVHUB_ALIAS>

# Update metadata / delete a beta
sf package version update --package <VERSION_ID> --version-description "..." --target-dev-hub <DEVHUB_ALIAS>
sf package version delete --package <VERSION_ID> --target-dev-hub <DEVHUB_ALIAS>
sf package update --package "<PACKAGE_NAME>" --description "..." --target-dev-hub <DEVHUB_ALIAS>

# Installed packages in an org
sf package installed list --target-org <TEST_ALIAS>
```

### Version numbering in `sfdx-project.json`

```json
{
  "packageDirectories": [{
    "path": "force-app",
    "default": true,
    "package": "<PACKAGE_NAME>",
    "versionName": "Spring Release",
    "versionNumber": "1.2.0.NEXT",
    "ancestorVersion": "HIGHEST"
  }]
}
```

---

## 15 · Package install and uninstall

```powershell
sf package install --package <VERSION_ID> --target-org <TEST_ALIAS> --wait 20 --publish-wait 20
sf package install --package <VERSION_ID> --installation-key "secret" --target-org <TEST_ALIAS> --wait 20
sf package install --package <VERSION_ID> --no-prompt --security-type AdminsOnly --target-org <TEST_ALIAS> --wait 20
sf package install --package <VERSION_ID> --upgrade-type Mixed --target-org <TEST_ALIAS> --wait 20

sf package install report --request-id <0Hf...> --target-org <TEST_ALIAS>

sf package uninstall --package <VERSION_ID> --target-org <TEST_ALIAS> --wait 20
sf package uninstall report --request-id <06y...> --target-org <TEST_ALIAS>
```

Browser install URL:

```
https://login.salesforce.com/packaging/installPackage.apexp?p0=<VERSION_ID>
https://test.salesforce.com/packaging/installPackage.apexp?p0=<VERSION_ID>
```

---

## 16 · Git

```powershell
# Branch
git switch -c feat/short-description
git switch main
git pull --rebase origin main

# Stage, commit, push
git add -A
git status --porcelain
git commit -m "feat: imperative summary"
git push -u origin feat/short-description

# Tag a release
git tag -a v<VERSION> -m "<PACKAGE_NAME> <VERSION> (<VERSION_ID>)"
git push origin v<VERSION>
git tag -l

# Inspect
git log --oneline -20
git log --oneline --graph --all -20
git diff main...HEAD --stat
git show <SHA> --stat

# Remove a tracked file without deleting it locally
git rm --cached path/to/file
git rm -r force-app/main/default/lwc/<BUNDLE>

# Branch cleanup
git branch --merged main
git branch -d old-branch
git push origin --delete old-branch
git fetch --prune

# Find a committed secret
git log -p -S "sfdxAuthUrl" --all
git log --all --full-history -- "**/.env"

# Undo
git restore path/to/file
git restore --staged path/to/file
git reset --soft HEAD~1
git revert <SHA>
```

---

## 17 · PowerShell file handling

```powershell
# Write UTF-8 with NO BOM — the reliable way to author .cls and -meta.xml
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText("D:\project\force-app\main\default\classes\<CLASS>.cls", $content, $utf8NoBom)

# Read
$content = [System.IO.File]::ReadAllText("path\to\file.cls")

# Detect a BOM
Get-Content file.cls -Encoding Byte -TotalCount 3

# Search the tree
Select-String -Path force-app -Pattern "TODO" -Recurse
Select-String -Path force-app -Pattern "<BUNDLE>" -Recurse | Select-Object Path, LineNumber

# Find large files
Get-ChildItem -Recurse -File | Sort-Object Length -Descending | Select-Object -First 20 FullName, Length

# Strip CRLF from a file
(Get-Content file.xml -Raw) -replace "`r`n", "`n" | Set-Content file.xml -NoNewline

# Delete
Remove-Item analyzer-*.html -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force destructive
```

---

## 18 · Sequences — full runs

### First-time machine setup

```powershell
git clone <REPO_URL>
cd <REPO_FOLDER>
npm install
sf org login web --alias <DEVHUB_ALIAS> --set-default-dev-hub
sf org login web --alias <DEV_ALIAS> --set-default
sf config set target-org=<DEV_ALIAS>
sf config set target-dev-hub=<DEVHUB_ALIAS>
sf config get target-org --verbose
sf project deploy start --target-org <DEV_ALIAS>
sf org assign permset --name <PERMSET_NAME> --target-org <DEV_ALIAS>
sf org open --target-org <DEV_ALIAS>
```

### Daily change loop

```powershell
git switch -c fix/short-description
sf project deploy start --source-dir force-app --target-org <DEV_ALIAS>
npm run lint
npm run test:unit
sf apex run test --target-org <DEV_ALIAS> --code-coverage --result-format human
sf code-analyzer run --workspace force-app --rule-selector AppExchange --rule-selector Recommended:Security --output-file analyzer.html
git add -A
git commit -m "fix: ..."
git push -u origin fix/short-description
```

### Fresh scratch org from zero

```powershell
sf org create scratch --definition-file config/project-scratch-def.json --alias scratch-1 --duration-days 7 --target-dev-hub <DEVHUB_ALIAS>
sf project deploy start --target-org scratch-1
sf org assign permset --name <PERMSET_NAME> --target-org scratch-1
sf data import tree --plan data/sample-plan.json --target-org scratch-1
sf org generate password --target-org scratch-1
sf org open --target-org scratch-1
```

### Release a version

```powershell
# 1 · bump versionNumber / versionName in sfdx-project.json, update CHANGELOG.md
sf package version create --package "<PACKAGE_NAME>" --installation-key-bypass --code-coverage --wait 90 --target-dev-hub <DEVHUB_ALIAS>
sf package version list --packages "<PACKAGE_NAME>" --verbose --target-dev-hub <DEVHUB_ALIAS>

# 2 · install the prior released version, then upgrade to the new beta
sf package install --package <PRIOR_VERSION_ID> --target-org <TEST_ALIAS> --wait 20 --publish-wait 20
sf package install --package <VERSION_ID> --target-org <TEST_ALIAS> --wait 20 --publish-wait 20
sf org assign permset --name <PERMSET_NAME> --target-org <TEST_ALIAS>
sf org open --target-org <TEST_ALIAS>

# 3 · manual test passes → promote (IRREVERSIBLE)
sf package version promote --package "<PACKAGE_NAME>@<VERSION>" --target-dev-hub <DEVHUB_ALIAS>

# 4 · tag
git add sfdx-project.json CHANGELOG.md
git commit -m "chore: release <VERSION>"
git tag -a v<VERSION> -m "<PACKAGE_NAME> <VERSION> (<VERSION_ID>)"
git push origin main --tags
```

### CI pipeline body

```powershell
npm ci
sf org login sfdx-url --sfdx-url-file authurl.txt --alias ci-devhub --set-default-dev-hub
sf org create scratch --definition-file config/project-scratch-def.json --alias ci-scratch --duration-days 1 --set-default --target-dev-hub ci-devhub
sf project deploy start --target-org ci-scratch
sf org assign permset --name <PERMSET_NAME> --target-org ci-scratch
npm run lint
npm run test:unit
sf apex run test --target-org ci-scratch --test-level RunLocalTests --code-coverage --result-format junit --output-dir test-results --wait 30
sf code-analyzer run --workspace force-app --rule-selector AppExchange --rule-selector Recommended:Security --severity-threshold 3
sf org delete scratch --target-org ci-scratch --no-prompt
```

### Production deployment (validate then quick-deploy)

```powershell
sf project deploy validate --source-dir force-app --test-level RunLocalTests --target-org <PROD_ALIAS> --wait 60
# note the job id from the output
sf project deploy quick --job-id <JOB_ID> --target-org <PROD_ALIAS> --wait 60
```

---

## Never run

```powershell
sf org display --verbose          # prints the SFDX auth URL — never paste the output anywhere
```

Never commit: passwords, security tokens, access or refresh tokens, SFDX auth URLs, connected-app
consumer secrets, JWT private keys (`server.key`, `*.pem`).
