# Diagrams

All diagrams are **Mermaid source embedded in Markdown**. GitHub renders them natively, they diff as
text in review, and they cannot drift out of date the way an exported PNG does.

| # | Diagram | Type | Answers |
| --- | --- | --- | --- |
| 01 | [C4 System Context](01-c4-context.md) | C4 L1 | Who uses this and what does it touch? |
| 02 | [C4 Container](02-c4-container.md) | C4 L2 | What are the deployable/runtime pieces? |
| 03 | [C4 Component — Apex](03-c4-component-apex.md) | C4 L3 | How is the Apex layer decomposed? |
| 04 | [LWC Component Tree](04-lwc-component-tree.md) | Composition | How is the UI assembled? |
| 05 | [Sequence — Resolve User](05-sequence-resolve-user.md) | Sequence | What happens when a user is selected? |
| 06 | [Sequence — Object Detail](06-sequence-object-detail.md) | Sequence | How is field-level security built? |
| 07 | [Permission Resolution Flow](07-permission-resolution-flow.md) | Flowchart | How are grants and muting combined? |
| 08 | [Entity Relationship](08-entity-relationship.md) | ERD | What is stored and what is read? |
| 09 | [UI State Machine](09-ui-state-machine.md) | State | How does WHO/WHERE/WHAT navigation behave? |
| 10 | [Caching and Invalidation](10-caching-dataflow.md) | Flowchart | Where does data come from and when does it go stale? |
| 11 | [Deployment Topology](11-deployment-topology.md) | Deployment | Which orgs, and what flows between them? |
| 12 | [Release Pipeline](12-release-pipeline.md) | Process | How does a change become an installed package? |
| 13 | [Security Trust Boundaries](13-security-trust-boundaries.md) | Threat model | Where is trust established? |

## Editing

Edit the fenced ```mermaid block directly. Preview in VS Code with the Markdown Preview Mermaid
extension, or on <https://mermaid.live>. Do not commit rendered images — the source is the artefact.
