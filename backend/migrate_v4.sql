-- ReceiptIQ migration v3 -> v4
-- Category consolidation: 8 labels -> 6, matching the 6 outputs the
-- TF-IDF + Naive Bayes classifier can produce.
--   Transportation     -> Fuel
--   Bills & Utilities  -> Cash & ATM
--   Medicines          -> Other   (label was never classifier-set)
--   Entertainment      -> Other   (label was never classifier-set)
-- Run once:  psql -U postgres -d receipt_iq -f migrate_v4.sql
-- Wrapped in BEGIN/COMMIT so any error rolls back the whole thing.

BEGIN;

-- 1. Snapshot existing receipts in case anything goes wrong.
CREATE TABLE receipts_backup_v3 AS SELECT * FROM receipts;

-- 2. Apply the four renames. Updated_at is bumped so client devices
-- pick up the new value on their next pullDelta and overwrite their
-- local copy with the canonical name.
UPDATE receipts SET category = 'Fuel',       updated_at = NOW() WHERE category = 'Transportation';
UPDATE receipts SET category = 'Cash & ATM', updated_at = NOW() WHERE category = 'Bills & Utilities';
UPDATE receipts SET category = 'Other',      updated_at = NOW() WHERE category = 'Medicines';
UPDATE receipts SET category = 'Other',      updated_at = NOW() WHERE category = 'Entertainment';

-- 3. Sanity check — show row counts per category after the rename.
-- Visible in psql output, no effect on the migration result.
SELECT category, COUNT(*) AS row_count
FROM   receipts
WHERE  deleted_at IS NULL
GROUP  BY category
ORDER  BY category;

COMMIT;
