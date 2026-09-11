# Comm-Log Reconciliation

This repository contains the SQL queries and step-by-step reasoning used to reconcile the raw `communication_log` data to Finance's `target_base` of **22** for merchant `501` in October 2026.

## How to Run

You can execute the final reconciliation query against the provided SQLite database using the following command:

```powershell
Get-Content sql/reconciliation.sql | sqlite3 data/comm_log.db
# OR from inside the sqlite prompt:
# sqlite3 data/comm_log.db ".read sql/reconciliation.sql"
```

## Surprises in the Data

During the investigation, a few nuances in the data dictionary proved critical to hitting the exact target base:

1. **Pending Approvals Count as Sent in the Raw Log:** There were 4 sends in `communication_log` attached to campaigns where `creation_status = 'approval_awaiting'`. Even though the send pipeline executed for these, they must be excluded because the campaign workflow is not finalized.
2. **Standalone vs. Chain Deduplication:** The rule stating that *standalone campaigns are not deduplicated* was the trickiest part. At first glance, you might want to deduplicate any customer who received multiple messages in the same underlying campaign. However, doing so blindly misses the target.

### Real Row-Level Evidence: The Standalone Exception

To hit the target of `22`, we must handle retry chains and standalone campaigns differently:

- **Retry Chains:** Campaign `9001` is the root of a retry chain. Customer `C3` appears **3 times** in this chain. Since it's a chain, we deduplicate these 3 sends down to **1** qualifying reach.
- **Standalone Campaigns:** Campaign `9101` has no parent and no children (it's completely standalone). Customer `C20` appears **2 times** in this campaign (likely because the campaign was independently re-run, which the README notes is distinct from a retry). According to the rules, standalone campaigns count *every* send independently. If we mistakenly deduplicated `C20` for campaign `9101`, our final count would drop to **21**, breaking the bridge.

By utilizing a recursive CTE to count the depth of each campaign chain, we conditionally apply the deduplication logic *only* to chains (depth > 1). This retains both sends for `C20` in `9101`, and perfectly lands us at the target base of `22`.
