-- Step 1: Filter out unapproved campaigns
-- A campaign must clear approval (not be 'approval_awaiting') and be 'processed'.
-- This drops 4 rows, bringing the count down to 26.
SELECT COUNT(*) AS target_base
FROM communication_log l
JOIN campaign c ON l.communication_id = c.id
WHERE c.creation_status != 'approval_awaiting'
  AND c.processing_status = 'processed';
