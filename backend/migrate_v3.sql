-- ReceiptIQ migration v2 -> v3
-- Adds composite primary key (user_id, id) to receipts.
-- Adds user_id column to receipt_items, backfills it, recreates FK as composite.
-- Run once:  psql -U postgres -d receipt_iq -f migrate_v3.sql
-- Wrapped in BEGIN/COMMIT so any error rolls back the whole thing.

BEGIN;

-- 1. Snapshot existing data in case anything goes wrong.
CREATE TABLE receipts_backup_v2     AS SELECT * FROM receipts;
CREATE TABLE receipt_items_backup_v2 AS SELECT * FROM receipt_items;

-- 2. Add user_id to receipt_items (nullable for now so the existing rows don't break).
ALTER TABLE receipt_items ADD COLUMN user_id TEXT;

-- 3. Backfill user_id by joining to the parent receipts row.
UPDATE receipt_items ri
SET    user_id = r.user_id
FROM   receipts r
WHERE  ri.receipt_id = r.id;

-- 4. Now that every row has a user_id, enforce NOT NULL.
ALTER TABLE receipt_items ALTER COLUMN user_id SET NOT NULL;

-- 5. Drop the old single-column FK.
ALTER TABLE receipt_items DROP CONSTRAINT receipt_items_receipt_id_fkey;

-- 6. Drop the old single-column PK on receipts.
ALTER TABLE receipts DROP CONSTRAINT receipts_pkey;

-- 7. Create the new composite PK.
ALTER TABLE receipts ADD PRIMARY KEY (user_id, id);

-- 8. Recreate the FK as composite so cascade still works.
ALTER TABLE receipt_items
    ADD CONSTRAINT receipt_items_user_receipt_fkey
    FOREIGN KEY (user_id, receipt_id)
    REFERENCES  receipts(user_id, id)
    ON DELETE CASCADE;

-- 9. Refresh the items index to use the composite key.
DROP INDEX IF EXISTS idx_items_receipt;
CREATE INDEX idx_items_receipt ON receipt_items(user_id, receipt_id);

COMMIT;
