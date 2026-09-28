# 11 — Deployment Topology

Orgs, repository and what flows between them.

```mermaid
flowchart LR
    subgraph LOCAL["Developer workstation"]
        WS["D:\Product\PermissionChecker\PermissionChecker<br/>VS Code · Salesforce CLI · Node"]
    end

    subgraph GH["GitHub — DemoProjectDjango"]
        REPO["Who-Sees-What<br/>github.com/DemoProjectDjango/Who-Sees-What<br/><i>account: demoorgsalesforce@gmail.com</i>"]
        MAIN["main — protected"]
        FEAT["feat/* · fix/* · style/* · docs/*"]
    end

    subgraph SF["Salesforce orgs"]
        DEVHUB["<b>WSWDevHub</b><br/>nilufa.tforce-abyj@force.com<br/>00DdN00000roILEUA2<br/><i>owns package 0HoOW00000000ZV0AY</i>"]
        DEV["<b>wsw-dev</b><br/>ishann.tforce.a3cd5122e44a@agentforce.com<br/>00DgK00000a8MoDUAU<br/><i>primary development</i>"]
        SCRATCH["<b>wsw-scratch</b><br/><i>ephemeral, 7 days</i>"]
        TEST["<b>WhoSeesWhat</b><br/>ishann.tforce.3eaafb93063e@agentforce.com<br/>00DgL00000ZdsQzUAJ<br/><i>package install testing</i>"]
        REVIEW["<b>Security review org</b><br/><i>not yet provisioned</i><br/>fictional seeded data"]
    end

    subgraph AE["Distribution"]
        PARTNER["Partner Console<br/>listing + security review"]
        SUB["Subscriber orgs"]
    end

    subgraph DANGER["Unrelated — do NOT deploy here"]
        VSC["vscodeOrg<br/>saiful@momentum-worldwide.com<br/>00DAq00000AT6cTMAT"]
        OTHER["formBuilder · ishanTNB · isij-prod<br/>momentum@arrivehomeownership.org"]
    end

    WS -->|"git push"| FEAT
    FEAT -->|"pull request"| MAIN
    MAIN -->|"git pull"| WS
    WS -->|"sf project deploy start<br/>--target-org wsw-dev"| DEV
    WS -->|"sf org create scratch<br/>--target-dev-hub WSWDevHub"| SCRATCH
    DEVHUB -.->|"authorises"| SCRATCH
    WS -->|"sf package version create<br/>--target-dev-hub WSWDevHub"| DEVHUB
    DEVHUB -->|"04t beta version"| TEST
    DEVHUB -->|"04t beta version"| REVIEW
    DEVHUB -->|"promote"| PARTNER
    PARTNER -->|"install"| SUB
    REVIEW -->|"security review"| PARTNER

    WS -.->|"⚠ wrong-org hazard"| VSC

    classDef danger fill:#fbeceb,stroke:#C0483C,color:#C0483C,stroke-dasharray:4 3
    classDef hub fill:#1b4db1,stroke:#123a8a,color:#fff
    classDef org fill:#e8eef9,stroke:#1b4db1,color:#15181D
    classDef pending fill:#faf1de,stroke:#B4801F,color:#15181D
    class VSC,OTHER,DANGER danger
    class DEVHUB hub
    class DEV,SCRATCH,TEST org
    class REVIEW pending
```

## The hazard

`vscodeOrg` resolves to `saiful@momentum-worldwide.com`, an org belonging to an entirely different
engagement. A stray `sf project deploy start` without an explicit target has landed there before.

```powershell
sf config set target-org=wsw-dev
sf config set target-dev-hub=WSWDevHub
sf config get target-org --verbose
```

Pass `--target-org wsw-dev` explicitly on every deploy regardless of configuration. Full inventory:
[SALESFORCE-ENVIRONMENTS.md](../SALESFORCE-ENVIRONMENTS.md).
