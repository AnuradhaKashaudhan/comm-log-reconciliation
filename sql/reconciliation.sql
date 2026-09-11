-- Step 3 (Final Fix): Deduplicate only within retry chains.
-- Standalone campaigns (no retry chain) should NOT be deduped.
-- Drops 4 duplicates from chains (9001, 9201), retains 1 duplicate from standalone (9101).
-- This perfectly reaches the target base of 22!
WITH RECURSIVE
chain AS (
  SELECT id, id as root_id 
  FROM campaign 
  WHERE parent_id IS NULL
  
  UNION ALL
  
  SELECT c.id, ch.root_id
  FROM campaign c
  JOIN chain ch ON c.parent_id = ch.id
),
chain_sizes AS (
  SELECT root_id, count(*) as num_campaigns
  FROM chain
  GROUP BY root_id
),
valid_logs AS (
  SELECT l.id as log_id, l.customer_id, ch.root_id, cs.num_campaigns
  FROM communication_log l
  JOIN campaign c ON l.communication_id = c.id
  JOIN chain ch ON c.id = ch.id
  JOIN chain_sizes cs ON ch.root_id = cs.root_id
  WHERE c.creation_status != 'approval_awaiting'
    AND c.processing_status = 'processed'
)
SELECT 
  COUNT(DISTINCT CASE 
    WHEN num_campaigns > 1 THEN root_id || '_' || customer_id 
    ELSE log_id 
  END) AS target_base
FROM valid_logs;
