# Cleanup Candidates

Files and folders present in the working tree that are no longer needed, or that should not be there
at all. **Reviewed 15 October 2026** against `update/v6.1` at `0.6.0-2`.

Each entry states whether it is **tracked in Git** — that determines whether removing it needs a
commit or just a local delete.

---

## A. Blocking — fix before the next version create

These are not tidiness. Each one breaks or distorts a build.

| Path | Tracked | Why it must go |
| --- | --- | --- |
| `force-app/main/default/classes/PEInspectionLogService (1).cls` | **Yes** | A browser-download duplicate, committed. It is the **older** copy — pre-dating the namespace-safe dynamic SOQL fix — and has **no `-meta.xml` sidecar**. `(1)` is not a valid Apex identifier. The deploy either fails or silently skips it, which is the worse outcome: you ship the other copy and cannot explain why an edit had no effect. |
| `force-app/main/default/lwc/peBase/` | **Yes** | Contains `peBase.css` and `peBase.js-meta.xml` only — no `.js`, no `.html`. Salesforce rejects a bundle in this shape. If it is a shared stylesheet, it is not a component; move the CSS into whichever component imports it, or give the bundle a real `.js` and `.html`. |

```powershell
git rm "force-app/main/default/classes/PEInspectionLogService (1).cls"
```

> **Before touching `peBase`**, confirm who imports it, because it *is* a packaged component and
> `ancestorVersion: HIGHEST` will not let a version drop it without a deprecation path:
> ```powershell
> Select-String -Path force-app -Pattern "peBase|pe-base" -Recurse
> ```
> If it is imported anywhere, completing the bundle is the correct fix, not deleting it.

A standing check worth adding to the pre-release routine:

```powershell
# Any LWC folder without a matching .js
Get-ChildItem force-app/main/default/lwc -Directory | Where-Object {
  -not (Test-Path "$($_.FullName)\$($_.Name).js"
)}

# Any .cls without its sidecar
Get-ChildItem force-app/main/default/classes -Filter *.cls | Where-Object {
  -not (Test-Path "$($_.FullName)-meta.xml")
}
```

---

## B. Generated reports — pick one source of truth

The repository currently holds **two** sets of scan output, and the committed one is the stale one.

| Path | Tracked | Dated | Note |
| --- | --- | --- | --- |
| `code-analyzer-reports/` (5 files) | **Yes** | 28 Sep 2026 | 0.5-era. Reports 0 violations, which is no longer the full picture. |
| `analyzer-full.html` | No (gitignored) | 14 Oct 2026 | Current |
| `code-analyzer-full.html` | No (gitignored) | 14 Oct 2026 | Current. **Different content from `analyzer-full.html` despite the identical byte size** — two runs, not a copy. |
| `code-analyzer-security.html` | No (gitignored) | 14 Oct 2026 | Current, 0 violations |
| `code-analyzer-pmd.html` | No (gitignored) | 14 Oct 2026 | Current, **1 violation** — `AvoidHardcodingId` in `PEInspectionLogServiceTest` |

**Decide one way and apply it:**

- *Keep evidence* — re-run after fixing section A, commit **one** HTML per ruleset into
  `code-analyzer-reports/`, and delete the root-level files. The evidence trail has real value at
  security review.
- *Keep none* — delete `code-analyzer-reports/` and gitignore it. Regenerate on demand with
  `npm run scan`.

What should not continue is the current state: stale committed evidence alongside current untracked
output, with no way for a reader to tell which is authoritative.

```powershell
Remove-Item analyzer-full.html, code-analyzer-full.html, code-analyzer-security.html, code-analyzer-pmd.html -ErrorAction SilentlyContinue
```

---

## C. Delete — safe, no dependants

| Path | Tracked | Why it can go |
| --- | --- | --- |
| `force-app/main/default/lwc/peGettingStarted/` | **Yes** | Still unreferenced, as at the September review. The `Getting_Started` tab points at `gettingStarted`, not this. |
| `force-app/main/default/lwc/peCrudStrip/` | **Yes** | Superseded by `peCrudChips`. **One caveat:** `peRecordAccessPanel.css` now matches on the string — confirm whether that is a CSS class name coincidence or a real dependency before removing. |
| `destructive/` | No (gitignored) | Byte-identical to `destructive-p3/` apart from line endings and a BOM. Keep `destructive-p3/` (tracked). |
| `braces.json`, `braces-worklist.txt` | No (gitignored) | Artefacts of a one-off brace-balancing exercise. |

```powershell
Select-String -Path force-app -Pattern "peCrudStrip|pe-crud-strip|peGettingStarted|pe-getting-started" -Recurse
```

If either appears anywhere other than its own folder and the CSS match noted above, stop and
investigate.

**Both are packaged components.** Under `ancestorVersion: HIGHEST` a version cannot simply drop them.
Add them to `destructive-p3/destructiveChanges.xml`, which currently deprecates only `peObjectTable`
and `peObjectRow`:

```xml
<types>
    <members>peObjectTable</members>
    <members>peObjectRow</members>
    <members>peGettingStarted</members>
    <members>peCrudStrip</members>
    <n>LightningComponentBundle</n>
</types>
```

---

## D. Decide — reasonable either way

| Path | Tracked | Consideration |
| --- | --- | --- |
| `scripts/apex/hello.apex` | **Yes** | Default SFDX scaffolding. The "Enter_your_name_here" template, not a real script. |
| `scripts/soql/account.soql` | **Yes** | Queries `Account`, which this product never touches. |
| `docs/security-review-docs/` and `docs/who-sees-what-security-review/` | **Yes** | **Two** security-review document sets, each in markdown + docx + pdf. The older cites 74 tests, the newer 101. Three formats × two sets is six copies of a document that must be internally consistent at submission. Keep one set, keep markdown as the source, and generate docx/pdf at submission time rather than committing them. |
| Merged branches: `apexdoc`, `style/imtiaz-update`, `update/css`, `fix/0.4.1-update`, `update/v6` | — | All merged. `update/v6.1` is level with `origin/main`. Delete locally and on the remote. |

The duplicated security-review sets are the item most likely to cause an actual problem: submitting
the wrong one, or submitting two that contradict each other on test counts, is a self-inflicted
review delay.

---

## E. Already done since the September review

Recorded so nobody re-opens them.

- Community files moved to `.github/` — done.
- `CodeAnalyzerReport.html` removed from the tree — done.
- `README.md` replaced; `.gitignore` de-duplicated — done.

---

## Reviewing this file

Re-run the review at every minor version. An entry that survives two reviews is either load-bearing
and should be explained rather than listed, or nobody owns it — say which.
