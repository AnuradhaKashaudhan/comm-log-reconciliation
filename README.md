# Comm-Log Reconciliation

This repository contains the SQL queries and step-by-step reasoning used to reconcile the raw `communication_log` data to Finance's `target_base` of **22** for merchant `501` in October 2026.

## How to Verify

You can execute the primary reconciliation query, as well as a simpler `GROUP BY` sanity-check query, using the following commands depending on your terminal:

**Bash / Unix:**
```bash
sqlite3 data/comm_log.db < sql/reconciliation.sql
sqlite3 data/comm_log.db < sql/sanity_check.sql
```

**PowerShell (Windows):**
```powershell
Get-Content sql/reconciliation.sql | sqlite3 data/comm_log.db
Get-Content sql/sanity_check.sql | sqlite3 data/comm_log.db
```

## Assumptions

Because a few nuances weren't 100% explicit in the data dictionary, I made the following verifiable assumptions to compute the metric:

1. **Fully-Failed Customers Still Count as "Reached":** The prompt defines `target_base` as "how many distinct customers were reached". I assumed this means *attempted audience* (targeted) rather than *successfully delivered*. Thus, my query intentionally does not filter by `delivery_status = 900`. If a customer soft-fails (`1100`) on every single attempt within a retry chain, my query mathematically retains them, counting them exactly **once**. (I verified this by injecting a synthetic fully-failed customer into the data; the base correctly incremented by 1).
2. **Cost & Scheduling Fields are Irrelevant:** I assumed `credit_used` and `scheduled_time` have no bearing on the `target_base`. The metric measures distinct customers, not budget. Additionally, the timeframe scope ("October 2026") evaluates `sent_time` (when the reach actually occurred), rather than `scheduled_time`. 
3. **Approval Status is Evaluated per Campaign:** The rule states that a campaign must clear approval to count. I assumed this applies strictly to the *immediate* campaign triggering the send, rather than being inherited from the chain's root. In the data, root campaign `9001` is `approved`, but its retry child `9004` is `approval_awaiting`. The query independently evaluates `c.creation_status` for every send's direct campaign ID, successfully excluding `9004`'s logs while retaining `9001-9003`.
4. **Global `GROUP BY` Shortcut:** For the sanity check query, I assumed a global `GROUP BY customer_id` is mathematically safe for chained campaigns because I empirically verified that no customers overlap between *different* chains in this specific dataset.

## Surprises in the Data

During the investigation, a few nuances in the data dictionary proved critical to hitting the exact target base:

1. **Pending Approvals Count as Sent in the Raw Log:** There were 4 sends in `communication_log` attached to campaigns where `creation_status = 'approval_awaiting'`. Even though the send pipeline executed for these, they must be excluded because the campaign workflow is not finalized.
2. **Standalone vs. Chain Deduplication:** The rule stating that *standalone campaigns are not deduplicated* was the trickiest part. At first glance, you might want to deduplicate any customer who received multiple messages in the same underlying campaign. However, doing so blindly misses the target.

### Real Row-Level Evidence: The Standalone Exception

To hit the target of `22`, we must handle retry chains and standalone campaigns differently:

- **Retry Chains:** Campaign `9001` is the root of a retry chain. Customer `C3` appears **3 times** in this chain. Since it's a chain, we deduplicate these 3 sends down to **1** qualifying reach.
- **Standalone Campaigns:** Campaign `9101` has no parent and no children (it's completely standalone). Customer `C20` appears **2 times** in this campaign (likely because the campaign was independently re-run, which the README notes is distinct from a retry). According to the rules, standalone campaigns count *every* send independently. If we mistakenly deduplicated `C20` for campaign `9101`, our final count would drop to **21**, breaking the bridge.

By utilizing a recursive CTE to count the depth of each campaign chain, we conditionally apply the deduplication logic *only* to chains (depth > 1). This retains both sends for `C20` in `9101`, and perfectly lands us at the target base of `22`.
