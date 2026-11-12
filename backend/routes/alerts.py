# =====================================================================
# FILE        : backend/routes/alerts.py
# WHAT IT DOES: The URLs for stock alerts:
#                 GET  /alerts                list the OPEN alerts            -> view v_open_alerts
#                 POST /alerts/{id}/resolve   mark one alert as RESOLVED      -> procedure sp_resolve_alert
#                 POST /alerts/refresh        create missing alerts right now -> procedures sp_generate_expiry_alerts
#                                                                                and sp_generate_low_stock_alerts
# DEPENDS ON  : db.py, view v_open_alerts and the three procedures named above.
# USED BY     : frontend/src/api.js  ->  frontend/src/pages/Dashboard.jsx
#
# The alerts are normally created by MySQL itself (a trigger after every sale, and the daily
# event). "/alerts/refresh" is a button for the case when the event scheduler is switched off.
# =====================================================================

from fastapi import APIRouter                                 # groups the URLs of this file

from db import get_connection                                 # opens a MySQL connection

# All URLs in this file start with /alerts.
router = APIRouter(prefix="/alerts", tags=["Alerts"])


@router.get("")
def list_open_alerts():
    """Return every OPEN alert, newest first."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute("SELECT * FROM v_open_alerts")
        return cursor.fetchall()
    finally:
        connection.close()


@router.post("/refresh")
def refresh_alerts():
    """Run the two alert generators now (same work as the daily MySQL event)."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)

        # Each procedure ends with a SELECT of its counts. We must read these result sets,
        # otherwise the connection complains about "unread results".
        cursor.callproc("sp_generate_expiry_alerts")
        expiry_counts = [result.fetchall() for result in cursor.stored_results()]

        cursor.callproc("sp_generate_low_stock_alerts")
        low_stock_counts = [result.fetchall() for result in cursor.stored_results()]

        return {
            "message": "Alerts refreshed",
            "expiry": expiry_counts[0][0] if expiry_counts and expiry_counts[0] else {},
            "low_stock": low_stock_counts[0][0] if low_stock_counts and low_stock_counts[0] else {},
        }
    finally:
        connection.close()


@router.post("/{alert_id}/resolve")
def resolve_alert(alert_id: int):
    """Mark one alert as RESOLVED. MySQL answers with an error if it is missing or already resolved."""
    connection = get_connection()
    try:
        cursor = connection.cursor()
        cursor.callproc("sp_resolve_alert", (alert_id,))
        # The procedure ends with a SELECT of the updated alert; read it so the connection stays clean.
        for result in cursor.stored_results():
            result.fetchall()
        return {"alert_id": alert_id, "message": "Alert resolved"}
    finally:
        connection.close()
