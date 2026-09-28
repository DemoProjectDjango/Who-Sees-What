# ADR-0001: Read-only product with zero external calls

- **Status:** Accepted
- **Date:** Project inception
- **Deciders:** Product engineering, Twinforce Solutions

## Context

Who Sees What reads other users' permission metadata and is distributed through the AppExchange,
which requires a Salesforce security review. Every external endpoint, every credential store and
every write path expands the review surface and the review timeline.

The product's job is to *answer a question*. Nothing about answering it requires modifying the
subscriber's org or contacting anything outside it.

## Decision

The package is read-only and self-contained:

- No HTTP callouts.
- No Named Credentials or External Credentials.
- No Metadata API callouts.
- No custom REST or SOAP endpoints.
- No DML, with exactly one exception: the append-only `PE_Inspection_Log__c` insert.

## Consequences

**Positive**

- The security review answer to "what leaves the org?" is "nothing", with no caveats.
- The product cannot corrupt a subscriber's configuration. Worst case it renders a wrong answer.
- No credential storage, so no credential-handling review questions.
- Installation requires no remote site settings or trusted URLs.

**Negative**

- Per-user record type visibility, page layout assignment, per-permission-set app visibility and
  standard tab visibility are unobtainable, because they exist only in Metadata API territory.
  These were each verified independently before being accepted as out of scope.
- Any future feature requiring org modification needs a new ADR, not an exception.

## Alternatives considered

- **Metadata API from day one.** Rejected: it would have delayed the first security review
  substantially for features that were not the core value proposition. Revisited in
  [ADR-0007](0007-defer-record-types-to-metadata-api.md).
- **Allow writes for a "fix this" action.** Rejected: a permission-inspection tool that can also
  grant permissions is a different, far riskier product.
