# Demo and Review Org Seeding

Standing up an org that demonstrates the product honestly, with fictional data only.

This closes a long-open blocker: the AppExchange security reviewer needs an org where the product
visibly does something, and every screenshot and video needs data that is not real.

**Hard rule:** no real subscriber, employee or customer data. Blurring is not sufficient — regenerate
with fictional data instead. See [SECURITY-MODEL.md](SECURITY-MODEL.md) §7.

---

## 1. What the org has to prove

A reviewer, or a prospect watching the demo, should be able to see each of these without being
walked through it:

| # | Must be visible | Needs |
| --- | --- | --- |
| 1 | Permission resolution with attribution | A user with a profile, a direct permission set and a group |
| 2 | **Granted then muted** — the amber state | A group containing a component set *and* a muting set that cancels one of its permissions |
| 3 | Muting correctly **not** applying across groups | A second group muting the same permission, with the user holding it directly |
| 4 | An outdated permission set group | A group with `Status != Updated` |
| 5 | Access without a tab | An object the user can read, in an app with no tab for it |
| 6 | Not-applicable field classification | Formula, auto-number and system audit fields on a custom object |
| 7 | **Exact** record reach | A public-read object with records |
| 8 | **Floor** record reach | A private object with owned records *and* share rows |
| 9 | A reason breakdown with more than one bucket | Manual shares and a sharing rule on the same object |
| 10 | Posture signals that are non-zero but not alarming | A stale group, a dormant user, an unassigned permission set |
| 11 | An inspection log with history | Inspections performed by two different inspectors over several days |
| 12 | The denied path | A user **without** `Use_Permission_Explorer` |

Item 12 matters more than it looks: a reviewer will try it, and the ask-an-administrator message is
the clearest evidence that authorisation lives in Apex rather than in the UI.

---

## 2. Fictional identity set

Use one consistent cast everywhere — org, screenshots, video, listing, security-review documents. A
demo that uses different names in each artefact looks assembled rather than built.

| Role in the story | Name | Username pattern |
| --- | --- | --- |
| Delegated inspector (the hero) | Priya Raman | `priya.raman@<org>.demo` |
| Sales rep, private data | Daniel Okafor | `daniel.okafor@<org>.demo` |
| Sales manager, above Daniel in the hierarchy | Mei-Lin Chen | `meilin.chen@<org>.demo` |
| Support agent, muting case | Tomas Vargas | `tomas.vargas@<org>.demo` |
| Dormant user, never signed in | Agnes Whitlock | `agnes.whitlock@<org>.demo` |
| Over-privileged user, holds View All Data | Robert Nkemdirim | `robert.n@<org>.demo` |
| Unauthorised user, for the denied path | Sofia Brennan | `sofia.brennan@<org>.demo` |

Company names: **Northwind Ceramics**, **Harbourline Logistics**, **Calder & Vale**. Phone numbers
from the `555-01xx` reserved range. Email domain `.demo` or `.example` — never a real TLD.

> Do **not** reuse your own name, your colleagues' names, or any client's name. It reads as sloppy to
> a reviewer and it is the exact failure mode the policy exists to prevent.

---

## 3. Permission scaffolding

Minimum viable set to prove items 1–4 and 10.

```
Profile:  Demo Sales User            (cloned from Standard User)

Permission sets (standalone):
  WSW_Demo_Direct_Export             grants Export Reports
  WSW_Demo_Unassigned                assigned to nobody          → posture signal 4

Permission set groups:
  WSW_Demo_Support_Bundle
    ├── WSW_Demo_Support_Base        grants Export Reports, Manage Cases
    └── WSW_Demo_Support_Mute        MUTING — mutes Export Reports   → amber state

  WSW_Demo_Field_Bundle
    ├── WSW_Demo_Field_Base          grants Manage Cases
    └── WSW_Demo_Field_Mute          MUTING — mutes Export Reports   → must NOT affect
                                                                       a direct grant
```

Assignments:

| User | Holds | Demonstrates |
| --- | --- | --- |
| Tomas Vargas | `WSW_Demo_Support_Bundle` | Granted then muted — amber |
| Priya Raman | `WSW_Demo_Direct_Export` + `WSW_Demo_Field_Bundle` | Muting scoped to its group — **still has** Export Reports |
| Daniel Okafor | Profile only | The clean baseline |

Priya's row is the one to point at in a demo. It is the case that was silently wrong before 0.6, and
it is the case most competitors get wrong.

To produce an **outdated group** (item 4): edit a component set and screenshot within the
recalculation window. It resolves itself in minutes, so capture it when it appears rather than
planning around it.

---

## 4. Record data

For items 7–9, two objects are enough.

| Object | OWD | Seed | Proves |
| --- | --- | --- | --- |
| A standard object, e.g. `Account` | **Public Read/Write** | ~400 records | Exact reach — sharing bypassed, total *is* the answer |
| A custom object, e.g. `Demo_Project__c` | **Private** | ~300 records: 40 owned by Daniel, ~25 manually shared to him, a sharing rule granting a public group he is in | Floor reach, plus a reason breakdown with Owner / Manual / Rule buckets |

Put Mei-Lin above Daniel in the role hierarchy. She is the live illustration of *why* the private
figure is a floor: she reaches Daniel's records, and no share row exists to count that.

Give `Demo_Project__c` a formula field, an auto-number field and a required text field so the field
table shows all three not-applicable reasons (item 6).

Leave one object the demo user can read but that has no tab in the demo app (item 5).

---

## 5. Inspection history

Posture and the log viewer are empty on a fresh org, and an empty panel demos badly.

Before recording or submitting, have **two** inspectors — Priya and one other — work through the
product over at least three different days: resolve several users, open object detail, open Data
Visibility on both objects. This populates the activity chart, the top-inspectors list and the
seven-day count with real shape rather than a single spike.

Do this through the UI, not by inserting rows. Inserted rows will not carry the action and detail
combinations the viewer renders, and the result looks synthetic.

---

## 6. Build order

1. Create the Developer Edition org. Record it in
   [SALESFORCE-ENVIRONMENTS.md](SALESFORCE-ENVIRONMENTS.md).
2. Install the beta from its `04t` ID. **Install the managed package — never deploy source.**
   Namespace-prefixed behaviour, packaged custom permissions and cache partition allocation only
   behave correctly under a real install.
3. Allocate the `PermissionExplorer` Platform Cache partition.
4. Create users (§2), profile and permission scaffolding (§3).
5. Assign `PermissionCheckerPermissionSet` to Priya and Robert. **Leave Sofia without it** (item 12).
6. Create the custom object and seed records (§4).
7. Configure the role hierarchy, sharing rules and manual shares.
8. Generate inspection history (§5).
9. Walk the manual test script in [TESTING.md](TESTING.md) §5 end to end.
10. Capture screenshots and video.

---

## 7. Before handing the org to a reviewer

- [ ] Every username, email, company and phone number is fictional
- [ ] No real data anywhere, including in records created incidentally while testing
- [ ] Priya's view shows the **granted then muted** amber state
- [ ] Priya's view shows Export Reports **held**, despite `WSW_Demo_Field_Mute`
- [ ] Data Visibility shows one **exact** figure and one **floor** figure, each labelled
- [ ] The reason breakdown has at least three buckets
- [ ] Posture shows non-zero signals, each with its remedy text
- [ ] The Inspection Log viewer shows history from two inspectors across several days
- [ ] Logging in as Sofia produces the ask-an-administrator message on every tab, with no data
- [ ] Reviewer credentials are recorded wherever the submission expects them
- [ ] The org will not expire mid-review — check the Developer Edition's login activity requirement
