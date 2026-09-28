# 01 — C4 Level 1: System Context

Who interacts with Who Sees What, and what it depends on.

```mermaid
flowchart TB
    ADMIN["System Administrator<br/><i>Primary user</i><br/>Holds the Use_Permission_Explorer<br/>custom permission"]
    BIZ["Business user / executive<br/><i>Secondary user</i><br/>Answers access questions<br/>without Setup access"]
    AUDITOR["Compliance reviewer<br/><i>Consumer of the audit trail</i>"]
    SFADMIN["Salesforce administrator<br/><i>Installs and configures</i>"]

    WSW(["<b>Who Sees What</b><br/>Managed package, namespace twinforce<br/><br/>Resolves effective user access across<br/>apps, objects and fields, and attributes<br/>every grant to its source"])

    ORG[("Subscriber Salesforce org<br/>Users, profiles, permission sets,<br/>permission set groups, muting sets,<br/>object and field permissions, licenses")]
    CACHE[("Platform Cache<br/>PermissionExplorer partition<br/><i>optional</i>")]
    LOG[("PE_Inspection_Log__c<br/>Append-only audit trail")]
    AE["Salesforce AppExchange<br/><i>Distribution</i>"]

    ADMIN -->|"inspects user access"| WSW
    BIZ -->|"answers access questions"| WSW
    SFADMIN -->|"installs, assigns permission set,<br/>allocates cache"| WSW
    AUDITOR -->|"reviews inspection history"| LOG

    WSW -->|"reads permission metadata<br/>SOQL, WITH USER_MODE"| ORG
    WSW -->|"caches resolved graphs<br/>degrades gracefully if absent"| CACHE
    WSW -->|"writes one row per inspection<br/><b>only write in the product</b>"| LOG
    AE -.->|"distributes"| WSW

    EXT["Any external system"]
    WSW -.->|"<b>NO</b> callouts, Named Credentials,<br/>Metadata API or egress"| EXT

    classDef sys fill:#1b4db1,stroke:#123a8a,color:#fff
    classDef person fill:#F5F3EE,stroke:#15181D,color:#15181D
    classDef store fill:#e8eef9,stroke:#1b4db1,color:#15181D
    classDef none fill:#fbeceb,stroke:#C0483C,color:#C0483C,stroke-dasharray:4 3
    class WSW sys
    class ADMIN,BIZ,AUDITOR,SFADMIN person
    class ORG,CACHE,LOG,AE store
    class EXT none
```

## Notes

- The **delegation USP** is visible here: the secondary user reaches the system without ever
  traversing Setup.
- The dashed red edge is a deliberate architectural statement, not an omission. See
  [ADR-0001](../adr/0001-read-only-no-callouts.md).
- The audit trail is drawn as an external consumer relationship because a compliance reviewer reads
  it through Salesforce reporting, not through the product UI (a viewer is planned).
