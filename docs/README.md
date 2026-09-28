# Who Sees What — Documentation

Documentation index for the Who Sees What managed package.

## Start here

| If you are... | Read |
| --- | --- |
| New to the codebase | [ARCHITECTURE.md](ARCHITECTURE.md) then [diagrams/](diagrams/) |
| Setting up a machine | [DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md), [SALESFORCE-ENVIRONMENTS.md](SALESFORCE-ENVIRONMENTS.md) |
| Changing the resolver | [PERMISSION-RESOLUTION.md](PERMISSION-RESOLUTION.md), [TESTING.md](TESTING.md) |
| Wiring a new LWC to Apex | [API-REFERENCE.md](API-REFERENCE.md) |
| Preparing a release | [RELEASE-PROCESS.md](RELEASE-PROCESS.md), [../CHANGELOG.md](../CHANGELOG.md) |
| Answering a security reviewer | [SECURITY-MODEL.md](SECURITY-MODEL.md) |
| Stuck on a platform error | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| Wondering why something is the way it is | [adr/](adr/) |

## Contents

### Reference
- [ARCHITECTURE.md](ARCHITECTURE.md) — layers, boundaries, quality attributes
- [DATA-MODEL.md](DATA-MODEL.md) — custom object, DTOs, platform objects consumed
- [API-REFERENCE.md](API-REFERENCE.md) — the `@AuraEnabled` surface
- [PERMISSION-RESOLUTION.md](PERMISSION-RESOLUTION.md) — the resolution algorithm
- [SECURITY-MODEL.md](SECURITY-MODEL.md) — threat model and review posture
- [GLOSSARY.md](GLOSSARY.md) — domain vocabulary

### Operational
- [DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md)
- [TESTING.md](TESTING.md)
- [RELEASE-PROCESS.md](RELEASE-PROCESS.md)
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- [SALESFORCE-ENVIRONMENTS.md](SALESFORCE-ENVIRONMENTS.md)
- [CLEANUP-CANDIDATES.md](CLEANUP-CANDIDATES.md)

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
