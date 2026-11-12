# =====================================================================
# FILE        : backend/routes/reports.py
# WHAT IT DOES: The URLs for the dashboard and the reports:
#                 GET /reports/dashboard         numbers of the dashboard tiles -> view v_dashboard_summary
#                 GET /reports/monthly-sales     sales of one month (3 tables)  -> procedure sp_monthly_sales_report
#                 GET /reports/top-selling       best-selling medicines         -> view v_top_selling_medicines
#                 GET /reports/expiring-soon     batches expiring within 30 days-> view v_expiring_soon
#                 GET /reports/expired           expired batches still in stock -> view v_expired_stock
#                 GET /reports/low-stock         medicines below reorder level  -> view v_low_stock
#                 GET /reports/supplier-summary  purchases per supplier         -> view v_supplier_purchase_summary
# DEPENDS ON  : db.py and the views / procedure named above.
# USED BY     : frontend/src/api.js  ->  pages/Dashboard.jsx and pages/Reports.jsx
# =====================================================================

from datetime import date                                     # date.today() gives today's date
from typing import Optional

from fastapi import APIRouter, Query                          # Query adds checks to URL parameters

from db import call_procedure, fetch_all, fetch_one

# Every URL in this file starts with /reports.
router = APIRouter(prefix="/reports", tags=["Reports"])


@router.get("/dashboard")
def dashboard_summary():
    """ONE row with the numbers of the dashboard tiles."""
    return fetch_one("SELECT * FROM v_dashboard_summary")


@router.get("/monthly-sales")
def monthly_sales(
    month: Optional[int] = Query(default=None, ge=1, le=12),       # ?month=11   (1 to 12)
    year: Optional[int] = Query(default=None, ge=2000, le=2100),   # ?year=2026
):
    """The monthly sales report. Without month/year it uses the current month."""
    today = date.today()
    if month is None:
        month = today.month
    if year is None:
        year = today.year

    # The procedure returns THREE tables: summary (1 row), sales by payment mode, top medicines.
    out_values, result_sets = call_procedure("sp_monthly_sales_report", (month, year))
    return {
        "summary": result_sets[0][0],
        "by_payment_mode": result_sets[1],
        "top_medicines": result_sets[2],
    }


@router.get("/top-selling")
def top_selling(limit: int = Query(default=10, ge=1, le=100)):
    """The best-selling medicines (default: top 10)."""
    # Even the LIMIT number is passed as a parameter, never glued into the SQL text.
    return fetch_all("SELECT * FROM v_top_selling_medicines LIMIT %s", (limit,))


@router.get("/expiring-soon")
def expiring_soon():
    """Batches that expire within the next 30 days."""
    return fetch_all("SELECT * FROM v_expiring_soon")


@router.get("/expired")
def expired_stock():
    """Expired batches that still hold stock."""
    return fetch_all("SELECT * FROM v_expired_stock")


@router.get("/low-stock")
def low_stock():
    """Medicines whose sellable stock is below the reorder level."""
    return fetch_all("SELECT * FROM v_low_stock")


@router.get("/supplier-summary")
def supplier_summary():
    """How much we bought from each supplier."""
    return fetch_all("SELECT * FROM v_supplier_purchase_summary")
