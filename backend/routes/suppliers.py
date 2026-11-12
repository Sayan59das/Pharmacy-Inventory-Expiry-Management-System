# =====================================================================
# FILE        : backend/routes/suppliers.py
# WHAT IT DOES: The URLs for suppliers:
#                 GET  /suppliers     list suppliers with their purchase totals
#                 POST /suppliers     add a supplier
# DEPENDS ON  : db.py and the MySQL view v_supplier_purchase_summary.
# USED BY     : frontend/js/api.js  ->  frontend/js/suppliers.js, purchase.js
# (Parameterized queries are explained in routes/medicines.py.)
# =====================================================================

from typing import Optional                                   # Optional[str] = a string or None

from fastapi import APIRouter                                 # groups the URLs of this file
from pydantic import BaseModel, Field                         # describes and validates incoming JSON

from db import get_connection                                 # opens a MySQL connection

# All URLs in this file start with /suppliers.
router = APIRouter(prefix="/suppliers", tags=["Suppliers"])


# The JSON the web page sends to add a supplier.
class SupplierIn(BaseModel):
    supplier_name: str = Field(min_length=1, max_length=100)        # company name
    contact_person: Optional[str] = Field(default=None, max_length=100)
    phone: str = Field(min_length=1, max_length=15)                 # required: we must be able to call them
    email: Optional[str] = Field(default=None, max_length=100)
    address: Optional[str] = Field(default=None, max_length=255)
    gst_no: str = Field(min_length=15, max_length=15)               # a GSTIN has exactly 15 characters


@router.get("")
def list_suppliers():
    """Return every supplier together with how much we bought from it."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        # The view already calculates the totals; we only join it with the supplier's contact details.
        cursor.execute(
            "SELECT s.supplier_id, s.supplier_name, s.contact_person, s.phone, s.email, s.address, s.gst_no, "
            "       v.number_of_purchases, v.total_units_bought, v.total_amount_spent, v.last_purchase_date "
            "FROM supplier AS s "
            "JOIN v_supplier_purchase_summary AS v ON v.supplier_id = s.supplier_id "
            "ORDER BY s.supplier_name"
        )
        return cursor.fetchall()
    finally:
        connection.close()


@router.post("", status_code=201)
def add_supplier(supplier: SupplierIn):
    """Add a new supplier. MySQL refuses a GST number that already exists."""
    connection = get_connection()
    try:
        cursor = connection.cursor()
        cursor.execute(
            "INSERT INTO supplier (supplier_name, contact_person, phone, email, address, gst_no) "
            "VALUES (%s, %s, %s, %s, %s, %s)",
            (supplier.supplier_name, supplier.contact_person, supplier.phone,
             supplier.email, supplier.address, supplier.gst_no),
        )
        return {"supplier_id": cursor.lastrowid, "message": "Supplier added"}
    finally:
        connection.close()
