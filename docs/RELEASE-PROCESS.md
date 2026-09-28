# Release Process

Creating, testing and promoting a 2GP managed package version of Who Sees What.

---

## 1. Facts

| | |
| --- | --- |
| Package | `Who Sees What` |
| Package ID | `0HoOW00000000ZV0AY` |
| Namespace | `twinforce` |
| Dev Hub | `WSWDevHub` (`nilufa.tforce-abyj@force.com`) |
| Ancestry | `ancestorVersion: HIGHEST` |
| API version | `67.0` |
| Coverage gate | 75% (Salesforce-enforced); current 88% |

2GP allows one namespace to host many packages — unlike 1GP. Reusing `twinforce` for other Twinforce
products is valid and expected.

---

## 2. Pre-Release Checklist

- [ ] `main` is green; the release branch is merged
- [ ] `sfdx-project.json` `versionNumber` and `versionName` bumped
- [ ] `CHANGELOG.md` updated with a dated entry
- [ ] `npm run lint` clean
- [ ] `npm run scan` reports zero violations on AppExchange + Security rulesets
- [ ] `npm run test:unit` passes
- [ ] Apex tests pass in `wsw-dev` with coverage recorded
- [ ] **Muting correctness matrix passes** ([TESTING.md](TESTING.md) §3)
- [ ] `CACHE_PREFIX` bumped if any cached object's shape changed
- [ ] Documentation updated
- [ ] No real user data in static resources or screenshots
- [ ] `git status --porcelain` is empty

---

## 3. Create the Version

```powershell
sf config set target-dev-hub=WSWDevHub

sf package version create `
  --package "Who Sees What" `
  --installation-key-bypass `
  --code-coverage `
  --wait 90 `
  --target-dev-hub WSWDevHub

sf package version list --packages "Who Sees What" --target-dev-hub WSWDevHub --verbose
```

The command writes the new `04t` ID into `packageAliases` in `sfdx-project.json`. Commit that.

### Ancestry

`ancestorVersion: HIGHEST` pins each new version to the highest **promoted** version as its ancestor.
This enforces an upgradable lineage: version creation fails if the change would break installed
subscribers — for example by removing a packaged component. That failure is a feature. If a removal
is genuinely required, it needs a deprecation path, not an ancestry override.

---

## 4. Install and Verify

Install the beta into a clean org (never straight into a customer org):

```powershell
sf package install --package 04tXXXXXXXXXXXXXXX --target-org WhoSeesWhat --wait 20 --publish-wait 20
sf org assign permset --name PermissionCheckerPermissionSet --target-org WhoSeesWhat
sf org open --target-org WhoSeesWhat
```

Then run the manual test script in [TESTING.md](TESTING.md) §5 **against the installed managed
package**, not against source. Namespace-prefixed behaviour, packaged custom permissions and cache
partition allocation only behave correctly under a real install.

Also verify an **upgrade** path: install the previous promoted version first, then upgrade to the new
beta, and confirm no data loss and no broken tabs.

---

## 5. Promote

Promotion makes a version installable in production and is **irreversible**.

```powershell
sf package version promote --package "Who Sees What@0.5.0-1" --target-dev-hub WSWDevHub
```

Once promoted, that version becomes the ancestor for everything that follows. Do not promote a
version that has not completed §4.

---

## 6. Tag and Record

```powershell
git tag -a v0.5.0-1 -m "Who Sees What 0.5.0-1 (04tXXXXXXXXXXXXXXX)"
git push origin v0.5.0-1
```

Record in `CHANGELOG.md`: version number, `04t` ID, promotion date, coverage, and anything a
subscriber must do on upgrade.

---

## 7. AppExchange Submission

Required for a listed release:

- [ ] Partner Program membership active
- [ ] Partner Business Org linked
- [ ] Listing complete in Partner Console
- [ ] Security review submitted with the promoted version
- [ ] Checkmarx scan attached, zero findings
- [ ] Code Analyzer report attached, zero violations
- [ ] Review org provisioned with **fictional** seeded permission data
  ([SALESFORCE-ENVIRONMENTS.md](SALESFORCE-ENVIRONMENTS.md) §7)
- [ ] All screenshots free of real usernames, emails and phone numbers
- [ ] Documentation URLs reachable

---

## 8. Version Numbering

`major.minor.patch.build`

| Change | Bump |
| --- | --- |
| Breaking change to packaged components | major |
| New feature, new object, new API method | minor |
| Defect fix, copy change, styling | patch |
| `NEXT` build increment | automatic |

`versionName` is the human label (`Beta 5`). `versionNumber` ends in `NEXT` so each create
auto-increments the build.

---

## 9. Rollback

There is no un-promote. Mitigations, in order of preference:

1. Ship a patch version that reverses the behaviour.
2. Deprecate a version so it can no longer be installed (existing installs are unaffected).
3. Guide affected subscribers to uninstall and reinstall the prior version — last resort, and it
   loses `PE_Inspection_Log__c` data.

This asymmetry is why §4 is not optional.
