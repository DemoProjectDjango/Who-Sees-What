# Security Model

**Audience:** AppExchange security reviewers, subscriber security teams, engineers changing anything
that touches authorisation.

---

## 1. Summary

Who Sees What reads other users' permission metadata. That is exactly the pattern a security
reviewer scrutinises, so the design answers the question before it is asked:

1. Access is gated by an **explicit packaged custom permission**, checked **in Apex**.
2. Every inspection writes an **append-only audit row** the inspector cannot alter.
3. The product makes **no external calls** of any kind.
4. The product performs **no writes** other than that audit row.

---

## 2. Trust Boundaries

```mermaid
flowchart TB
    subgraph Browser["Subscriber browser — untrusted"]
        LWC[Lightning Web Components]
    end
    subgraph Platform["Salesforce platform — trusted runtime"]
        subgraph Pkg["Managed package, namespace twinforce"]
            CTRL[PermissionExplorerController]
            GATE[[PEAccessGate<br/>TRUST BOUNDARY]]
            SVC[Domain services]
            LOG[PEInspectionAuditLogger]
        end
        DATA[(Subscriber org data<br/>read via WITH USER_MODE)]
        AUDIT[(PE_Inspection_Log__c<br/>append only)]
    end
    EXT[External systems]

    LWC -->|@AuraEnabled| CTRL
    CTRL --> GATE
    GATE -->|authorised| SVC
    GATE -->|denied| LWC
    GATE --> LOG --> AUDIT
    SVC --> DATA
    Pkg -. "no callouts, no Named Credentials,<br/>no Metadata API, no egress" .-x EXT
```

The **only** trust boundary that matters is `PEAccessGate`. UI state is never treated as an
authorisation decision.

---

## 3. Authorisation

### The gate

```apex
public static Boolean isAuthorised() {
    return FeatureManagement.checkPermission(PEConstants.CUSTOM_PERMISSION);
}
```

- Custom permission: `Use_Permission_Explorer`, packaged.
- Granted by: `PermissionCheckerPermissionSet`, packaged.
- **Deliberately uncached.** An authorisation decision held in a mutable static outlives the context
  that produced it — `System.runAs` changes the user but not the static. `checkPermission` is cheap
  enough that the guarantee is worth more than the microseconds.

### Enforcement points

Every `@AuraEnabled` method calls one of:

| Method | Behaviour |
| --- | --- |
| `assertAuthorised()` | Throws a typed, non-retryable exception with an admin-actionable message |
| `assertAuthorisedAndLog(action, subjectUserId, detail)` | Gate **and** audit in one call — an inspection cannot occur without a log row |
| `assertInspectable(userId)` | Target guard: user must exist and be active. Frozen users are inspectable; that is the point. |

### Threats considered

| Threat | Mitigation |
| --- | --- |
| Direct Apex invocation bypassing the UI | Gate is in Apex, on every method |
| Privilege escalation via the tool | Read-only; no permission is ever granted or modified |
| Inspecting users without accountability | `assertAuthorisedAndLog` couples the two |
| Tampering with the audit trail | Edit and Delete withheld on `PE_Inspection_Log__c` |
| SOQL injection via search terms | Bind variables throughout; sort fields whitelisted in `PEKeysetCursor` |
| Cursor tampering | `PEKeysetCursor.decode` validates structure and sort field, else throws |
| Cache poisoning across users | Cache keys include the version token and the subject user ID; keys sanitised |
| CRUD/FLS bypass | `with sharing` on every class; `WITH USER_MODE` on user-facing queries |
| Data exfiltration | No callouts, no Named Credentials, no external endpoints |
| Reading another user's *records* through the tool | Record lists are read `WITH USER_MODE` as the running administrator. The product reports what the subject *would* reach; it never renders a record the running user cannot already see. |
| Rewriting history through the log viewer | `PEInspectionLogService` has no update or delete path, and the packaged permission set withholds Edit and Delete |

---

## 4. Injection Surface

| Input | Source | Handling |
| --- | --- | --- |
| Search term | User typed | Bound (`:term`) in a composed-but-parameterised query |
| `profileId`, `roleId`, `userType` | Picklist | Bound |
| `sortField` | UI | Whitelisted: `Name`, `LastLoginDate` |
| `encodedCursor` | Previous response | Decoded and validated; malformed input throws |
| `objectApiName` | UI | Resolved through `Schema.getGlobalDescribe()`, never concatenated into SOQL |
| `appDeveloperName` | UI | Bound |
| `objectApiName` (Data Visibility) | UI | Resolved through the describe map before use; field and relationship names come from `Schema.SObjectType`, never from the request |
| `searchTerm` (record list) | User typed | Bound; only accepted in ALL mode, against the name field |
| `sortField` (record list) | UI | Validated against the object's describe before it reaches the query |
| `inspectorId`, `subjectId` (log viewer) | UI | Typed as `Id` and bound |

`PEUserSearchService` composes dynamic SOQL from **constant string fragments only** — clause
constants concatenated in a fixed order, with all values bound. No user input reaches the query text.

---

## 5. Sharing and Data Access

- Every Apex class is declared `with sharing`.
- User-facing queries use `WITH USER_MODE`, so the running administrator's own CRUD/FLS applies.
- Permission-metadata objects (`ObjectPermissions`, `FieldPermissions`, `PermissionSetAssignment`)
  require **View Setup and Configuration** in the subscriber org. The product does not attempt to
  bypass this, and surfaces a typed error if the reading user lacks it.
- The product never queries `UserRecordAccess` for another user, because doing so requires
  **View All Data** — which would defeat the product's entire premise.

### Record reach, and why it is not an escalation

Data Visibility reports how many records of an object a *subject* user reaches. It derives that from
the org-wide default, ownership and share rows — all of which the running administrator reads under
their own sharing, `WITH USER_MODE`. Three consequences a reviewer should note:

1. No record is rendered that the running user could not already query. The subject's access is
   *described*, never *exercised*.
2. Apex runs as the running user, so the org-wide total is the administrator's view, not the
   subject's. It is labelled a denominator and never presented as the subject's reach.
3. Where the answer cannot be completed without View All Data — principally role-hierarchy access,
   which produces no countable share rows — the figure is labelled a **floor**, not rounded up into
   a claim. See [RECORD-VISIBILITY.md](RECORD-VISIBILITY.md).

### Reading the audit log

`getRecentInspections` is gated like every other method but is deliberately **not** logged. Logging a
read of the log makes the trail grow every time someone looks at it; an audit trail that records its
own observation is noise, not evidence. The query runs `WITH USER_MODE`, so a running user without
Read on `PE_Inspection_Log__c` receives an empty, flagged result rather than an error or a leak.

---

## 6. Data Handling and Privacy

| Category | Position |
| --- | --- |
| Data leaving the org | None |
| Data stored by the package | Audit rows only: actor, subject, action, detail, timestamp |
| PII in the package | None shipped. Subject/inspector are lookups to `User`, not copies of PII. |
| Logging | No `System.debug` of user data on success paths |
| Encryption | Platform-native; the package adds no key material |
| Retention | Not enforced by the package; subscribers may apply their own |

---

## 7. Screenshot and Demo-Data Policy

Applies to AppExchange listings, security-review documents, the Getting Started static resources and
any public material.

- **Must** use fictional users, emails, phone numbers and company names.
- **Must not** contain real subscriber, employee or customer data.
- Blurring is not sufficient — regenerate with seeded fictional data instead.

The clean Developer Edition review org exists for this purpose. See
[SALESFORCE-ENVIRONMENTS.md](SALESFORCE-ENVIRONMENTS.md) §7.

---

## 8. Static Analysis Posture

| Scan | Configuration | Result |
| --- | --- | --- |
| Salesforce Code Analyzer | `AppExchange` ruleset, `code-analyzer.yml` | 0 violations |
| Salesforce Code Analyzer | `Recommended:Security` ruleset | 0 violations |
| Salesforce Code Analyzer | Full PMD ruleset | **1 violation** — `AvoidHardcodingId`, severity 3, in `PEInspectionLogServiceTest`. Test-only; outside both review rulesets. Fix before the next build. |
| Checkmarx | Scan `a0OKX000001JPnJ2AW`, taken at `0.3.0-1` | 0 security, 0 quality issues — **re-run before resubmission** |
| ESLint | `eslint.config.js` (Salesforce LWC config) | Clean |

PMD's JavaScript engine is disabled in `code-analyzer.yml`: its ECMAScript rules produce false
positives against modern LWC patterns. LWC JavaScript is linted by ESLint instead. This is a
documented, deliberate configuration — not a suppression of real findings.

Suppressions are **not** globally disabled (`disable_suppressions: false`), and any in-code
suppression must carry a comment explaining why.

---

## 9. Reporting a Vulnerability

Do not open a public GitHub issue. See [`../SECURITY.md`](../SECURITY.md) for the private reporting
channel and expected response times.

---

## 10. Review Checklist for Authorisation Changes

Any pull request touching `PEAccessGate`, `PermissionExplorerController`, `PEKeysetCursor` or
`PEUserSearchService` must confirm:

- [ ] Every new `@AuraEnabled` method calls the gate as its first statement
- [ ] No authorisation result is cached in a static
- [ ] No user input is concatenated into SOQL
- [ ] Any new sort field is added to the whitelist, not accepted dynamically
- [ ] Any new inspection path writes an audit row — unless it is a *read of the log itself*, which
      must not
- [ ] Any new dynamic SOQL resolves object, field and relationship names through `Schema.SObjectType`
      so it stays correct under the `twinforce` namespace
- [ ] `npm run scan` reports zero violations
- [ ] Apex tests cover both the authorised and unauthorised path
