# 02 — C4 Level 2: Containers

The runtime pieces inside the package boundary.

```mermaid
flowchart TB
    ADMIN["System Administrator"]

    subgraph BROWSER["Lightning Experience — subscriber browser"]
        APP["<b>Who Sees What</b> Lightning app<br/><i>CustomApplication</i>"]
        T1["Permission Explorer tab<br/><i>permissionExplorer LWC</i>"]
        T2["License Inspector tab<br/><i>licenseInspector LWC</i>"]
        T3["Getting Started tab<br/><i>gettingStarted LWC</i>"]
    end

    subgraph APEX["Apex runtime — managed package"]
        CTRL["<b>PermissionExplorerController</b><br/><i>The only @AuraEnabled surface</i>"]
        GATE["<b>PEAccessGate</b><br/><i>Custom permission + audit</i>"]
        SERVICES["<b>Domain services</b><br/>PEPermissionResolver, PEAccessQueryService,<br/>PEAppVisibilityService, PEUserSearchService,<br/>PEUserDetailService, PELicenseInspectorService,<br/>PEOrgStatsService, PEFlsClassifier"]
        INFRA["<b>Infrastructure</b><br/>PECacheManager, PEMetadataCatalog,<br/>PESoqlChunker, PEKeysetCursor,<br/>PEInspectionAuditLogger"]
    end

    subgraph PLATFORM["Salesforce platform"]
        SOQL[("Permission metadata<br/>SOQL, WITH USER_MODE")]
        DESCRIBE[("Schema describes<br/>getGlobalDescribe, DescribeFieldResult")]
        PC[("Platform Cache<br/>org + session partitions")]
        LOGOBJ[("PE_Inspection_Log__c")]
    end

    subgraph CONFIG["Packaged configuration"]
        CP["Use_Permission_Explorer<br/><i>CustomPermission</i>"]
        PS["PermissionCheckerPermissionSet<br/><i>PermissionSet</i>"]
        PART["PermissionExplorer<br/><i>PlatformCachePartition</i>"]
        SR["Static resources<br/><i>logo, walkthrough imagery</i>"]
    end

    ADMIN --> APP
    APP --> T1 & T2 & T3
    T1 & T2 & T3 -->|"@salesforce/apex"| CTRL
    CTRL --> GATE
    GATE -->|"grants"| CP
    CTRL --> SERVICES
    GATE --> INFRA
    SERVICES --> INFRA
    SERVICES --> SOQL
    INFRA --> DESCRIBE
    INFRA --> PC
    INFRA --> LOGOBJ
    PS -->|"assigns"| CP
    PART -.->|"defines"| PC
    T3 --> SR

    classDef ui fill:#e8eef9,stroke:#1b4db1,color:#15181D
    classDef apex fill:#1b4db1,stroke:#123a8a,color:#fff
    classDef plat fill:#F5F3EE,stroke:#15181D,color:#15181D
    classDef cfg fill:#f4f0e4,stroke:#B4801F,color:#15181D
    class APP,T1,T2,T3 ui
    class CTRL,GATE,SERVICES,INFRA apex
    class SOQL,DESCRIBE,PC,LOGOBJ plat
    class CP,PS,PART,SR cfg
```

## Notes

- Three tabs, three exposed LWCs. Every other component is a child and is never surfaced directly.
- All three tabs funnel through one controller — see
  [ADR-0006](../adr/0006-single-auraenabled-controller.md).
- Packaged configuration is drawn separately because it is what the subscriber administrator
  interacts with at install time, not at runtime.
