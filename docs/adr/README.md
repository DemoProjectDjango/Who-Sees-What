# Architecture Decision Records

Short, dated records of decisions that shaped this codebase and would otherwise be re-litigated
every few months.

Format: [Michael Nygard's ADR template](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).
Status is one of **Proposed**, **Accepted**, **Superseded by ADR-XXXX**, **Deprecated**.

| ID | Title | Status |
| --- | --- | --- |
| [0001](0001-read-only-no-callouts.md) | Read-only product with zero external calls | Accepted |
| [0002](0002-custom-permission-gate-and-audit.md) | Custom-permission gate coupled to an append-only audit trail | Accepted |
| [0003](0003-muting-permission-set-subtraction.md) | Subtract muting permission sets rather than unioning grants | Accepted |
| [0004](0004-platform-cache-with-version-token.md) | Platform Cache with a single version token and graceful fallback | Accepted |
| [0005](0005-keyset-pagination.md) | Keyset pagination instead of OFFSET | Accepted |
| [0006](0006-single-auraenabled-controller.md) | One `@AuraEnabled` controller as the sole LWC-facing surface | Accepted |
| [0007](0007-defer-record-types-to-metadata-api.md) | Defer record type and layout visibility to the Apex Metadata API | Accepted |
| [0008](0008-2gp-shared-namespace.md) | 2GP managed package sharing the `twinforce` namespace | Accepted |

## Writing a new ADR

1. Copy the structure of an existing record.
2. Number sequentially; never renumber an existing one.
3. Record the decision when it is made, not when it is questioned.
4. Superseding a decision means adding a new ADR and marking the old one — never editing history.
