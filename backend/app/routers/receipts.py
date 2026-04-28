from fastapi import APIRouter, Depends, Query
from typing import Any
from datetime import datetime, timezone
from ..database import get_connection
from ..auth import verify_token

router = APIRouter(prefix="/receipts", tags=["receipts"])


@router.get("")
def get_receipts(
    uid: str = Depends(verify_token),
    since: str = Query(default=None, description="ISO datetime — only return records updated after this"),
):
    """
    Delta sync endpoint.
    - If since is provided: returns only receipts updated after that timestamp
      (including soft-deleted ones so client can remove them locally).
    - If since is omitted: returns all non-deleted receipts for the user.
    """
    with get_connection() as conn:
        with conn.cursor() as cur:
            if since:
                cur.execute(
                    """
                    SELECT * FROM receipts
                    WHERE user_id = %s AND updated_at > %s
                    ORDER BY updated_at ASC
                    """,
                    (uid, since),
                )
            else:
                cur.execute(
                    """
                    SELECT * FROM receipts
                    WHERE user_id = %s AND deleted_at IS NULL
                    ORDER BY created_at DESC
                    """,
                    (uid,),
                )
            receipts = cur.fetchall()
            for receipt in receipts:
                if receipt["deleted_at"] is None:
                    cur.execute(
                        "SELECT * FROM receipt_items WHERE receipt_id = %s AND user_id = %s",
                        (receipt["id"], uid),
                    )
                    receipt["items"] = cur.fetchall()
                else:
                    receipt["items"] = []
    return list(receipts)


@router.post("/sync")
def sync_receipts(payload: dict[str, Any], uid: str = Depends(verify_token)):
    receipts = payload.get("receipts", [])
    now = datetime.now(timezone.utc).isoformat()

    with get_connection() as conn:
        with conn.cursor() as cur:
            for r in receipts:
                cur.execute(
                    """
                    INSERT INTO receipts (
                        id, user_id, merchant_name, date, total_amount, category,
                        image_path, notes, created_at, raw_ocr_text, vendor_address,
                        receipt_time, subtotal, tax, fbr_pos_fee, discount, cash_paid,
                        change_due, payment_method, fbr_invoice_id, ntn, invoice_number,
                        sync_status, category_data, updated_at
                    ) VALUES (
                        %(id)s, %(user_id)s, %(merchant_name)s, %(date)s,
                        %(total_amount)s, %(category)s, %(image_path)s, %(notes)s,
                        %(created_at)s, %(raw_ocr_text)s, %(vendor_address)s,
                        %(receipt_time)s, %(subtotal)s, %(tax)s, %(fbr_pos_fee)s,
                        %(discount)s, %(cash_paid)s, %(change_due)s, %(payment_method)s,
                        %(fbr_invoice_id)s, %(ntn)s, %(invoice_number)s,
                        'synced', %(category_data)s, %(updated_at)s
                    )
                    ON CONFLICT (user_id, id) DO UPDATE SET
                        merchant_name  = EXCLUDED.merchant_name,
                        date           = EXCLUDED.date,
                        total_amount   = EXCLUDED.total_amount,
                        category       = EXCLUDED.category,
                        notes          = EXCLUDED.notes,
                        updated_at     = EXCLUDED.updated_at,
                        sync_status    = 'synced',
                        deleted_at     = NULL
                    """,
                    {**r, "user_id": uid, "updated_at": now},
                )
                cur.execute(
                    "DELETE FROM receipt_items WHERE receipt_id = %s AND user_id = %s",
                    (r["id"], uid),
                )
                for item in r.get("items", []):
                    cur.execute(
                        """
                        INSERT INTO receipt_items
                            (receipt_id, user_id, name, quantity, price, total_price)
                        VALUES (%s, %s, %s, %s, %s, %s)
                        """,
                        (r["id"], uid, item["name"], item["quantity"],
                         item["price"], item["totalPrice"]),
                    )
        conn.commit()
    return {"synced": len(receipts), "server_time": now}


@router.put("/{receipt_id}")
def update_receipt(
    receipt_id: str,
    payload: dict[str, Any],
    uid: str = Depends(verify_token),
):
    now = datetime.now(timezone.utc).isoformat()
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE receipts SET
                    merchant_name = %(merchant_name)s,
                    date          = %(date)s,
                    total_amount  = %(total_amount)s,
                    category      = %(category)s,
                    notes         = %(notes)s,
                    updated_at    = %(updated_at)s
                WHERE id = %(id)s AND user_id = %(user_id)s
                """,
                {**payload, "id": receipt_id, "user_id": uid, "updated_at": now},
            )
        conn.commit()
    return {"updated": receipt_id}


@router.delete("/{receipt_id}")
def delete_receipt(receipt_id: str, uid: str = Depends(verify_token)):
    """Soft delete — sets deleted_at instead of removing the row."""
    now = datetime.now(timezone.utc).isoformat()
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE receipts
                SET deleted_at = %s, updated_at = %s
                WHERE id = %s AND user_id = %s
                """,
                (now, now, receipt_id, uid),
            )
        conn.commit()
    return {"deleted": receipt_id}
