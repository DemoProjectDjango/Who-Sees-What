# Security Policy

## Supported Versions

| Version | Supported |
| --- | --- |
| 0.5.x (beta) | ✅ Active development |
| 0.3.0-1 (released) | ✅ Security fixes |
| 0.2.x and earlier | ❌ Upgrade required |

Only the latest promoted version receives security fixes. Salesforce 2GP promotion is irreversible,
so remediation is always forward — a patch version, never a rollback.

---

## Reporting a Vulnerability

**Do not open a public GitHub issue for a security vulnerability.**

Report privately to Twinforce Solutions Limited through the vendor contact listed on the AppExchange
listing, or via the repository's private security advisory channel:

<https://github.com/DemoProjectDjango/Who-Sees-What/security/advisories/new>

### Include

- Affected package version (`04t` ID if known)
- Org type where it reproduces (scratch, Developer Edition, sandbox, production)
- Reproduction steps
- Impact — what an attacker gains
- Any proof of concept

**Redact real usernames, emails, org IDs and record data** from your report. A description of the
data class is sufficient.

### Response

| Stage | Target |
| --- | --- |
| Acknowledgement | 3 business days |
| Initial assessment | 10 business days |
| Fix or mitigation plan | Severity-dependent, communicated at assessment |

We will keep you informed and credit you in the release notes unless you prefer otherwise.

---

## Scope

### In scope

- Authorisation bypass of the `Use_Permission_Explorer` custom permission gate
- SOQL injection through search terms, filters, cursors or deep-link parameters
- Sharing, CRUD or FLS bypass allowing access to data the running user should not see
- Tampering with or suppressing `PE_Inspection_Log__c` audit rows
- Cache poisoning that causes one user's resolved access to be served for another
- Any data egress from a subscriber org

### Out of scope

- Salesforce platform vulnerabilities — report those to Salesforce
- Issues requiring an already-compromised administrator session
- Misconfiguration in a subscriber org (for example, assigning the permission set too widely)
- Denial of service through deliberate governor-limit exhaustion
- Known platform limitations documented in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) §7

---

## Security Posture

- **No external calls.** No HTTP callouts, Named Credentials, External Credentials or Metadata API
  callouts. Nothing leaves the subscriber org.
- **Read-only.** The only DML in the product is an append-only audit insert.
- **Gated in Apex.** Every `@AuraEnabled` method calls `PEAccessGate` as its first statement. The
  check is deliberately uncached.
- **Audited.** Gate and audit are the same call, so an inspection cannot happen without a log row.
  Edit and Delete are withheld on the audit object.
- **Scanned.** Checkmarx and Salesforce Code Analyzer (AppExchange + Security rulesets) report zero
  findings.

Full detail: [`docs/SECURITY-MODEL.md`](docs/SECURITY-MODEL.md).

---

## Handling Credentials

Never commit to this repository: passwords, security tokens, access or refresh tokens, SFDX auth
URLs, connected app consumer secrets, or JWT private keys.

If a credential is committed, treat it as compromised: revoke it first, then remove it from history.
Removing the commit without revoking is not a fix.
