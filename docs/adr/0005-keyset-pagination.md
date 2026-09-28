# ADR-0005: Keyset pagination instead of OFFSET

- **Status:** Accepted
- **Date:** User search implementation

## Context

User search must page through potentially tens of thousands of active users, filtered by profile,
role and user type, sorted by name or last login.

SOQL `OFFSET` is capped at 2000 and degrades badly at depth — the database still scans the skipped
rows. It is also unstable under concurrent edits: a user created or deactivated mid-session shifts
every subsequent page, silently skipping or duplicating rows.

## Decision

Keyset (seek) pagination via `PEKeysetCursor`.

The cursor encodes `sortField`, `sortValue` (ISO-8601 for datetimes) and `lastId`. The next page
queries for rows *after* that composite position, with `Id` as the deterministic tiebreaker:

```
ORDER BY Name ASC NULLS LAST, Id ASC
WHERE (Name > :sortValue) OR (Name = :sortValue AND Id > :lastId)
```

The cursor is treated as **untrusted input**:

- `sortField` is whitelisted (`Name`, `LastLoginDate`). Anything else throws.
- Malformed cursors raise a typed `BAD_CURSOR` exception rather than being coerced into a query.
- The UI resets to page one on that error rather than retrying.

Backward navigation is handled client-side by `peUtils/cursorStack.js`, which keeps the cursors
already visited. A result cap (`PEConstants.MAX_SEARCH_RESULTS`, 200) sets `capReached` so the UI can
prompt the user to refine rather than page indefinitely.

## Consequences

**Positive**

- Page cost is constant regardless of depth.
- Results are stable under concurrent user creation and deactivation.
- No 2000-row ceiling.
- The whitelist closes an injection vector that a dynamic `ORDER BY` would open.

**Negative**

- No random access — "jump to page 7" is not expressible. Acceptable: the workflow is search then
  refine, not browse.
- Backward navigation requires client-side cursor state.
- Every sortable column must be added to the whitelist deliberately, which is the intended friction.
