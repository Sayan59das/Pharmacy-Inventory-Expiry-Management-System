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
# Alerts are normally created by MySQL itself (a trigger after every sale, and the daily
# event). "/alerts/refresh" is a button for when the event scheduler is switched off.
# =====================================================================

from fastapi import APIRouter

from db import call_procedure, fetch_all

# Every URL in this file starts with /alerts.
router = APIRouter(prefix="/alerts", tags=["Alerts"])


@router.get("")
def list_open_alerts():
    """Every OPEN alert, newest first."""
    return fetch_all("SELECT * FROM v_open_alerts")


@router.post("/refresh")
def refresh_alerts():
    """Run the two alert procedures now (the same work as the daily MySQL event)."""
    # Each procedure ends with ONE row of counts, e.g. {"near_expiry_alerts_added": 0, ...}.
    # result_sets[0] = the first table it returned, [0] again = the first (only) row.
    out_values, expiry_results = call_procedure("sp_generate_expiry_alerts")
    out_values, low_stock_results = call_procedure("sp_generate_low_stock_alerts")
    return {
        "message": "Alerts refreshed",
        "expiry": expiry_results[0][0],
        "low_stock": low_stock_results[0][0],
    }


@router.post("/{alert_id}/resolve")
def resolve_alert(alert_id: int):
    """Mark one alert RESOLVED. MySQL answers with an error if it is missing or already resolved."""
    call_procedure("sp_resolve_alert", (alert_id,))
    return {"alert_id": alert_id, "message": "Alert resolved"}
