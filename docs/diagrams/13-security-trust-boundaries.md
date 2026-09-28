# 13 — Security Trust Boundaries

Where trust is established, and what each boundary defends against.

```mermaid
flowchart TB
    subgraph U["Zone 0 — Untrusted input"]
        BROWSER["Subscriber browser<br/>LWC components"]
        DIRECT["Direct @AuraEnabled invocation<br/><i>bypassing the UI entirely</i>"]
        CURSOR["Pagination cursors<br/>URL deep-link parameters<br/>Search terms and filters"]
    end

    subgraph B1["Boundary 1 — Authorisation"]
        GATE["<b>PEAccessGate</b><br/>FeatureManagement.checkPermission<br/>('Use_Permission_Explorer')<br/><i>uncached, in Apex, first statement</i>"]
    end

    subgraph B2["Boundary 2 — Input validation"]
        CURV["PEKeysetCursor.decode<br/><i>structure + sort whitelist</i>"]
        BIND["Bound variables only<br/><i>SOQL from constant fragments</i>"]
        TARGET["assertInspectable<br/><i>exists and is active</i>"]
        BUDGET["PESoqlChunker.assertQueryBudget"]
    end

    subgraph B3["Boundary 3 — Platform enforcement"]
        SHARING["with sharing on every class"]
        USERMODE["WITH USER_MODE on user-facing queries"]
        SETUPPERM["Subscriber's own<br/>View Setup and Configuration"]
    end

    subgraph T["Zone 3 — Trusted"]
        SVC["Domain services"]
        DATA[("Subscriber permission metadata")]
    end

    subgraph AUD["Accountability — not a boundary, a consequence"]
        LOG["PE_Inspection_Log__c<br/><b>Create + Read only</b><br/>Edit · Delete · ViewAll · ModifyAll withheld"]
    end

    EGRESS["External systems"]

    BROWSER --> GATE
    DIRECT --> GATE
    CURSOR --> GATE
    GATE -->|denied| DENY["Typed NOT_AUTHORISED<br/>retryable = false<br/>no data returned"]
    GATE -->|authorised| CURV
    GATE ==>|"same call — cannot be decoupled"| LOG
    CURV --> BIND --> TARGET --> BUDGET --> SHARING
    SHARING --> USERMODE --> SETUPPERM --> SVC --> DATA
    SVC -.->|"NO callouts · NO Named Credentials<br/>NO Metadata API · NO egress"| EGRESS

    classDef untrust fill:#fbeceb,stroke:#C0483C,color:#15181D
    classDef bound fill:#faf1de,stroke:#B4801F,color:#15181D
    classDef trust fill:#e6f4ef,stroke:#1F8A6B,color:#15181D
    classDef none fill:#f1f0ee,stroke:#B4B0A8,color:#6b6862,stroke-dasharray:4 3
    class BROWSER,DIRECT,CURSOR untrust
    class GATE,CURV,BIND,TARGET,BUDGET,SHARING,USERMODE,SETUPPERM bound
    class SVC,DATA,LOG trust
    class EGRESS none
```

## What each boundary defends

| Boundary | Threat | Control |
| --- | --- | --- |
| 1 — Authorisation | Anyone invoking Apex directly, bypassing the UI | Gate in Apex, first statement of every method, never in the UI alone |
| 1 — Authorisation | A cached decision outliving its context (`System.runAs`) | `checkPermission` is deliberately uncached |
| 2 — Input validation | SOQL injection via search terms or sort fields | Bound variables; dynamic SOQL assembled from constant fragments; sort whitelist |
| 2 — Input validation | Tampered pagination cursor | `decode` validates and throws `BAD_CURSOR` |
| 2 — Input validation | Governor-limit exhaustion via a wide permission graph | `assertQueryBudget` before fan-out |
| 3 — Platform | CRUD/FLS bypass | `with sharing` everywhere, `WITH USER_MODE` |
| 3 — Platform | Reading permission metadata the admin cannot read | Subscriber's own View Setup and Configuration still applies |
| Accountability | Untraceable inspections | `assertAuthorisedAndLog` couples gate and audit in one call |
| Accountability | Inspector erasing their own trail | Edit and Delete withheld on the audit object |
| Egress | Data exfiltration | No callouts, no Named Credentials, no Metadata API, no external endpoints |

The heavy edge from the gate to the audit log is the important one: an inspection **cannot** occur
without producing a log row, because the same call does both. See
[ADR-0002](../adr/0002-custom-permission-gate-and-audit.md) and
[SECURITY-MODEL.md](../SECURITY-MODEL.md).
