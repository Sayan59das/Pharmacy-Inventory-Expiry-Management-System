# =====================================================================
# FILE        : backend/routes/purchases.py
# WHAT IT DOES: The URLs for buying stock from suppliers:
#                 POST /purchases     add a purchase invoice with all its items -> procedure sp_add_purchase
#                 GET  /purchases     the 20 most recent invoices               -> view v_purchase_list
# DEPENDS ON  : db.py, procedure sp_add_purchase, view v_purchase_list.
# USED BY     : frontend/src/api.js  ->  frontend/src/pages/Purchase.jsx
#
# The procedure does all the work: it creates the invoice, creates or tops up every batch,
# and a trigger adds the stock. If ANY item is wrong, MySQL undoes the whole invoice.
# =====================================================================

import json                                                   # json.dumps turns a Python list into JSON text
from datetime import date
from typing import List, Optional

from fastapi import APIRouter
from pydantic import BaseModel, Field

from db import call_procedure, fetch_all

# Every URL in this file starts with /purchases.
router = APIRouter(prefix="/purchases", tags=["Purchases"])


# One line of the invoice.
class PurchaseItemIn(BaseModel):
    medicine_id: int
    batch_no: str = Field(min_length=1, max_length=30)
    manufacture_date: Optional[date] = None                         # needed only for a NEW batch
    expiry_date: Optional[date] = None                              # needed only for a NEW batch
    quantity: int = Field(gt=0)                                     # gt=0: more than zero
    unit_cost: float = Field(ge=0)
    selling_price: Optional[float] = Field(default=None, ge=0)      # MRP; needed only for a NEW batch


# The whole invoice.
class PurchaseIn(BaseModel):
    supplier_id: int
    invoice_no: str = Field(min_length=1, max_length=30)
    purchase_date: Optional[date] = None                            # None = today
    items: List[PurchaseItemIn] = Field(min_length=1)               # at least one item


@router.post("", status_code=201)
def add_purchase(purchase: PurchaseIn):
    """Record a purchase invoice by calling the stored procedure sp_add_purchase."""
    # The procedure expects the items as JSON text. Build a plain list of dictionaries first.
    items = []
    for item in purchase.items:
        # mode="json" turns dates into "2026-11-12" text; exclude_none leaves out empty optional fields
        items.append(item.model_dump(mode="json", exclude_none=True))
    items_as_json = json.dumps(items)

    # sp_add_purchase(supplier_id, invoice_no, purchase_date, items, OUT purchase_id)
    # The last argument (0) is only a placeholder that MySQL replaces with the new id.
    out_values, result_sets = call_procedure(
        "sp_add_purchase",
        (purchase.supplier_id, purchase.invoice_no, purchase.purchase_date, items_as_json, 0),
    )
    new_purchase_id = out_values[4]          # the 5th argument = OUT purchase_id
    return {"purchase_id": new_purchase_id, "message": "Purchase recorded and stock updated"}


@router.get("")
def list_purchases():
    """The 20 most recent purchase invoices."""
    return fetch_all("SELECT * FROM v_purchase_list LIMIT 20")
