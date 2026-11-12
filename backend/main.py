# =====================================================================
# FILE        : backend/main.py
# WHAT IT DOES: Starts the web application:
#                 1. creates the FastAPI app
#                 2. switches on CORS so the HTML pages may call it
#                 3. plugs in the six route files (medicines, suppliers, purchases, sales, alerts, reports)
#                 4. turns MySQL errors (including our own SIGNAL messages) into clear JSON answers
# DEPENDS ON  : db.py and the six files in routes/.
# USED BY     : uvicorn  ->  start it with:   uvicorn main:app --reload
#               (run that command inside the backend folder)
# READ ORDER  : after db.py and the route files.
#
# AUTOMATIC DOCUMENTATION: once running, open http://127.0.0.1:8000/docs
#               to see and test every endpoint in your browser.
# =====================================================================

import mysql.connector                                   # we need its Error class for the error handler
from fastapi import FastAPI, Request                     # FastAPI = the app; Request = an incoming HTTP request
from fastapi.middleware.cors import CORSMiddleware       # CORS support
from fastapi.responses import JSONResponse               # lets us build our own JSON answers

from db import get_connection                            # used by the /health endpoint
from routes import medicines, suppliers, purchases, sales, alerts, reports   # the six route files


# Create the application object. title/description appear on the /docs page.
app = FastAPI(
    title="Pharmacy Inventory & Expiry Management API",
    description="A thin layer over MySQL: every rule lives in stored procedures, triggers and views.",
    version="1.0.0",
)


# ---------------------------------------------------------------------
# CORS (Cross-Origin Resource Sharing)
# The HTML pages are opened from files (or another port such as :5500), while this API
# runs on port 8000. A browser treats that as a different "origin" and BLOCKS the call
# unless the server says "this origin is allowed". These lines say: allow every origin.
# (Fine for a course project on your own computer; a real website would list its own address.)
# ---------------------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],         # which web pages may call us: all of them
    allow_methods=["*"],         # which HTTP methods: GET, POST, PUT ...
    allow_headers=["*"],         # which request headers
)


# ---------------------------------------------------------------------
# Plug in the route files. Each one has its own "router" with its own URLs.
# ---------------------------------------------------------------------
app.include_router(medicines.router)
app.include_router(suppliers.router)
app.include_router(purchases.router)
app.include_router(sales.router)
app.include_router(alerts.router)
app.include_router(reports.router)


# ---------------------------------------------------------------------
# Friendly texts for database rules. MySQL's own text for a violated CHECK or UNIQUE rule
# mentions the constraint name (e.g. "Check constraint 'chk_batch_price' is violated").
# If that name appears in the error, we show the plain-English sentence instead.
# ---------------------------------------------------------------------
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


# ---------------------------------------------------------------------
# One error handler for EVERY MySQL error raised in any route.
# Route code therefore needs no try/except for database errors.
# ---------------------------------------------------------------------
@app.exception_handler(mysql.connector.Error)
async def handle_database_error(request: Request, error: mysql.connector.Error):
    # error.errno = MySQL's error number, error.msg = MySQL's error text.
    number = error.errno
    message = error.msg or str(error)

    # Replace a technical text by a friendly one when we know the rule's name.
    for rule_name, friendly_text in FRIENDLY_MESSAGES.items():
        if rule_name in message:
            message = friendly_text
            break

    # Choose the HTTP status code from the kind of error.
    if number == 1644:
        # 1644 = SIGNAL SQLSTATE '45000' written by our triggers/procedures.
        # The message is already clear (e.g. "Insufficient stock for ...").
        status_code = 400
    elif number in (1062, 1451, 1452):
        # duplicate value / cannot delete a parent row / parent row missing -> conflict
        status_code = 409
    elif number in (3819, 1048, 1265, 1366, 1406, 1292, 3140):
        # CHECK violated / NULL not allowed / bad or too long value / invalid JSON -> bad input
        status_code = 400
    elif number in (2003, 2002, 2013, 1045, 1049):
        # cannot connect / wrong password / database missing -> the database is unavailable
        status_code = 503
        message = "Cannot reach the MySQL database. Check that MySQL is running and that backend/.env is correct. (" + message + ")"
    else:
        # anything else is an unexpected server-side problem
        status_code = 500
        message = "Database error " + str(number) + ": " + message

    # {"detail": "..."} is the same shape FastAPI uses for its own errors, so the web page
    # can treat all errors alike.
    return JSONResponse(status_code=status_code, content={"detail": message})


# ---------------------------------------------------------------------
# Two small endpoints to check that everything is alive.
# ---------------------------------------------------------------------
@app.get("/", tags=["Health"])
def home():
    # Visiting http://127.0.0.1:8000/ shows this message.
    return {"message": "Pharmacy Inventory API is running", "documentation": "/docs"}


@app.get("/health", tags=["Health"])
def health():
    # Tries to talk to MySQL. If MySQL is down, the error handler above answers with status 503.
    connection = get_connection()                  # open a connection
    try:
        cursor = connection.cursor()               # a cursor sends SQL and reads answers
        cursor.execute("SELECT 1")                 # the simplest possible query
        cursor.fetchall()                          # read (and discard) the answer
        return {"status": "ok", "database": "connected"}
    finally:
        connection.close()                         # always close the connection
