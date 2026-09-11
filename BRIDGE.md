# Target Base Reconciliation Bridge

**Goal:** Reconcile the initial naive count of `communication_log` sends down to the finance target of **22** for merchant 501 in October 2026.

| Step | Description | Result | Reason |
|---|---|---|---|
| 0 | Naive `SELECT COUNT(*)` on `communication_log` | 30 | Starting point. All 30 rows in the raw dataset fall within the basic scope (merchant 501, type 2, Oct 2026). |
| 1 | Filter `creation_status != 'approval_awaiting'` and `processing_status = 'processed'` | 26 | 4 campaigns are dropped because they haven't cleared approval, even though sends exist. |
| 2 | **(Hypothesis)** Dedup by customer across *all* root campaigns | 21 | Deduplicating blindly drops 5 duplicates (4 from retry chains, 1 from standalone campaign 9101). This drops us to 21 (misses target 22). |
| 3 | **(Fix)** Dedup by customer *only* in retry chains (standalone sends are all independent) | 22 | We retain the 1 duplicate send for customer `C20` under standalone campaign `9101`, and drop the 4 duplicates under chains `9001` and `9201`. This perfectly hits the target 22! |
