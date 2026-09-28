# ADR-0008: 2GP managed package sharing the `twinforce` namespace

- **Status:** Accepted
- **Date:** Packaging setup

## Context

Twinforce Solutions ships several AppExchange products (Mass Delete, Google Form Auto Sync, Smart
Lookup Data Loader, Accounting, Who Sees What). Under first-generation packaging, a namespace maps to
one package, which would force a new namespace — and a new branding surface — per product.

## Decision

Package Who Sees What as a **second-generation managed package (2GP)** under the existing `twinforce`
namespace.

2GP permits one namespace to host many packages, so namespace reuse is valid and supported. Each
product keeps its own package ID, its own source repository and its own org set; only the namespace
is shared.

Configuration:

| Setting | Value |
| --- | --- |
| Package ID | `0HoOW00000000ZV0AY` |
| Namespace | `twinforce` |
| `ancestorVersion` | `HIGHEST` |
| `versionNumber` | `<major>.<minor>.<patch>.NEXT` |

`ancestorVersion: HIGHEST` pins each new version to the highest promoted version, so version creation
**fails** if a change would break installed subscribers. That failure is the guard working, not an
obstacle to route around.

## Consequences

**Positive**

- Consistent `twinforce__` prefix across the vendor's catalogue.
- Source-driven packaging from `sfdx-project.json` with reproducible version creation from CI.
- Enforced upgrade lineage protects subscribers from breaking changes.
- No new namespace registration or branding fragmentation.

**Negative**

- All Twinforce products share a namespace, so component API names must not collide across products.
  The `PE` prefix convention exists for this reason.
- Removing a packaged component requires a deprecation path, not a deletion.
- Promotion is irreversible. Mitigation is forward-only: ship a patch, or deprecate the version.
- Strict org separation must be maintained despite the shared namespace — see
  [../SALESFORCE-ENVIRONMENTS.md](../SALESFORCE-ENVIRONMENTS.md) §8.
