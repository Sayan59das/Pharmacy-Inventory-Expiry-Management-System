# =====================================================================
# FILE        : backend/routes/suppliers.py
# WHAT IT DOES: The URLs for suppliers:
#                 GET  /suppliers     list suppliers with their purchase totals
#                 POST /suppliers     add a supplier
# DEPENDS ON  : db.py and the MySQL view v_supplier_purchase_summary.
# USED BY     : frontend/src/api.js  ->  pages/Suppliers.jsx, pages/Purchase.jsx
# =====================================================================

from typing import Optional                                   # Optional[str] = a string or None

from fastapi import APIRouter
from pydantic import BaseModel, Field

from db import execute, fetch_all

# Every URL in this file starts with /suppliers.
router = APIRouter(prefix="/suppliers", tags=["Suppliers"])


# The JSON the website sends to add a supplier.
class SupplierIn(BaseModel):
    supplier_name: str = Field(min_length=1, max_length=100)
    contact_person: Optional[str] = Field(default=None, max_length=100)
    phone: str = Field(min_length=1, max_length=15)                 # required: we must be able to call them
    email: Optional[str] = Field(default=None, max_length=100)
    address: Optional[str] = Field(default=None, max_length=255)
    gst_no: str = Field(min_length=15, max_length=15)               # a GSTIN has exactly 15 characters


@router.get("")
def list_suppliers():
    """Every supplier with how much we bought from it (the view calculates the totals)."""
    return fetch_all(
        "SELECT s.supplier_id, s.supplier_name, s.contact_person, s.phone, s.email, s.address, s.gst_no, "
        "       v.number_of_purchases, v.total_units_bought, v.total_amount_spent, v.last_purchase_date "
        "FROM supplier AS s "
        "JOIN v_supplier_purchase_summary AS v ON v.supplier_id = s.supplier_id "
        "ORDER BY s.supplier_name"
    )


@router.post("", status_code=201)
def add_supplier(supplier: SupplierIn):
    """Add a supplier. MySQL refuses a GST number that already exists."""
    new_id = execute(
        "INSERT INTO supplier (supplier_name, contact_person, phone, email, address, gst_no) "
        "VALUES (%s, %s, %s, %s, %s, %s)",
        (supplier.supplier_name, supplier.contact_person, supplier.phone,
         supplier.email, supplier.address, supplier.gst_no),
    )
    return {"supplier_id": new_id, "message": "Supplier added"}
