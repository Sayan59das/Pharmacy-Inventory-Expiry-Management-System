# =====================================================================
# FILE        : backend/routes/purchases.py
# WHAT IT DOES: The URLs for buying stock from suppliers:
#                 POST /purchases     add a purchase invoice with all its items
#                                     -> calls the MySQL procedure sp_add_purchase
#                 GET  /purchases     the most recent purchase invoices (view v_purchase_list)
# DEPENDS ON  : db.py, procedure sp_add_purchase, view v_purchase_list.
# USED BY     : frontend/js/api.js  ->  frontend/js/purchase.js
#
# WHAT THE PROCEDURE DOES (so Python does not have to): it creates the invoice, creates or tops up
# every batch, and the trigger trg_purchase_item_after_insert adds the stock. If ANY item is
# wrong, MySQL undoes the whole invoice and we receive the error message.
# =====================================================================

import json                                                   # json.dumps turns a Python list into JSON text
from datetime import date                                     # type of the invoice date
from typing import List, Optional                             # List[...] = a list of items

from fastapi import APIRouter                                 # groups the URLs of this file
from pydantic import BaseModel, Field                         # describes and validates incoming JSON

from db import get_connection                                 # opens a MySQL connection

# All URLs in this file start with /purchases.
router = APIRouter(prefix="/purchases", tags=["Purchases"])


# One line of the invoice.
class PurchaseItemIn(BaseModel):
    medicine_id: int                                                # which medicine arrived
    batch_no: str = Field(min_length=1, max_length=30)              # batch number printed on the pack
    manufacture_date: Optional[date] = None                         # needed only for a NEW batch
    expiry_date: Optional[date] = None                              # needed only for a NEW batch
    quantity: int = Field(gt=0)                                     # gt=0: more than zero units
    unit_cost: float = Field(ge=0)                                  # price per unit on the invoice
    selling_price: Optional[float] = Field(default=None, ge=0)      # MRP; needed only for a NEW batch


# The whole invoice.
class PurchaseIn(BaseModel):
    supplier_id: int                                                # who sent the goods
    invoice_no: str = Field(min_length=1, max_length=30)            # the supplier's invoice number
    purchase_date: Optional[date] = None                            # None = today
    items: List[PurchaseItemIn] = Field(min_length=1)               # at least one item


@router.post("", status_code=201)
def add_purchase(purchase: PurchaseIn):
    """Record a purchase invoice by calling the stored procedure sp_add_purchase."""
    # Turn the list of items into JSON text, which is what the procedure expects.
    # mode="json" converts dates to "2026-11-12" text; exclude_none leaves out empty optional fields.
    items_as_json = json.dumps([item.model_dump(mode="json", exclude_none=True) for item in purchase.items])

    connection = get_connection()
    try:
        cursor = connection.cursor()
        # callproc(name, arguments). The last argument (0) is a placeholder for the OUT parameter p_purchase_id.
        result = cursor.callproc(
            "sp_add_purchase",
            (purchase.supplier_id, purchase.invoice_no, purchase.purchase_date, items_as_json, 0),
        )
        # callproc returns the arguments again, with the OUT parameter filled in by MySQL.
        new_purchase_id = result[4]
        return {"purchase_id": new_purchase_id, "message": "Purchase recorded and stock updated"}
    finally:
        connection.close()


@router.get("")
def list_purchases():
    """Return the 20 most recent purchase invoices."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute("SELECT * FROM v_purchase_list LIMIT 20")
        return cursor.fetchall()
    finally:
        connection.close()
