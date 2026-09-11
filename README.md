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

While implementing the SQL, I assumed that the `target_base` metric represents the *attempted audience* rather than exclusively *successfully delivered* messages. As a result, the query intentionally does not filter by `delivery_status = 900`. If a customer soft-failed (`1100`) on every single attempt within a retry chain, they still count exactly once toward the target base pool. I also assumed that because no customers overlapped between different chains in this dataset, a global `GROUP BY customer_id` is a mathematically safe shortcut for the `sanity_check.sql` query.

## Surprises in the Data

During the investigation, a few nuances in the data dictionary proved critical to hitting the exact target base:

1. **Pending Approvals Count as Sent in the Raw Log:** There were 4 sends in `communication_log` attached to campaigns where `creation_status = 'approval_awaiting'`. Even though the send pipeline executed for these, they must be excluded because the campaign workflow is not finalized.
2. **Standalone vs. Chain Deduplication:** The rule stating that *standalone campaigns are not deduplicated* was the trickiest part. At first glance, you might want to deduplicate any customer who received multiple messages in the same underlying campaign. However, doing so blindly misses the target.

### Real Row-Level Evidence: The Standalone Exception

To hit the target of `22`, we must handle retry chains and standalone campaigns differently:

- **Retry Chains:** Campaign `9001` is the root of a retry chain. Customer `C3` appears **3 times** in this chain. Since it's a chain, we deduplicate these 3 sends down to **1** qualifying reach.
- **Standalone Campaigns:** Campaign `9101` has no parent and no children (it's completely standalone). Customer `C20` appears **2 times** in this campaign (likely because the campaign was independently re-run, which the README notes is distinct from a retry). According to the rules, standalone campaigns count *every* send independently. If we mistakenly deduplicated `C20` for campaign `9101`, our final count would drop to **21**, breaking the bridge.

By utilizing a recursive CTE to count the depth of each campaign chain, we conditionally apply the deduplication logic *only* to chains (depth > 1). This retains both sends for `C20` in `9101`, and perfectly lands us at the target base of `22`.
