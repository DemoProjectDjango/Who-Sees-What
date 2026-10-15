# Glossary

Vocabulary used across the codebase, the documentation and the product UI. Where the platform term
and the user-facing term differ, both are given — the difference is deliberate.

---

## Salesforce Platform

**Profile** — The single permission container every user must have. Internally it *is* a
`PermissionSet` with `IsOwnedByProfile = true`, which is why `PEPermissionResolver` can treat it like
any other parent.

**Permission set** — An additive grant container assignable to many users.

**Permission set group** — A bundle of permission sets assigned as one unit. Assignment produces a
`PermissionSetAssignment` carrying a `PermissionSetGroupId`.

**Permission set group component** — The join from a group to one of its member permission sets
(`PermissionSetGroupComponent`).

**Muting permission set** — A permission set with `Type = 'Muting'` attached to a group. It
**removes** permissions its sibling component sets grant. The most commonly mishandled concept in
this product's category.

**Outdated group** — A `PermissionSetGroup` with `Status != 'Updated'`. Recalculation is pending, so
live behaviour may not yet match the definition. Flagged rather than trusted.

**FLS (field-level security)** — Per-field read and edit permission, stored in `FieldPermissions`.

**CRUD** — Create, Read, Update, Delete at the object level, stored in `ObjectPermissions` along with
View All and Modify All.

**View All Data / Modify All Data** — Org-wide overrides. Deliberately **not** required by this
product; requiring them would contradict its premise.

**Parent** — Any `PermissionSet` ID contributing to a resolution. Profiles, permission sets,
group components and muting sets are all parents.

**2GP** — Second-generation packaging. Allows one namespace to host many packages, unlike 1GP.

**Ancestor version** — The promoted version a new version upgrades from. `HIGHEST` enforces an
unbroken upgrade lineage.

**Platform Cache** — Org- and session-scoped key/value cache. Allocated per partition by the
subscriber; the product degrades gracefully when it is absent.

---

## Product Concepts

**WHO / WHERE / WHAT** — The three stages of the Permission Explorer. WHO selects a user, WHERE
selects an app then an object, WHAT shows object and field access. WHO and WHERE collapse on
selection; WHAT is terminal and does not auto-collapse.

**Effective parents** — The set of permission set IDs that contribute grants after group expansion
and muting removal.

**Muting parents** — The permission set IDs that subtract.

**Granted then muted** — A permission granted somewhere and cancelled by a muting set. Rendered
amber. The user does **not** have the permission; the state exists so the administrator does not go
looking for a grant that is already there.

**Not applicable** — A field where FLS is not a meaningful concept: formula, auto-number, system
audit field, master-detail key. Distinct from "hidden", which would be technically true and
practically misleading.

**Access without a tab** — Objects a user has access to but cannot reach from the selected app's
navigation. Surfaced explicitly so nothing disappears silently.

**Attribution / granted-by** — The chain from a permission back to the profile, permission set,
group or muting set responsible.

**Access trace** — The explain-this-access view for a single permission.

**Inspection** — One read of another user's access. Every inspection writes a
`PE_Inspection_Log__c` row.

**Inspector** — The administrator performing the inspection. **Subject** — the user being inspected.

**Delegation USP** — The product's core promise: people who ask access questions can answer them
themselves, without being granted Setup access.

**Data Visibility** — The tab answering *how many records* of an object a user reaches, and why.
Distinct from Permission Explorer, which answers *what objects and fields* they can touch.

**Reach** — The count of records of one object a selected user can get to: records they own, plus
records shared to them or to a group they belong to.

**Exact vs floor** — A reach figure is **exact** when the answer is complete: a public org-wide
default, or the user holds View All on the object. Otherwise it is a **floor** — at least this many,
possibly more, because role-hierarchy access produces no share rows to count. The distinction is
always rendered; a floor is never presented as a total.

**Sharing bypassed** — The state where the org-wide default or View All makes sharing irrelevant, so
every record is reachable and the org total *is* the answer.

**Denominator** — The org-wide record count, as the *running* user sees it. Apex runs as the running
user, so `with sharing` enforces the administrator's sharing, not the subject's. The denominator is
context for a reach figure, never the reach figure itself.

**Posture signal** — An org-level count with a defined remedy, shown on Home. A count nobody can act
on is not a signal and does not belong on the panel. A signal that fails to compute renders as
*unavailable*, never as zero — on a risk panel a fabricated zero reads as an all-clear.

**Inspection Log viewer** — The in-product read of `PE_Inspection_Log__c`. Reading the log is gated
but deliberately **not** logged: a trail that records its own observation is noise, not evidence.

---

## Signal Colours

| State | Colour | Meaning |
| --- | --- | --- |
| Grant | `#1F8A6B` green | Permission is held |
| Deny | `#C0483C` red | Permission is not held |
| Muted | `#B4801F` amber | Granted then cancelled by a muting set |
| Not applicable | `#B4B0A8` grey | FLS does not apply to this field |

---

## Codebase

**`PE` prefix** — Applied to all Apex classes and LWC components, except the `PermissionExplorer*`
classes that predate the convention.

**`Resolved`** — The output of `PEPermissionResolver`: effective parents, muting parents,
attribution, outdated groups, counts.

**`PEDto`** — The `@AuraEnabled` transport types.

**Version token** — An org-scoped string participating in every cache key. Bumping it invalidates
the entire product cache in one operation.

**`CACHE_PREFIX`** — The resolver's cache namespace (`resolvedV4`). Bumped whenever the shape of a
cached object changes.

**Keyset cursor** — Opaque pagination token encoding sort field, sort value and last ID. Used instead
of `OFFSET`, which is expensive and unstable at depth.
