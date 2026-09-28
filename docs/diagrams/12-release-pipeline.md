# 12 — Release Pipeline

From a local change to an installed package version.

```mermaid
flowchart TD
    A["Branch: feat/* · fix/* · style/*"] --> B["Local edit"]
    B --> C{"Husky pre-commit<br/>lint-staged"}
    C -->|fail| B
    C -->|pass| D["Commit + push"]
    D --> E["Pull request → main"]

    E --> F["Review checklist"]
    F --> G{"npm run lint"}
    G -->|fail| B
    G --> H{"npm run test:unit"}
    H -->|fail| B
    H --> I{"npm run scan<br/>AppExchange + Security"}
    I -->|violations| B
    I --> J{"sf apex run test --code-coverage<br/>in wsw-dev"}
    J -->|"below 75%"| B
    J --> K{"Resolver touched?"}
    K -->|yes| L{"Muting correctness matrix<br/>TESTING.md §3"}
    L -->|fail| B
    K -->|no| M
    L -->|pass| M["Merge to main"]

    M --> N["Bump versionNumber + versionName<br/>in sfdx-project.json"]
    N --> O["Update CHANGELOG.md"]
    O --> P["sf package version create<br/>--code-coverage --target-dev-hub WSWDevHub"]

    P --> Q{"Ancestry check<br/>ancestorVersion: HIGHEST"}
    Q -->|"would break subscribers"| R["❌ Creation fails<br/><i>the guard working</i>"]
    R --> B
    Q -->|ok| S["04t beta version created<br/>packageAliases updated"]

    S --> T["Install into WhoSeesWhat org"]
    T --> U["Manual test script<br/>TESTING.md §5<br/><i>against the managed package</i>"]
    U --> V["Upgrade test:<br/>prior promoted version → this beta"]
    V -->|fail| B
    V -->|pass| W{"Promote?"}

    W -->|no| X["Remain a beta"]
    W -->|yes| Y["sf package version promote<br/><b>irreversible</b>"]
    Y --> Z["git tag v<version>"]
    Z --> AA["Partner Console:<br/>listing + security review"]
    AA --> AB(["Installable by subscribers"])

    classDef gate fill:#faf1de,stroke:#B4801F,color:#15181D
    classDef fail fill:#fbeceb,stroke:#C0483C,color:#15181D
    classDef done fill:#e6f4ef,stroke:#1F8A6B,color:#15181D
    class C,G,H,I,J,K,L,Q,W gate
    class R fail
    class AB,Y done
```

## Gates that must not be skipped

| Gate | Why |
| --- | --- |
| `npm run scan` zero violations | The AppExchange security review runs the same rulesets |
| 75% Apex coverage | Salesforce refuses to create the version below it |
| Muting correctness matrix | The product's core claim; fails silently if wrong |
| Manual test against the **installed package** | Namespace prefixes, packaged custom permissions and cache partitions only behave correctly under a real install |
| Upgrade test from the prior promoted version | Subscribers upgrade; they do not install fresh |

## Irreversibility

Promotion cannot be undone. There is no un-promote. Recovery is forward-only: ship a patch version,
or deprecate the version so it can no longer be installed. That asymmetry is why every gate above
sits *before* the promote step. See [RELEASE-PROCESS.md](../RELEASE-PROCESS.md) §9.
