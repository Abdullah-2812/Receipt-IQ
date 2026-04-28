from fastapi import APIRouter, Depends
from ..database import get_connection
from ..auth import verify_token

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/summary")
def get_summary(uid: str = Depends(verify_token)):
    with get_connection() as conn:
        with conn.cursor() as cur:

            # Total spending + receipt count (active rows only)
            cur.execute(
                """
                SELECT COALESCE(SUM(total_amount), 0) AS total_spending,
                       COUNT(*) AS receipt_count
                FROM receipts
                WHERE user_id = %s
                  AND deleted_at IS NULL
                """,
                (uid,),
            )
            overview = cur.fetchone()

            # Spending by category (active rows only)
            cur.execute(
                """
                SELECT category,
                       SUM(total_amount) AS total,
                       COUNT(*)          AS count
                FROM receipts
                WHERE user_id = %s
                  AND deleted_at IS NULL
                GROUP BY category
                ORDER BY total DESC
                """,
                (uid,),
            )
            by_category = cur.fetchall()

            # Spending by month — current month + 5 prior calendar months,
            # active rows only. DATE_TRUNC anchors the cutoff to the start
            # of the 6th-most-recent month so the result aligns with what
            # the Flutter line chart expects (6 contiguous calendar months).
            cur.execute(
                """
                SELECT TO_CHAR(date::date, 'Mon YYYY') AS month,
                       SUM(total_amount)               AS total
                FROM receipts
                WHERE user_id = %s
                  AND deleted_at IS NULL
                  AND date::date >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '5 months')
                GROUP BY TO_CHAR(date::date, 'Mon YYYY'), DATE_TRUNC('month', date::date)
                ORDER BY DATE_TRUNC('month', date::date)
                """,
                (uid,),
            )
            by_month = cur.fetchall()

    return {
        "total_spending": overview["total_spending"],
        "receipt_count":  overview["receipt_count"],
        "by_category":    list(by_category),
        "by_month":       list(by_month),
    }
