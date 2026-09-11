# Target Base Reconciliation Bridge

**Goal:** Reconcile the initial naive count of `communication_log` sends down to the finance target of **22** for merchant 501 in October 2026.

| Step | Description | Result | Reason |
|---|---|---|---|
| 0 | Naive `SELECT COUNT(*)` on `communication_log` | 30 | Starting point. All 30 rows in the raw dataset fall within the basic scope (merchant 501, type 2, Oct 2026). |
| 1 | Filter `creation_status != 'approval_awaiting'` and `processing_status = 'processed'` | 26 | 4 campaigns are dropped because they haven't cleared approval, even though sends exist. |
| 2 | **(Hypothesis)** Dedup by customer across *all* root campaigns | 21 | Deduplicating blindly drops 5 duplicates (4 from retry chains, 1 from standalone campaign 9101). This drops us to 21 (misses target 22). |
| 3 | **(Fix)** Dedup by customer *only* in retry chains (standalone sends are all independent) | 22 | We retain the 1 duplicate send for customer `C20` under standalone campaign `9101`, and drop the 4 duplicates under chains `9001` and `9201`. This perfectly hits the target 22! |

## Edge Cases Tested

To ensure the SQL handles potential interview curveballs, I stress-tested the logic against the following synthetic scenarios:

### 1. Chain Depth 3+ Levels
**Scenario:** Does the recursive CTE correctly group a grandparent -> parent -> child chain?
**SQL Test:**
```sql
SELECT l.customer_id, c.id, c.parent_id 
FROM communication_log l 
JOIN campaign c ON l.communication_id = c.id 
WHERE c.id IN (9001, 9002, 9003, 9004) AND l.customer_id = 'C3';
```
**Output:**
```text
C3|9001|
C3|9002|9001
C3|9003|9002
```
**Conclusion:** Yes. Customer `C3` exists across 3 levels (root 9001, child 9002, grandchild 9003). Because the CTE is recursive (`UNION ALL ... JOIN chain`), it assigns `root_id = 9001` to all three levels, allowing the `COUNT(DISTINCT root_id || '_' || customer_id)` to correctly deduplicate all 3 attempts down to exactly 1 reach.

### 2. What if Campaign 9004 is Approved?
**Scenario:** Campaign 9004 targets 4 unique customers (`C11, C12, C13, C14`) not seen elsewhere in the 9001 chain. If its status changed from `approval_awaiting` to `approved`, what happens?
**SQL Test:**
```sql
WITH RECURSIVE
chain AS (SELECT id, id as root_id FROM campaign WHERE parent_id IS NULL UNION ALL SELECT c.id, ch.root_id FROM campaign c JOIN chain ch ON c.parent_id = ch.id),
chain_sizes AS (SELECT root_id, count(*) as num_campaigns FROM chain GROUP BY root_id),
valid_logs AS (
  SELECT l.id as log_id, l.customer_id, ch.root_id, cs.num_campaigns 
  FROM communication_log l
  JOIN campaign c ON l.communication_id = c.id
  JOIN chain ch ON c.id = ch.id
  JOIN chain_sizes cs ON ch.root_id = cs.root_id
  WHERE (CASE WHEN c.id = 9004 THEN 'approved' ELSE c.creation_status END) != 'approval_awaiting'
    AND c.processing_status = 'processed'
)
SELECT COUNT(DISTINCT CASE WHEN num_campaigns > 1 THEN root_id || '_' || customer_id ELSE log_id END) AS target_base
FROM valid_logs;
```
**Output:** `26`
**Conclusion:** The query dynamically adapts. 9004 is part of the 9001 chain. The 4 new distinct customers are successfully deduplicated against the 9001 chain's existing customers, increasing the base perfectly from 22 to 26.

### 3. Fully-Failed Customers
**Scenario:** If a customer in a retry chain fails on every single attempt (`delivery_status = 1100`), do they count?
**SQL Test:** Injecting a synthetic customer `C_FAIL` who fails in 9001 and 9002:
```sql
WITH RECURSIVE
chain AS (SELECT id, id as root_id FROM campaign WHERE parent_id IS NULL UNION ALL SELECT c.id, ch.root_id FROM campaign c JOIN chain ch ON c.parent_id = ch.id),
chain_sizes AS (SELECT root_id, count(*) as num_campaigns FROM chain GROUP BY root_id),
synthetic_log AS (
  SELECT id as log_id, communication_id, customer_id, delivery_status FROM communication_log 
  UNION ALL SELECT 9991, 9001, 'C_FAIL', 1100 
  UNION ALL SELECT 9992, 9002, 'C_FAIL', 1100
),
valid_logs AS (
  SELECT l.log_id, l.customer_id, ch.root_id, cs.num_campaigns 
  FROM synthetic_log l
  JOIN campaign c ON l.communication_id = c.id
  JOIN chain ch ON c.id = ch.id
  JOIN chain_sizes cs ON ch.root_id = cs.root_id
  WHERE c.creation_status != 'approval_awaiting' AND c.processing_status = 'processed'
)
SELECT COUNT(DISTINCT CASE WHEN num_campaigns > 1 THEN root_id || '_' || customer_id ELSE log_id END) AS target_base
FROM valid_logs;
```
**Output:** `23`
**Conclusion:** The query counts them exactly 1 time (increasing the base from 22 to 23). This is mathematically correct: `target_base` tracks the *audience targeted* (the "attempted reach"). If we were asked to compute *successful* reach, we would add `AND l.delivery_status = 900`, but for the base metric, tracking the fully-failed customer once ensures we don't under-count the attempt pool.
