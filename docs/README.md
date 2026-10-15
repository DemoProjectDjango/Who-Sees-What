# Who Sees What — Documentation

Documentation index for the Who Sees What managed package.

**Current:** `0.6.0-2` beta · latest promoted `0.3.0-1` · namespace `twinforce` · API 67.0

## Start here

| If you are... | Read |
| --- | --- |
| New to the codebase | [ARCHITECTURE.md](ARCHITECTURE.md) then [diagrams/](diagrams/) |
| Setting up a machine | [DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md), [SALESFORCE-ENVIRONMENTS.md](SALESFORCE-ENVIRONMENTS.md) |
| Changing the resolver | [PERMISSION-RESOLUTION.md](PERMISSION-RESOLUTION.md), [TESTING.md](TESTING.md) |
| Changing Data Visibility | [RECORD-VISIBILITY.md](RECORD-VISIBILITY.md), [TESTING.md](TESTING.md) §3b |
| Changing anything that logs | [AUDIT-TRAIL.md](AUDIT-TRAIL.md) |
| Wiring a new LWC to Apex | [API-REFERENCE.md](API-REFERENCE.md) |
| Preparing a release | [RELEASE-PROCESS.md](RELEASE-PROCESS.md), [../CHANGELOG.md](../CHANGELOG.md), [UPGRADE-NOTES.md](UPGRADE-NOTES.md) |
| Running the whole product lifecycle | [PIPELINE.md](PIPELINE.md) |
| Answering a security reviewer | [SECURITY-MODEL.md](SECURITY-MODEL.md), [DEMO-ORG-SEED.md](DEMO-ORG-SEED.md) |
| Writing listing or marketing copy | [LISTING-COPY.md](LISTING-COPY.md) |
| Deciding what to build next | [ROADMAP.md](ROADMAP.md) |
| Stuck on a platform error | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| Wondering why something is the way it is | [adr/](adr/) |

## Contents

### Reference
- [ARCHITECTURE.md](ARCHITECTURE.md) — layers, boundaries, quality attributes
- [DATA-MODEL.md](DATA-MODEL.md) — custom object, DTOs, platform objects consumed
- [API-REFERENCE.md](API-REFERENCE.md) — the `@AuraEnabled` surface
- [PERMISSION-RESOLUTION.md](PERMISSION-RESOLUTION.md) — the resolution algorithm, including muting
- [RECORD-VISIBILITY.md](RECORD-VISIBILITY.md) — how record reach is computed, and when it is exact
- [AUDIT-TRAIL.md](AUDIT-TRAIL.md) — what is logged, what deliberately is not, retention
- [SECURITY-MODEL.md](SECURITY-MODEL.md) — threat model and review posture
- [GLOSSARY.md](GLOSSARY.md) — domain vocabulary

### Operational
- [PIPELINE.md](PIPELINE.md) — idea → build → security review → patch loop
- [DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md)
- [TESTING.md](TESTING.md)
- [RELEASE-PROCESS.md](RELEASE-PROCESS.md)
- [UPGRADE-NOTES.md](UPGRADE-NOTES.md) — written for the subscriber, not for us
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- [SALESFORCE-ENVIRONMENTS.md](SALESFORCE-ENVIRONMENTS.md)
- [DEMO-ORG-SEED.md](DEMO-ORG-SEED.md) — seeding the reviewer and demo org with fictional data
- [CLEANUP-CANDIDATES.md](CLEANUP-CANDIDATES.md)

### Product
- [ROADMAP.md](ROADMAP.md) — sequencing, prerequisites, and features declined by design
- [LISTING-COPY.md](LISTING-COPY.md) — AppExchange copy of record and the claim rule

### Decisions
- [adr/README.md](adr/README.md) — index of Architecture Decision Records

### Diagrams
- [diagrams/README.md](diagrams/README.md) — index of all diagrams

## Conventions

- Diagrams are **Mermaid source inside Markdown**. GitHub renders them natively; they diff as text
  and never go stale as a binary export would.
- Every non-obvious constraint gets a note explaining *why*, not just *what*. Most of the
  limitations in this product cost real time to discover.
- Documents are updated in the same pull request as the change they describe.
- **State what is not known.** A documented floor, estimate or unavailable signal is more useful than
  a confident number that is wrong. The product holds itself to this; the documentation should too.
