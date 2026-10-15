# Listing Copy

The AppExchange listing text of record, and the rule for what the product is allowed to claim.

Listing: <https://appexchange.salesforce.com/appxListingDetail?listingId=dc0aa216-dbed-49e5-86e0-542869f8dc26>

---

## 1. The claim rule

> **Every claim in the listing must be demonstrable in the reviewer org, by someone who has not been
> briefed.**

That is the whole standard. A claim that needs an explanation, a caveat, or a specific click order is
not demonstrable — it is a sales line with a support ticket attached.

Two corollaries:

- A **floor** is never described as a total. Data Visibility reports at-least figures under a private
  org-wide default; copy must say so or say nothing.
- An **estimate** is never described as a fact. The app column resolves from `AppMenuItem` and is
  disclosed as an estimate in the product. Listing copy must not quietly upgrade it.

---

## 2. Outstanding review

### The subtitle

The listing has carried **"Record Visibility Explorer"** as a subtitle since before any record-level
feature existed. It was flagged as an overclaim and remains on the blocking list.

**0.6 changes the assessment.** Data Visibility genuinely reports record reach, with a reason
breakdown and a record list. The subtitle is now closer to true than false.

It is still not settled, and the decision belongs to a person, not to this document. The question to
answer explicitly:

> Does "Record Visibility Explorer" promise *"tell me whether this user can see this record"*, which
> the product does **not** do and will not do without View All Data — or does it promise *"show me
> how much of this object this user reaches"*, which it now does?

If the first reading is the natural one for a buyer, the subtitle should change. Candidates that are
accurate under both readings:

- *User Access & Record Reach Explorer*
- *See what any user can access — without giving them Setup*
- *Effective Permissions & Record Reach*

Record the decision here when it is made, with the date and who made it.

### Other claim-bearing copy to re-read against 0.6

| Claim area | Current risk | Action |
| --- | --- | --- |
| "Audit defensibility" or similar | Was blocked pending the muting matrix. **The matrix now passes** (`PEMutingMatrixTest`), and the log is readable in-product. The claim is now supportable. | Clear to use, once the Checkmarx re-run is done |
| Coverage or test-count figures | 88% was recorded at `0.3.0-1`. | Do not quote a figure in the listing. Numbers go stale; "every version is tested above the Salesforce floor" does not. |
| "No data leaves your org" | True, and strong. Zero callouts, no Named Credentials, no external endpoints. | Keep. This is the single most load-bearing differentiator. |
| Record type visibility | The catalogue is org-wide, not per-user. | Must not appear as a per-user feature until 0.7. |

---

## 3. Positioning

**One sentence:** Let the people who ask access questions answer them — without handing them Setup.

**The problem, in a buyer's words:** every access question in a Salesforce org routes to the two or
three people with Setup access, and most of those questions are *"why can't I see this"* or *"why can
she see that"*. The admin's choice is to be interrupted, or to grant Setup to someone who should not
have it.

**What the product does about it:** a custom permission, not Setup access. The person who asks
answers it themselves, and every inspection is logged.

### Differentiators, strongest first

1. **Delegation without Setup access.** The gate is a packaged custom permission checked in Apex.
   This is the product, not a feature of it.
2. **Muting permission sets are subtracted, scoped to their own group.** Most tools in the category
   union grants and ignore muting, which produces confidently wrong answers. Scoping it correctly is
   harder than it looks — this product had it wrong until 0.6 and now has a ten-scenario matrix
   proving it.
3. **Zero external calls.** No callouts, no Named Credentials, no Metadata API, no configuration
   burden on the subscriber, no endpoint for a security team to assess.
4. **Append-only audit trail, readable in-product.** Create and Read; never Edit or Delete.
5. **Honest limits.** Floors are labelled, estimates are labelled, and unavailable signals say
   unavailable rather than zero.

Point 5 is unusual enough to sell. In a category full of dashboards that quietly round up, a tool
that tells you what it does not know is the one an auditor trusts.

---

## 4. Assets

| Asset | Status | Source |
| --- | --- | --- |
| Demo video | Live — <https://youtu.be/-_Jabm_uPrs> | Predates 0.6; does not show Data Visibility, Home or the log viewer |
| Screenshots | Existing set audited for copy; language was written for admins rather than for the non-technical audience the product targets | Replacements delivered in the UX/copy audit |
| Reviewer org | **Not yet seeded** | [DEMO-ORG-SEED.md](DEMO-ORG-SEED.md) |

The video is the weakest asset relative to the current product. It demonstrates `0.3`-era scope while
the listing will describe `0.6`. Re-record against the seeded demo org rather than patching it.

---

## 5. Before publishing any listing change

- [ ] Every claim is demonstrable in the seeded reviewer org by someone unbriefed
- [ ] No floor is described as a total; no estimate is described as a fact
- [ ] No coverage percentage or test count appears
- [ ] No feature is described that is not in the **promoted** version — betas do not count
- [ ] Screenshots use the fictional cast from [DEMO-ORG-SEED.md](DEMO-ORG-SEED.md) §2
- [ ] The subtitle decision in §2 is recorded, not assumed
- [ ] Nothing in the copy implies the subscriber must grant View All Data or Modify All Data
