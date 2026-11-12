# =====================================================================
# FILE        : backend/routes/medicines.py
# WHAT IT DOES: The URLs for medicines:
#                 GET  /medicines/categories        list of categories (for drop-downs)
#                 GET  /medicines?search=para       list medicines with stock (optional search)
#                 GET  /medicines/{id}/batches      all batches of one medicine
#                 POST /medicines                   add a medicine
#                 PUT  /medicines/{id}              edit a medicine
# DEPENDS ON  : db.py (get_connection) and the MySQL views v_medicine_catalog and
#               v_batch_details (database/04_views.sql).
# USED BY     : frontend/js/api.js  ->  frontend/js/medicines.js, purchase.js, sale.js
#
# HOW SQL INJECTION IS PREVENTED  (viva question!)
#   SQL injection happens when user text is glued into the SQL string, e.g.
#         "SELECT * FROM medicine WHERE name = '" + text + "'"
#   If text is   x' OR '1'='1   the query changes meaning and leaks data.
#   We NEVER do that. We write placeholders (%s) in the SQL and pass the values
#   separately:   cursor.execute("... WHERE name = %s", (text,))
#   The driver escapes every value and inserts it as DATA, never as SQL code, so
#   the text   x' OR '1'='1   is just a strange medicine name that matches nothing.
# =====================================================================

from typing import Optional                                   # Optional[str] = a string or None

from fastapi import APIRouter, HTTPException, Query          # APIRouter groups the URLs of this file
from pydantic import BaseModel, Field                        # BaseModel describes and validates the JSON we receive

from db import get_connection                                # opens a MySQL connection

# All URLs in this file start with /medicines. "tags" only groups them on the /docs page.
router = APIRouter(prefix="/medicines", tags=["Medicines"])


# ---------------------------------------------------------------------
# The JSON the web page must send to add or edit a medicine.
# Pydantic checks the types automatically; wrong input gets an HTTP 422 answer.
# ---------------------------------------------------------------------
class MedicineIn(BaseModel):
    medicine_name: str = Field(min_length=1, max_length=100)        # e.g. "Paracetamol 500mg"
    generic_name: str = Field(min_length=1, max_length=100)         # e.g. "Paracetamol"
    manufacturer: str = Field(min_length=1, max_length=100)         # e.g. "Cipla"
    category_id: int                                                # id from the category table
    reorder_level: int = Field(default=10, ge=0)                    # ge=0: greater than or equal to 0
    requires_prescription: bool = False                             # True = needs a doctor's prescription
    gst_percent: float = Field(default=5.0, ge=0, le=28)            # GST between 0 and 28 percent


@router.get("/categories")
def list_categories():
    """Return every category (used to fill the category drop-down)."""
    connection = get_connection()                                    # open a MySQL connection
    try:
        cursor = connection.cursor(dictionary=True)                  # dictionary=True: rows come back as {"column": value}
        cursor.execute("SELECT category_id, category_name FROM category ORDER BY category_name")
        return cursor.fetchall()                                     # fetchall() returns the list of all rows
    finally:
        connection.close()                                           # always close the connection


@router.get("")
def list_medicines(search: Optional[str] = Query(default=None)):
    """Return all medicines with their stock numbers. ?search=text filters by name, generic name or maker."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        if search:
            # Build the LIKE pattern in Python ("%para%") and pass it as a parameter, never inside the SQL text.
            pattern = "%" + search + "%"
            cursor.execute(
                "SELECT * FROM v_medicine_catalog "
                "WHERE medicine_name LIKE %s OR generic_name LIKE %s OR manufacturer LIKE %s",
                (pattern, pattern, pattern),
            )
        else:
            cursor.execute("SELECT * FROM v_medicine_catalog")
        rows = cursor.fetchall()
        # MySQL stores BOOLEAN as 0/1; turn it into a real true/false for the web page.
        for row in rows:
            row["requires_prescription"] = bool(row["requires_prescription"])
        return rows
    finally:
        connection.close()


@router.get("/{medicine_id}/batches")
def list_batches(medicine_id: int):
    """Return every batch of one medicine, earliest expiry first."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute(
            "SELECT * FROM v_batch_details WHERE medicine_id = %s ORDER BY expiry_date",
            (medicine_id,),                                          # a one-item tuple needs the trailing comma
        )
        return cursor.fetchall()
    finally:
        connection.close()


@router.post("", status_code=201)
def add_medicine(medicine: MedicineIn):
    """Add a new medicine. MySQL checks the rules (unique name+maker, GST range ...)."""
    connection = get_connection()
    try:
        cursor = connection.cursor()
        cursor.execute(
            "INSERT INTO medicine (medicine_name, generic_name, manufacturer, category_id, "
            "reorder_level, requires_prescription, gst_percent) VALUES (%s, %s, %s, %s, %s, %s, %s)",
            (medicine.medicine_name, medicine.generic_name, medicine.manufacturer,
             medicine.category_id, medicine.reorder_level, medicine.requires_prescription,
             medicine.gst_percent),
        )
        # lastrowid = the AUTO_INCREMENT id MySQL just created.
        return {"medicine_id": cursor.lastrowid, "message": "Medicine added"}
    finally:
        connection.close()


@router.put("/{medicine_id}")
def edit_medicine(medicine_id: int, medicine: MedicineIn):
    """Change the details of an existing medicine (stock is NOT changed here)."""
    connection = get_connection()
    try:
        cursor = connection.cursor()
        # First make sure the medicine exists, so we can answer 404 (Not Found) properly.
        cursor.execute("SELECT 1 FROM medicine WHERE medicine_id = %s", (medicine_id,))
        if cursor.fetchone() is None:
            raise HTTPException(status_code=404, detail="Medicine not found")
        cursor.execute(
            "UPDATE medicine SET medicine_name = %s, generic_name = %s, manufacturer = %s, "
            "category_id = %s, reorder_level = %s, requires_prescription = %s, gst_percent = %s "
            "WHERE medicine_id = %s",
            (medicine.medicine_name, medicine.generic_name, medicine.manufacturer,
             medicine.category_id, medicine.reorder_level, medicine.requires_prescription,
             medicine.gst_percent, medicine_id),
        )
        return {"medicine_id": medicine_id, "message": "Medicine updated"}
    finally:
        connection.close()
