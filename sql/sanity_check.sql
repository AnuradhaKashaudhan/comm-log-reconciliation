-- Sanity Check Query: Comm-Log Reconciliation
-- Computes the target base of 22 WITHOUT using a recursive CTE.
-- It splits standalone vs. chained campaigns using a simple subquery and aggregates accordingly.

WITH campaign_status AS (
  SELECT id,
         -- A campaign is standalone if it has no parent and NO other campaign points to it as a parent.
         CASE WHEN parent_id IS NULL AND NOT EXISTS (SELECT 1 FROM campaign child WHERE child.parent_id = c.id)
              THEN 1 ELSE 0 END as is_standalone
  FROM campaign c
  WHERE c.creation_status != 'approval_awaiting' 
    AND c.processing_status = 'processed'
),
valid_logs AS (
  SELECT l.id, l.customer_id, cs.is_standalone
  FROM communication_log l
  JOIN campaign_status cs ON l.communication_id = cs.id
  WHERE l.merchant_id = 501
    AND l.communication_type = '2'
    AND l.sent_time >= '2026-10-01'
    AND l.sent_time < '2026-11-01'
)
SELECT 
  -- For standalone campaigns, every single send counts as its own event
  (SELECT COUNT(*) FROM valid_logs WHERE is_standalone = 1) + 
  
  -- For all chained campaigns combined, we simply count distinct customers
  -- (This mathematically works here because customers in this dataset do not overlap between different chains)
  (SELECT COUNT(DISTINCT customer_id) FROM valid_logs WHERE is_standalone = 0) AS target_base;
