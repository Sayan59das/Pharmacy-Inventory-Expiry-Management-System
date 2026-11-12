# =====================================================================
# FILE        : backend/main.py
# WHAT IT DOES: Starts the web application:
#                 1. creates the FastAPI app
#                 2. switches on CORS so the React website may call it
#                 3. plugs in the six route files
#                 4. turns MySQL errors (including our own SIGNAL messages) into clear JSON answers
# DEPENDS ON  : db.py and the six files in routes/.
# USED BY     : uvicorn  ->  start it with:   uvicorn main:app --reload   (inside the backend folder)
# READ ORDER  : after db.py and the route files.
# TIP         : while it runs, open http://127.0.0.1:8000/docs to try every URL in the browser.
# =====================================================================

import mysql.connector                                   # we need its Error class for the error handler
from fastapi import FastAPI, Request                     # FastAPI = the app; Request = an incoming request
from fastapi.middleware.cors import CORSMiddleware       # CORS support
from fastapi.responses import JSONResponse               # lets us build our own JSON answer

from db import fetch_one                                 # used by the /health URL
from routes import alerts, medicines, purchases, reports, sales, suppliers

# Create the application. title/description appear on the /docs page.
app = FastAPI(
    title="Pharmacy Inventory & Expiry Management API",
    description="A thin layer over MySQL: every rule lives in stored procedures, triggers and views.",
    version="1.0.0",
)

# ---------------------------------------------------------------------
# CORS: the website runs on http://127.0.0.1:5173 and this API on port 8000.
# A browser treats that as a different "origin" and blocks the call unless
# the server allows it. allow_origins=["*"] allows every origin (fine for a
# project on your own computer).
# ---------------------------------------------------------------------
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# Plug in the route files. Each has a "router" with its own URLs.
app.include_router(medicines.router)
app.include_router(suppliers.router)
app.include_router(purchases.router)
app.include_router(sales.router)
app.include_router(alerts.router)
app.include_router(reports.router)


# ---------------------------------------------------------------------
# ERROR HANDLING
# ---------------------------------------------------------------------

# MySQL's text for a broken CHECK or UNIQUE rule names the rule, e.g.
# "Check constraint 'chk_batch_price' is violated." If a rule name below appears
# in the error, the user sees the plain sentence instead.
FRIENDLY_MESSAGES = {
    "chk_batch_price":         "Selling price cannot be lower than the cost price.",
    "chk_batch_dates":         "Expiry date must be later than the manufacture date.",
    "chk_batch_cost":          "Cost price cannot be negative.",
    "chk_batch_qty":           "Stock cannot go below zero.",
    "chk_pitem_quantity":      "Quantity must be at least 1.",
    "chk_sitem_quantity":      "Quantity must be at least 1.",
    "chk_medicine_gst":        "GST must be between 0 and 28 percent.",
    "chk_medicine_reorder":    "Reorder level cannot be negative.",
    "chk_supplier_gst_length": "GST number must be exactly 15 characters.",
    "uq_supplier_gst_no":      "A supplier with this GST number already exists.",
    "uq_medicine_name_maker":  "This medicine from this manufacturer already exists.",
    "uq_purchase_invoice":     "This invoice number was already entered for this supplier.",
    "uq_customer_phone":       "A customer with this phone number already exists.",
    "uq_category_name":        "This category already exists.",
    "uq_batch_lot":            "This batch already exists for this medicine and supplier.",
    "fk_medicine_category":    "The selected category does not exist.",
    "fk_batch_medicine":       "The selected medicine does not exist.",
}

# Which HTTP status code to send for which MySQL error number.
# Any number not in this list gets 500 (unexpected server error).
HTTP_STATUS_FOR_MYSQL_ERROR = {
    1644: 400,   # SIGNAL SQLSTATE '45000' from our triggers/procedures (e.g. "Insufficient stock ...")
    3819: 400,   # a CHECK constraint was violated
    1048: 400,   # a NOT NULL column got no value
    1265: 400,   # a value does not fit the column (e.g. wrong ENUM)
    1366: 400,   # a value of the wrong type
    1406: 400,   # text too long for the column
    1292: 400,   # an invalid date
    3140: 400,   # invalid JSON
    1062: 409,   # duplicate value in a UNIQUE column  (409 = conflict)
    1451: 409,   # cannot delete a parent row that still has children
    1452: 409,   # the parent row does not exist (foreign key)
    2003: 503,   # cannot connect to MySQL             (503 = service unavailable)
    2002: 503,
    2013: 503,
    1045: 503,   # wrong user name or password
    1049: 503,   # the database does not exist
}


def friendly_text(mysql_text):
    """Return the plain-English sentence for a rule name found in the MySQL text,
    or the MySQL text itself when no rule name matches."""
    for rule_name in FRIENDLY_MESSAGES:
        if rule_name in mysql_text:
            return FRIENDLY_MESSAGES[rule_name]
    return mysql_text


# This function runs automatically whenever ANY route raises a MySQL error.
@app.exception_handler(mysql.connector.Error)
async def handle_database_error(request: Request, error: mysql.connector.Error):
    number = error.errno                                     # MySQL's error number, e.g. 1644
    message = friendly_text(error.msg or str(error))         # MySQL's text, made friendly
    status_code = HTTP_STATUS_FOR_MYSQL_ERROR.get(number, 500)

    if status_code == 503:
        message = "Cannot reach the MySQL database. Check that MySQL is running and that backend/.env is correct. (" + message + ")"
    if status_code == 500:
        message = "Database error " + str(number) + ": " + message

    # {"detail": "..."} is the same shape FastAPI uses for its own errors.
    return JSONResponse(status_code=status_code, content={"detail": message})


# ---------------------------------------------------------------------
# Two small URLs to check that everything is alive.
# ---------------------------------------------------------------------
@app.get("/", tags=["Health"])
def home():
    return {"message": "Pharmacy Inventory API is running", "documentation": "/docs"}


@app.get("/health", tags=["Health"])
def health():
    # The simplest possible query. If MySQL is down, the error handler above answers 503.
    fetch_one("SELECT 1 AS ok")
    return {"status": "ok", "database": "connected"}
