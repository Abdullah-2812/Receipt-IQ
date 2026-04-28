-- ReceiptIQ PostgreSQL Schema v3 (composite PK for multi-tenant isolation)
-- Run once: psql -U postgres -d receipt_iq -f app/schema.sql

CREATE TABLE IF NOT EXISTS receipts (
    id                   TEXT NOT NULL,
    user_id              TEXT NOT NULL,
    merchant_name        TEXT NOT NULL,
    date                 TEXT NOT NULL,
    total_amount         REAL NOT NULL,
    category             TEXT NOT NULL,
    image_path           TEXT,
    notes                TEXT,
    created_at           TEXT NOT NULL,
    raw_ocr_text         TEXT,
    vendor_address       TEXT,
    receipt_time         TEXT,
    subtotal             REAL,
    tax                  REAL,
    fbr_pos_fee          REAL,
    discount             REAL,
    cash_paid            REAL,
    change_due           REAL,
    payment_method       TEXT,
    fbr_invoice_id       TEXT,
    ntn                  TEXT,
    invoice_number       TEXT,
    sync_status          TEXT DEFAULT 'synced',
    category_data        TEXT,
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at           TIMESTAMPTZ,
    PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS receipt_items (
    id           SERIAL PRIMARY KEY,
    receipt_id   TEXT NOT NULL,
    user_id      TEXT NOT NULL,
    name         TEXT NOT NULL,
    quantity     REAL NOT NULL,
    price        REAL NOT NULL,
    total_price  REAL NOT NULL,
    FOREIGN KEY (user_id, receipt_id) REFERENCES receipts(user_id, id) ON DELETE CASCADE
);

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_receipts_user        ON receipts(user_id);
CREATE INDEX IF NOT EXISTS idx_receipts_date        ON receipts(user_id, date);
CREATE INDEX IF NOT EXISTS idx_receipts_category    ON receipts(user_id, category);
CREATE INDEX IF NOT EXISTS idx_receipts_updated     ON receipts(user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_items_receipt        ON receipt_items(user_id, receipt_id);
