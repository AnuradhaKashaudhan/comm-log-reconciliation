-- Step 2 (Hypothesis): Deduplicate by customer within the same root campaign.
-- What if we assume every campaign (standalone or chain) should be deduped?
-- This drops 5 rows (1 from standalone, 4 from chains), bringing count to 21. (Misses target 22)
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
valid_logs AS (
  SELECT l.customer_id, ch.root_id
  FROM communication_log l
  JOIN campaign c ON l.communication_id = c.id
  JOIN chain ch ON c.id = ch.id
  WHERE c.creation_status != 'approval_awaiting'
    AND c.processing_status = 'processed'
)
SELECT COUNT(DISTINCT root_id || '_' || customer_id) AS target_base
FROM valid_logs;
