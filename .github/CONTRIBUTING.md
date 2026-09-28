# Contributing to Who Sees What

---

## Before You Start

Read, in order:

1. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the layering and why it is that way
2. [`docs/DEVELOPER-GUIDE.md`](docs/DEVELOPER-GUIDE.md) — machine setup and daily workflow
3. [`docs/SALESFORCE-ENVIRONMENTS.md`](docs/SALESFORCE-ENVIRONMENTS.md) — orgs, and the wrong-org hazard
4. [`docs/adr/`](docs/adr/) — decisions already made; do not re-open one without a new ADR

---

## Working Practice

**Analysis before implementation.** Feasibility and design are discussed before code is written.
Several features in this product turned out to be impossible on the platform; discovering that after
implementation is expensive, discovering it before is free. Do not begin building unless the approach
has been agreed.

**Complete file replacements, not partial diffs.** Whole files. This matters especially for LWC
bundles, which deploy as a unit or not at all.

**Scope discipline.** When a workstream is narrowed, excluded material stays excluded. Do not
reintroduce requirements, risks or components that were deliberately cut.

---

## Branches

| Prefix | Use |
| --- | --- |
| `feat/` | New capability |
| `fix/` | Defect fix |
| `style/` | UI, CSS, copy |
| `docs/` | Documentation only |
| `chore/` | Tooling, dependencies, cleanup |
| `refactor/` | Behaviour-preserving restructure |

Branch from `main`. Keep branches short-lived. Delete after merge.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/): `type: imperative summary`.

```
feat: add muting set attribution to the granted-by panel
fix: correct field seeding so inaccessible fields still render
docs: record the decision to defer record types to the Metadata API
chore: remove two unreferenced LWC bundles
```

Reference the issue in the body, not the subject line.

---

## Pull Requests

### Checklist

- [ ] `npm run lint` clean
- [ ] `npm run prettier:verify` clean
- [ ] `npm run test:unit` passes
- [ ] `npm run scan` reports zero violations
- [ ] Apex tests pass in `wsw-dev`; coverage ≥ 80% on changed classes
- [ ] **Muting correctness matrix passes** if the resolver was touched ([`docs/TESTING.md`](docs/TESTING.md) §3)
- [ ] `CACHE_PREFIX` bumped if a cached object's shape changed
- [ ] Documentation updated in this PR, not a later one
- [ ] `CHANGELOG.md` updated under `Unreleased`
- [ ] New ADR added if an architectural decision was made or reversed
- [ ] No real user data in fixtures, screenshots or test payloads
- [ ] No credentials, tokens or auth URLs anywhere in the diff

### Description

State what changed, why, and how it was verified. If a platform constraint was discovered, add it to
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) in the same PR — that document exists so a
constraint costs one afternoon, not several.

---

## Code Standards

### Apex

- Prefix new classes `PE`.
- `with sharing` on every class. No exceptions.
- `WITH USER_MODE` on user-facing queries.
- Bind all variables; compose dynamic SOQL from constant fragments only.
- Typed DTOs only — `List<Object>` is not serialisable via `@AuraEnabled`.
- ApexDoc on every public method. Void methods need only `@param` tags under PMD's ApexDoc rule.
- `desc` and `where` are reserved words. `|=` is not valid for Apex Booleans.
- Never write a static property getter that reads its own property.

### LWC

- `pe` prefix on folders; `<c-pe-…>` in markup.
- Import Apex **only** from `PermissionExplorerController`.
- Shared styles via `@import 'c/peBase';`. `peBase` is CSS-only by design.
- Shared helpers go in `peUtils/`.
- No hardcoded viewport arithmetic — measure in `renderedCallback`.

### Documentation

- Mermaid inside Markdown. Never commit rendered images.
- Explain *why*, not just *what*, wherever a constraint is non-obvious.

---

## Adding an `@AuraEnabled` Method

1. Add it to `PermissionExplorerController` — nowhere else.
2. First statement: `PEAccessGate.assertAuthorisedAndLog(...)`.
3. Guard the target with `assertInspectable(userId)` if it takes a user.
4. Delegate to a service. Query logic in the controller is a review rejection.
5. Return a typed `PEDto`.
6. Wrap in `try/catch`, convert through `toAura`.
7. Test both the authorised and unauthorised path.
8. Update [`docs/API-REFERENCE.md`](docs/API-REFERENCE.md).

---

## Reporting Issues

- **Bugs** — <https://github.com/DemoProjectDjango/Who-Sees-What/issues>. Include the org type,
  package version, reproduction steps, and what you expected instead. Redact real usernames and
  emails.
- **Security vulnerabilities** — do **not** open a public issue. See [`SECURITY.md`](SECURITY.md).
