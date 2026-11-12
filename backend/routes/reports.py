# =====================================================================
# FILE        : backend/routes/reports.py
# WHAT IT DOES: The URLs for the dashboard and the reports:
#                 GET /reports/dashboard         the numbers of the dashboard cards   -> view v_dashboard_summary
#                 GET /reports/monthly-sales     sales of one month (3 tables)        -> procedure sp_monthly_sales_report
#                 GET /reports/top-selling       best-selling medicines               -> view v_top_selling_medicines
#                 GET /reports/expiring-soon     batches expiring within 30 days      -> view v_expiring_soon
#                 GET /reports/expired           expired batches still in stock       -> view v_expired_stock
#                 GET /reports/low-stock         medicines below the reorder level    -> view v_low_stock
#                 GET /reports/supplier-summary  purchases per supplier               -> view v_supplier_purchase_summary
# DEPENDS ON  : db.py and the views / procedure named above.
# USED BY     : frontend/js/api.js  ->  frontend/js/dashboard.js and reports.js
# =====================================================================

from datetime import date                                     # date.today() gives today's date
from typing import Optional                                   # Optional[int] = a number or None

from fastapi import APIRouter, Query                          # APIRouter groups URLs; Query describes URL parameters

from db import get_connection                                 # opens a MySQL connection

# All URLs in this file start with /reports.
router = APIRouter(prefix="/reports", tags=["Reports"])


@router.get("/dashboard")
def dashboard_summary():
    """Return ONE row of counts for the dashboard cards."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute("SELECT * FROM v_dashboard_summary")
        return cursor.fetchone()                              # fetchone() = just the first (and only) row
    finally:
        connection.close()


@router.get("/monthly-sales")
def monthly_sales(
    month: Optional[int] = Query(default=None, ge=1, le=12),   # ?month=11   (1 to 12)
    year: Optional[int] = Query(default=None, ge=2000, le=2100),  # ?year=2026
):
    """Return the monthly sales report. Without parameters it uses the current month."""
    # If the page did not send a month/year, use today's.
    today = date.today()
    month = month or today.month
    year = year or today.year

    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.callproc("sp_monthly_sales_report", (month, year))
        # The procedure returns THREE result sets: summary, by payment mode, top medicines.
        result_sets = [result.fetchall() for result in cursor.stored_results()]
        return {
            "summary": result_sets[0][0] if result_sets and result_sets[0] else {},
            "by_payment_mode": result_sets[1] if len(result_sets) > 1 else [],
            "top_medicines": result_sets[2] if len(result_sets) > 2 else [],
        }
    finally:
        connection.close()


@router.get("/top-selling")
def top_selling(limit: int = Query(default=10, ge=1, le=100)):
    """Return the best-selling medicines (default: top 10)."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        # LIMIT receives the number as a parameter too, so no user text is ever joined into the SQL.
        cursor.execute("SELECT * FROM v_top_selling_medicines LIMIT %s", (limit,))
        return cursor.fetchall()
    finally:
        connection.close()


@router.get("/expiring-soon")
def expiring_soon():
    """Return batches that expire within the next 30 days."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute("SELECT * FROM v_expiring_soon")
        return cursor.fetchall()
    finally:
        connection.close()


@router.get("/expired")
def expired_stock():
    """Return expired batches that still hold stock."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute("SELECT * FROM v_expired_stock")
        return cursor.fetchall()
    finally:
        connection.close()


@router.get("/low-stock")
def low_stock():
    """Return medicines whose sellable stock is below the reorder level."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute("SELECT * FROM v_low_stock")
        return cursor.fetchall()
    finally:
        connection.close()


@router.get("/supplier-summary")
def supplier_summary():
    """Return how much we bought from each supplier."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute("SELECT * FROM v_supplier_purchase_summary")
        return cursor.fetchall()
    finally:
        connection.close()
