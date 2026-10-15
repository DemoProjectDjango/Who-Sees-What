# Upgrade Notes

What a subscriber administrator has to do after installing a new version. One section per version
that requires anything; silence means a clean upgrade.

Internal release mechanics live in [RELEASE-PROCESS.md](RELEASE-PROCESS.md). This document is written
for the person on the receiving end.

---

## Upgrading to 0.6.x

**From:** `0.3.0-1` (the promoted version) or any 0.4 / 0.5 beta.

### Required

Nothing. The upgrade is additive — one new tab, three new tabs' worth of components, no schema
change to existing fields, no data migration.

### Recommended, in order

1. **Reassign the permission set, or confirm its new tabs.**
   `PermissionCheckerPermissionSet` now grants three further tabs: `WSW_Home`, `Data_Visibility` and
   `License_Inspector`. An upgrade applies the packaged permission set's new settings
   automatically — but if your org **cloned** it instead of assigning it directly, the clone will not
   pick them up. Check:

   ```
   Setup → Permission Sets → <your set> → Object Settings → Tab Settings
   ```

2. **Expect a slower first load per user.** `CACHE_PREFIX` moved from `resolvedV3` to `resolvedV4`,
   so every cached permission graph is invalidated by the upgrade. The first resolution for each user
   re-queries; subsequent ones are cached as before. Nothing to do — just do not read it as a
   regression.

3. **Allocate Platform Cache if you have not.** The product works without it and falls back to a
   request-scoped map, but Data Visibility is the most query-heavy part of the product to date, so
   the difference is more visible than it was. A small org partition is enough.

   ```
   Setup → Platform Cache → Partition: PermissionExplorer
   ```

4. **Decide your retention position on `PE_Inspection_Log__c`.** The log is now visible in-product,
   which usually prompts the question for the first time. The package never prunes it and ships no
   Delete permission. If you want a retention limit, you need your own scheduled job and your own
   permission set granting Delete. See [AUDIT-TRAIL.md](AUDIT-TRAIL.md) §7.

### Behaviour that changes

| Change | What you will notice |
| --- | --- |
| **Muting is now scoped to its own group** | Users who were previously reported as *not having* a permission may now correctly show as having it. This is a **fix**, not a regression. Before 0.6, a permission granted directly, or by a profile, or by a different group, could be wrongly suppressed by an unrelated group's muting set. If you made an access decision based on a pre-0.6 muting result, re-check it. |
| **Home is now the landing tab** | The app opens on `WSW_Home` rather than Permission Explorer. The explorer is one click away and unchanged. |
| **Org stats moved to Home** | The stats bar is no longer on Permission Explorer. |
| **App column is labelled an estimate** | Per-permission-set app visibility has no queryable source; the column resolves from `AppMenuItem` and now says so rather than implying precision it does not have. |

> The muting fix is the one item here worth escalating internally. It silently affected the
> product's core differentiator in versions up to and including 0.5.

### Not in this version

- Per-user record type and page layout visibility — the record type catalogue is still org-wide and
  labelled as such. Planned for 0.7.
- Inspection Log export. Planned for 0.7. The object is queryable today with a report or the Data
  Loader.

---

## Upgrading to 0.5.x

No action required. Additive: License Inspector tab, access trace, org stats bar.

---

## Upgrading to 0.4.x

No action required. UI-only release.

If you had styled anything against the previous pine-green palette — unlikely, since the components
are packaged — note that the brand moved to enterprise blue `#1b4db1`.

---

## Rollback

There is none. A 2GP managed package cannot be downgraded in place: `ancestorVersion: HIGHEST`
enforces a forward-only lineage, and promotion is irreversible.

If a version causes a problem in your org, uninstall and reinstall the previous promoted version.
`PE_Inspection_Log__c` data is removed on uninstall — **export it first** if you need the history.

---

## Checklist for whoever writes the next section

- [ ] Does the upgrade invalidate the cache? Say so, so slowness is not read as breakage.
- [ ] Does the packaged permission set gain tabs, objects or fields? Cloned sets will not inherit them.
- [ ] Does anything that previously reported X now report Y? That is the most important paragraph on
      the page — lead with it, and say plainly whether past decisions should be re-checked.
- [ ] Is there anything a subscriber must do *before* upgrading? Put it first, not last.
