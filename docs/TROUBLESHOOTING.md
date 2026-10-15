# Troubleshooting

Platform constraints and errors already paid for once. Each entry exists because it cost real time.

---

## Deployment

### `<component> named in package.xml, but was not found in zip directory`

**Cause.** An incomplete LWC bundle. Salesforce requires the whole folder.
**Fix.** Deploy the bundle directory, not individual files. All four files travel together:
`.html`, `.js`, `.css`, `.js-meta.xml`.

```powershell
sf project deploy start --source-dir force-app/main/default/lwc/peFieldTable --target-org wsw-dev
```

### Deployed to the wrong org

**Cause.** `vscodeOrg` resolves to `saiful@momentum-worldwide.com`, an unrelated org.
**Fix.**

```powershell
sf config set target-org=wsw-dev
sf config get target-org --verbose
sf org display --target-org wsw-dev
```

Pass `--target-org wsw-dev` explicitly regardless.

### Unexplained parse errors in `.cls` or `-meta.xml`

**Cause.** A UTF-8 BOM, usually from PowerShell's `Set-Content` or `Out-File`.
**Fix.** Write with `[System.IO.File]::WriteAllText` and a `UTF8Encoding($false)` instance.

### A class named `Something (1).cls` appears in `force-app`

**Cause.** A browser download landed in the source folder and was committed. It has no
`-meta.xml` sidecar and its name is not a valid Apex identifier.
**Fix.** Delete it and commit. Nothing in Salesforce can consume it, and `sf project deploy` will
either fail or silently skip it, which is worse — you deploy the *other* copy and wonder why your
edit had no effect.

```powershell
git rm "force-app/main/default/classes/PEInspectionLogService (1).cls"
```

### A CSS-only or JS-only LWC bundle is rejected

**Cause.** A folder under `lwc/` containing, for example, only `.css` and `.js-meta.xml`.
Salesforce requires a `.js` and `.html` for a renderable component; a shared-stylesheet folder is
not a component.
**Fix.** Either give the bundle a real `.js` and `.html`, or move the stylesheet into the component
that imports it. Check before every build:

```powershell
Get-ChildItem force-app/main/default/lwc -Directory | Where-Object {
  -not (Test-Path "$($_.FullName)\$($_.Name).js")
}
```

### Static resource deploy fails

**Cause.** Missing `.resource-meta.xml` sidecar, or the file exceeds practical size limits.
**Fix.** Add the sidecar. Keep images under ~300 KB or convert to WebP.

### Permission set deploy: `editable=true` on a required field

**Cause.** Salesforce rejects editable-true for required fields.
**Fix.** Remove the `<editable>` element for that field, or target a non-required field.

---

## Apex Compilation

| Error | Cause | Fix |
| --- | --- | --- |
| Unexpected token `desc` / `where` | Both are Apex reserved words | Rename the identifier |
| `|=` not valid | Apex has no Boolean compound-OR assignment | `x = x \|\| y;` |
| `Schema.Layout` does not exist | It is not an Apex type. `Layout` is queryable via the REST Tooling/standard API but not from Apex | Out of scope; see limitations |
| `TabDefinition.IsCustom` invalid | The field does not exist | Infer from the tab name/type instead |
| `Metadata.MetadataType` limited | Supports only three types, none relevant here | Use `Metadata.Operations.retrieve` (0.6 work) |

---

## Runtime

### `System.StackOverflowError` from `PECacheManager`

**Cause.** A static property getter that reads its own property recurses forever.
**Fix.** Use a backing field plus an explicit `*Resolved` boolean — the pattern already in
`PECacheManager.getOrgPartition()`.

### `@AuraEnabled` returns null or serialisation fails

**Cause.** `List<Object>` is not serialisable across the Aura boundary.
**Fix.** Return a concrete type: `List<PEDto.Grant>`, never `List<Object>`.

### Stale or nonsensical cached results after a refactor

**Cause.** The cached object's shape changed but `CACHE_PREFIX` did not. The old payload
deserialises without error and silently loses fields.
**Fix.** Bump `CACHE_PREFIX` in `PEPermissionResolver`, then `refreshCache()` in the UI.

### Platform Cache errors on key names

**Cause.** Platform Cache keys must be alphanumeric.
**Fix.** Route every key through `PECacheManager.safeKey`.

### App works in one org, silently returns nothing in another

**Cause.** The Platform Cache partition is not allocated in that org, **or** the running user lacks
**View Setup and Configuration**, which permission-metadata objects require.
**Fix.** Allocate the partition; verify the administrator's own permissions.

### Explorer panel height wrong on some orgs

**Cause.** A hardcoded `calc(100vh - 8.5rem)` assumes a fixed header height.
**Fix.** Measure in `renderedCallback` with `getBoundingClientRect().top` and write to the
`--pe-explorer-h` custom property.

---

## Namespaces

### Dynamic SOQL works unmanaged, breaks in the managed package

**Cause.** Dynamic SOQL does not reliably prefix unqualified custom object or field identifiers
with the package namespace. `SELECT Action__c FROM PE_Inspection_Log__c` compiles in the dev org
and fails for a subscriber, where the names are `twinforce__Action__c` and
`twinforce__PE_Inspection_Log__c`.
**Fix.** Never write the names. Ask describe for them:

```apex
String objectName   = Schema.SObjectType.PE_Inspection_Log__c.getName();
String actionField  = Schema.SObjectType.PE_Inspection_Log__c.fields.Action__c.getName();
String inspectorRel = Schema.SObjectType.PE_Inspection_Log__c
                          .fields.Inspector_User__c.getRelationshipName();
```

Describe returns the fully qualified name in both contexts. This is why
`PEInspectionLogService` builds its query text rather than using four static SOQL variants.
See [adr/0012-namespace-safe-dynamic-soql.md](adr/0012-namespace-safe-dynamic-soql.md).

---

## Static Analysis

### Code Analyzer reports hundreds of findings

**Cause.** `--rule-selector all` was used. It pulls in rules that do not apply to a managed package.
**Fix.** Use the project script:

```powershell
npm run scan   # AppExchange + Recommended:Security, per code-analyzer.yml
```

### PMD flags every LWC JavaScript file

**Cause.** PMD's ECMAScript rules mis-handle modern LWC patterns.
**Fix.** Already handled — `code-analyzer.yml` disables the ESLint engine and empties PMD's
JavaScript extensions. LWC JS is linted by the project's own ESLint config. Do not re-enable it.

### `AvoidHardcodingId` fires in a test class

**Cause.** A literal 15- or 18-character Id in test data.
**Fix.** Generate one instead. The pattern used elsewhere in this codebase:

```apex
Id fakeId = Id.valueOf(
    String.valueOf(User.SObjectType.getDescribe().getKeyPrefix()) +
    '0'.repeat(12 - String.valueOf(counter).length()) + counter
);
```

The rule sits outside the AppExchange and Security rulesets, so it does not block a review — but
`npm run scan` is supposed to come back empty, and an expected finding trains everyone to ignore
the output.

### PMD ApexDoc rule flags a void method

**Cause.** A missing `@param` tag — not a missing `@return`.
**Fix.** Void methods need only `@param` tags. After adding ApexDoc, line numbers shift; compare
subsequent findings **by method name**, not by line number.

---

## Packaging

### `sf package version create` fails on ancestry

**Cause.** `ancestorVersion: HIGHEST` and the change removes or breaks a packaged component.
**Fix.** This is the guard working. Restore the component and deprecate it properly rather than
overriding ancestry.

### Version creation fails on coverage

**Cause.** Below the 75% managed-package floor.
**Fix.** Add tests. Re-run with `--code-coverage` and read the per-class breakdown.

---

## Adding to This File

If a platform behaviour costs you more than an hour, add it here in the same pull request. That is
the whole point of the document.
