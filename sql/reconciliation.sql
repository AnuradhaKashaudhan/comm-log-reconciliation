-- Comm-Log Reconciliation Query
-- Scope: merchant_id = 501, communication_type = '2', Oct 2026.

WITH RECURSIVE
-- CTE 1: Resolve retry chains to their root campaign.
-- Implements: "A campaign can be a retry of an earlier campaign... parent_id pointing back at the original."
chain AS (
  -- Base case: campaigns that are not retries of anything
  SELECT id, id as root_id 
  FROM campaign 
  WHERE parent_id IS NULL
  
  UNION ALL
  
  -- Recursive step: traverse down the retry chain
  SELECT c.id, ch.root_id
  FROM campaign c
  JOIN chain ch ON c.parent_id = ch.id
),

-- CTE 2: Determine if a chain is standalone or has retries.
-- Implements: "A campaign with no retry chain at all (no other campaign points at it, and it points at nothing) is a standalone communication"
chain_sizes AS (
  SELECT root_id, count(*) as num_campaigns
  FROM chain
  GROUP BY root_id
),

-- CTE 3: Filter campaigns based on lifecycle status and apply scope.
-- Implements: "A campaign is included in official reporting only once both its creation workflow has cleared... and its processing has completed."
-- Implements: "A campaign still approval_awaiting has not been signed off and does not count"
valid_logs AS (
  SELECT l.id as log_id, l.customer_id, ch.root_id, cs.num_campaigns
  FROM communication_log l
  JOIN campaign c ON l.communication_id = c.id
  JOIN chain ch ON c.id = ch.id
  JOIN chain_sizes cs ON ch.root_id = cs.root_id
  WHERE c.creation_status != 'approval_awaiting'  -- Creation cleared
    AND c.processing_status = 'processed'         -- Processing completed
    AND l.merchant_id = 501                       -- Scope constraint
    AND l.communication_type = '2'                -- Scope constraint
    AND l.sent_time >= '2026-10-01'               -- Scope constraint
    AND l.sent_time < '2026-11-01'                -- Scope constraint
)

-- Final Aggregation: Deduplicate only within retry chains.
-- Implements: "for a given underlying communication (a campaign plus every retry chained off it), how many distinct customers were reached? ... still counts once."
-- Implements: "...standalone communication — every send under it is its own event, whether or not the same customer appears twice."
SELECT 
  COUNT(DISTINCT CASE 
    -- If it's part of a retry chain (num_campaigns > 1), count the distinct customer across the whole root chain once.
    WHEN num_campaigns > 1 THEN root_id || '_' || customer_id 
    -- If it's a standalone campaign, every send is its own distinct event.
    ELSE log_id 
  END) AS target_base
FROM valid_logs;
