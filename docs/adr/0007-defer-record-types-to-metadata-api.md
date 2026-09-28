# ADR-0007: Defer record type and layout visibility to the Apex Metadata API

- **Status:** Accepted
- **Date:** Version 0.4 / 0.5 planning

## Context

"Which record types and page layouts can this user see?" is a natural question for this product, and
users ask it.

It is also unanswerable within the current architecture. Four independent verifications confirmed:

- `Profile.recordTypeVisibilities` and `PermissionSet.recordTypeVisibilities` exist **only** in
  Metadata API representations. They are not queryable via SOQL and not exposed through Apex
  `Schema`.
- Page layout assignment is Profile × RecordType only. No permission set participates.
  `Schema.Layout` does not exist as an Apex type; `Layout` is queryable via the standard/Tooling REST
  API but not from Apex.
- There is no queryable junction object for either.

Adding Metadata API access ([ADR-0001](0001-read-only-no-callouts.md)) expands the security review
surface at exactly the point the product needed to ship.

## Decision

Defer to version 0.6, implemented via `Metadata.Operations.retrieve` on `Profile` and
`PermissionSet` — an Apex-native Metadata API path, not an HTTP callout, so
[ADR-0001](0001-read-only-no-callouts.md)'s no-callout position survives intact.

In the interim, display record types from the queryable `RecordType` object, **explicitly labelled as
org-wide rather than per-user**, with a forward-reference note. Page layout visibility is not shown
at all.

Two pre-build checks are required before 0.6 work starts:

1. Verify which metadata types `Metadata.Operations.retrieve` actually supports in `wsw-dev` — note
   that `Metadata.MetadataType` itself supports only three types, none of them relevant here.
2. Confirm whether muting permission sets affect record type visibility, since the resolver's
   subtraction model must extend to it or explicitly not.

## Consequences

**Positive**

- 0.5 ships without a Metadata API security review conversation.
- The limitation is documented and visible rather than silently absent.
- The 0.6 path is an Apex-native operation, keeping the no-callout position.

**Negative**

- An org-wide record type list answers a question users did not ask, and risks being read as a
  per-user answer. The labelling is load-bearing; if it proves insufficient in testing, the catalogue
  should be cut rather than left ambiguous.
- Metadata API retrieval is asynchronous and slower than SOQL, which will shape the 0.6 UX.
