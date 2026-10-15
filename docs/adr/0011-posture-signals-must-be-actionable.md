# ADR-0011 — A posture signal is a count with a remedy, or it is not a signal

**Status:** Accepted
**Date:** 2026-10

---

## Context

`PEOrgStatsService` answers *how big is this org*: 143 permission sets, 44 profiles. Those figures
are true, static for weeks, and nothing follows from reading them. They are a decoration on a
dashboard.

An access-audit tool exists to answer a different question: **is anything here wrong, and what would
I do about it?**

The temptation when building a Home panel is to fill it. Counts are cheap, and a dense dashboard
looks substantial. The result is a screen people stop reading within a fortnight.

## Decision

Every signal in `PEPostureService` is **a count with a defined remedy**. If no remedy can be written,
the count does not belong in the class.

Shipped signals:

| Key | Signal | Remedy |
| --- | --- | --- |
| `staleGroups` | Groups awaiting recalculation | Members hold different permissions than configured until recalculation finishes |
| `PermissionsViewAllData` | Users holding View All Data | Review whether each still needs it |
| `PermissionsModifyAllData` | Users holding Modify All Data | Same |
| `dormantUsers` | Active users who never signed in | Each holds a licence and its permissions without ever having used them |
| `unassignedSets` | Permission sets assigned to nobody | Harmless but noisy; retiring them makes real grants easier to find |

Two supporting rules:

1. **Each query is independently caught.** These are unrelated queries against objects of varying
   obscurity. One being unavailable in a given org is not a reason to blank the other four. (License
   Inspector taught this the hard way: an uncaught failure in one card took the whole panel down,
   silently, for every card — not just the one at fault.)
2. **A failed signal leaves its field null, and null renders as *unavailable*.** Never zero. On a risk
   panel a fabricated zero reads as an all-clear, which is the most dangerous thing a security tool
   can say.

Privileged-user counts resolve through assignments, not standalone sets: counting only standalone
sets would report most orgs as having no administrators.

## Consequences

**Good**

- The panel stays short and keeps being read.
- Each row answers *so what* without the administrator working it out, which is the difference
  between a dashboard and a tool.
- The null-is-unavailable rule means a partially broken panel is honest rather than reassuring.

**Bad**

- Rejecting interesting-but-inert metrics is a judgement call made repeatedly, and it will feel
  arbitrary to someone who was not in the conversation. Hence this record.
- Writing a good remedy line is harder than adding a count, so signals are slower to add. That is the
  intended friction.
- Five signals look sparse next to competitors' dashboards. Accepted — a screen people read beats a
  screen people screenshot once.

## See also

- [../ROADMAP.md](../ROADMAP.md) §6
- [0009-record-reach-approximation.md](0009-record-reach-approximation.md) — same principle applied to numbers rather than signals
