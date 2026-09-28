# Salesforce Environments

> Authoritative record of every org, alias and account this product is built, tested and packaged from.
> **No credentials, tokens or auth URLs belong in this file or anywhere in this repository.**

---

## 1. Product

| Attribute | Value |
| --- | --- |
| Product name | Who Sees What — User Access, Field Security & Record Visibility Explorer |
| Product code | WSW |
| Internal codebase name | PermissionChecker / PermissionExplorer |
| Apex/metadata prefix | `PE` |
| Packaging model | Second-generation managed package (2GP) |
| Namespace | `twinforce` |
| Package name | `Who Sees What` |
| Package ID (0Ho) | `0HoOW00000000ZV0AY` |
| Source API version | `67.0` |
| Environment strategy | Dedicated Developer Edition org per product |
| Vendor | Twinforce Solutions Limited |
| AppExchange listing | <https://appexchange.salesforce.com/appxListingDetail?listingId=dc0aa216-dbed-49e5-86e0-542869f8dc26> |

---

## 2. Source Control

| Attribute | Value |
| --- | --- |
| Repository | <https://github.com/DemoProjectDjango/Who-Sees-What> |
| Clone (HTTPS) | `git clone https://github.com/DemoProjectDjango/Who-Sees-What.git` |
| Clone (SSH) | `git clone git@github.com:DemoProjectDjango/Who-Sees-What.git` |
| Default branch | `main` |
| GitHub account holding the source | `demoorgsalesforce@gmail.com` |
| Local working copy | `D:\Product\PermissionChecker\PermissionChecker` |

> **Note on the GitHub account.** `demoorgsalesforce@gmail.com` is the account that owns the
> `DemoProjectDjango` organisation and the repository. It is **not** a Salesforce login and must
> never be used as one. Commits authored from a developer's personal Git identity are fine; the
> account above is the one that controls repository access, branch protection and releases.

### Branches in use

| Branch | Purpose |
| --- | --- |
| `main` | Released / packagable source. Protected. |
| `fix/*` | Defect fixes targeting the current version. |
| `style/*` | UI, CSS and copy changes. |
| `apexdoc`, `analyzer-cleanup`, `prune-for-2gp`, `rename-pe-prefix` | Historic maintenance branches. Delete once merged. |

---

## 3. Dev Hub

The Dev Hub is the org that owns the 2GP package and authorises scratch org creation.
Package versions can only be created and promoted from here.

| Attribute | Value |
| --- | --- |
| CLI alias | `WSWDevHub` |
| Username | `nilufa.tforce-abyj@force.com` |
| Org ID | `00DdN00000roILEUA2` |
| Org type | Developer Edition with Dev Hub enabled |
| Role | Owns package `0HoOW00000000ZV0AY`; creates and promotes all package versions; issues scratch org allocations |
| Default Dev Hub | Yes |

Verify:

```powershell
sf org list
sf config get target-dev-hub --verbose
sf package list --target-dev-hub WSWDevHub
sf package version list --packages "Who Sees What" --target-dev-hub WSWDevHub
```

> A second Dev Hub, `momentum@arrivehomeownership.org`, is authorised on this machine for an
> unrelated engagement. It has no relationship to Who Sees What. Always pass
> `--target-dev-hub WSWDevHub` explicitly on packaging commands.

---

## 4. Development Org (primary)

| Attribute | Value |
| --- | --- |
| CLI alias | `wsw-dev` |
| Username | `ishann.tforce.a3cd5122e44a@agentforce.com` |
| Org ID | `00DgK00000a8MoDUAU` |
| Org type | Developer Edition |
| Default target org | Yes |
| Purpose | Primary development, manual testing and Apex test execution for Who Sees What |

---

## 5. Secondary and Supporting Orgs

| Alias | Username | Org ID | Type | Purpose |
| --- | --- | --- | --- | --- |
| `WhoSeesWhat` | `ishann.tforce.3eaafb93063e@agentforce.com` | `00DgL00000ZdsQzUAJ` | Developer Edition | Package install testing / subscriber simulation |
| `vscodeOrg` | `saiful@momentum-worldwide.com` | `00DAq00000AT6cTMAT` | Sandbox | **Unrelated project.** Do not deploy Who Sees What here. |
| (no alias) | `nilufa.tforce-abyj@force.com.tfproduct` | `00DC40000055DkwMAE` | Sandbox | Dev Hub sandbox |
| `formBuilder` | `ishann.tforce.92b28a243242@agentforce.com` | `00DFj00000HmZMfEAN` | Developer Edition | Unrelated product. Expired/unreachable. |
| `ishanTNB` | `developertwinforce.80962c0f907d@agentforce.com` | `00DNS00000nhkQr2AI` | Developer Edition | Unrelated. Expired/unreachable. |
| `isij-prod` | `momentum@jaffari.org` | `00Dau00008LK2LEAW` | Production | Unrelated. Refresh token expired. |

### Wrong-org deploy hazard

`vscodeOrg` resolves to `saiful@momentum-worldwide.com`, which is **not** a Who Sees What org.
Deploying this package there is a real and previously-encountered risk. Pin the target org once
per clone:

```powershell
sf config set target-org=wsw-dev
sf config set target-dev-hub=WSWDevHub
sf config get target-org --verbose
sf org display --target-org wsw-dev
```

Prefer explicit `--target-org wsw-dev` on every deploy command regardless.

---

## 6. Scratch Orgs

Defined by `config/project-scratch-def.json` (Developer edition, `EnableSetPasswordInApi`).

```powershell
sf org create scratch --definition-file config/project-scratch-def.json --alias wsw-scratch --duration-days 7 --target-dev-hub WSWDevHub
sf project deploy start --target-org wsw-scratch
sf org assign permset --name PermissionCheckerPermissionSet --target-org wsw-scratch
sf org open --target-org wsw-scratch
```

Clean up stale authorisations (the CLI currently reports expired scratch org entries):

```powershell
sf org list --clean
```

---

## 7. AppExchange / Security Review Org

A clean Developer Edition org with seeded, **fictional** permission data is required for the
Salesforce security reviewer. This is tracked as outstanding work.

| Attribute | Value |
| --- | --- |
| Alias | _not yet provisioned_ |
| Username | _not yet provisioned_ |
| Org ID | _not yet provisioned_ |
| Requirement | Latest promoted package version installed; demo users, profiles, permission sets and muting permission sets seeded with fictional names, emails and phone numbers |

---

## 8. Scope Boundary

This Salesforce org set is dedicated to **Who Sees What**. Do not deploy metadata belonging to:

- Mass Delete
- Google Form Auto Sync
- Smart Lookup Data Loader
- Accounting
- Any other Twinforce Solutions product

2GP permits one namespace (`twinforce`) to host many packages, so namespace reuse across products
is valid — but the **source trees and orgs stay separate**.

---

## 9. Security

Never commit, paste into an issue, or store in this repository:

- Salesforce passwords
- Security tokens
- Access tokens or refresh tokens
- SFDX Auth URLs (`sf org display --verbose` output)
- Connected App consumer keys or secrets
- JWT private keys or certificates
- Real user emails, usernames or phone numbers in screenshots or test data

`.gitignore` already excludes `.sf/`, `.sfdx/` and `.env`. Verify before every push:

```powershell
git status --porcelain
git ls-files | Select-String -Pattern "\.sf/|\.sfdx/|\.env"
```

---

## 10. Change Log for This Document

| Date | Change |
| --- | --- |
| 2026-09-28 | Added GitHub repository, GitHub account, Dev Hub details, secondary org inventory, scratch org and security-review org sections. |
| (earlier) | Initial development org and scope boundary. |
