# ADR-0012 — Resolve names through `Schema.SObjectType` in all dynamic SOQL

**Status:** Accepted
**Date:** 2026-10

---

## Context

`PEInspectionLogService` shipped in `0.6.0-1` with four literal static SOQL variants, one per
combination of the two optional filters:

```apex
records = [
    SELECT Id, Action__c, Detail__c, Inspected_At__c, ...
    FROM PE_Inspection_Log__c
    WHERE Inspector_User__c = :inspectorId AND Subject_User__c = :subjectId
    WITH USER_MODE
    ORDER BY Inspected_At__c DESC
    LIMIT :lim
];
```

Static SOQL is the right default: it is compile-time checked, injection-proof, and the Code Analyzer
is happy with it. It worked in `wsw-dev`.

It would have failed for every subscriber. In the managed package the object is
`twinforce__PE_Inspection_Log__c` and the fields carry the same prefix. Static SOQL is rewritten by
the compiler; **dynamic SOQL is not reliably namespace-qualified**, and the moment any part of the
query text is composed, unqualified custom identifiers stop being safe.

This class needed composed text — four near-identical static variants to vary two optional predicates
is the kind of duplication that rots — so the composition was the right call and the literals were
the defect.

## Decision

Any dynamic SOQL in this codebase resolves object, field and relationship names through describe:

```apex
String objectName   = Schema.SObjectType.PE_Inspection_Log__c.getName();
String actionField  = Schema.SObjectType.PE_Inspection_Log__c.fields.Action__c.getName();
String inspectorRel = Schema.SObjectType.PE_Inspection_Log__c
                          .fields.Inspector_User__c.getRelationshipName();
```

Describe returns the fully qualified name in **both** unmanaged and managed contexts. Values stay
bound; `Database.queryWithBinds(queryText, binds, AccessLevel.USER_MODE)` preserves user-mode access.

Written down as a rule because the failure is invisible in development and total in production.

## Consequences

**Good**

- The same code is correct unmanaged and under the namespace. No conditional, no string prefix
  constant.
- Relationship traversal (`Inspector_User__r.Name`) is handled too, via `getRelationshipName()` —
  the part most easily forgotten, because the relationship suffix differs from the field suffix.
- Four query variants collapsed to one composed query with bound predicates.

**Bad**

- The query text is less readable than static SOQL, and the cost is real. Static SOQL remains the
  default; this applies only where composition is genuinely needed.
- Compile-time field checking is lost. A renamed field now fails at runtime rather than at deploy.
  Mitigated by the describe reference itself — `fields.Action__c` is still a compile-time symbol, so
  only the *query shape* is unchecked, not the field's existence.
- Prevention depends on review, not on tooling. No analyser rule catches this. It is on the
  authorisation-change checklist in [../SECURITY-MODEL.md](../SECURITY-MODEL.md) §10 and in
  [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md).

## The broader lesson

**A managed-package bug that cannot reproduce in the development org is the expensive kind.** This
one was caught between `0.6.0-1` and `0.6.0-2`. It would otherwise have reached a subscriber as a
feature that simply did not work, with no error anyone could act on.

Worth generalising at the release level: beta verification happens against the **installed managed
package**, never against source. [../RELEASE-PROCESS.md](../RELEASE-PROCESS.md) §4 already says so;
this is the case that proves why.

## See also

- [../AUDIT-TRAIL.md](../AUDIT-TRAIL.md) §5
- [0008-2gp-shared-namespace.md](0008-2gp-shared-namespace.md)
