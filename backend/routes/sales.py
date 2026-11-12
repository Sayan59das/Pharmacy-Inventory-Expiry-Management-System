# =====================================================================
# FILE        : backend/routes/sales.py
# WHAT IT DOES: The URLs for selling and billing:
#                 GET  /sales/customers      list customers
#                 POST /sales/customers      add a customer
#                 POST /sales                sell a shopping cart on ONE bill  -> procedure sp_make_bill
#                 POST /sales/single         sell ONE medicine on a new bill   -> procedure sp_make_sale
#                 GET  /sales/{id}/bill      the bill with GST and totals      -> procedure sp_generate_bill
#                 GET  /sales                the 20 most recent bills          -> view v_sale_list
# DEPENDS ON  : db.py and the procedures / view named above.
# USED BY     : frontend/src/api.js  ->  frontend/src/pages/Sale.jsx
#
# FEFO (First Expired, First Out) is done by MySQL: Python never chooses a batch. If the stock
# is not enough, or a batch has expired, MySQL answers with an error and NOTHING is saved.
# =====================================================================

import json
from typing import List, Literal, Optional                    # Literal["CASH", ...] = only these exact values

from fastapi import APIRouter
from pydantic import BaseModel, Field

from db import call_procedure, execute, fetch_all

# Every URL in this file starts with /sales.
router = APIRouter(prefix="/sales", tags=["Sales"])


# One cart line: which medicine and how many units (MySQL picks the batch).
class CartItemIn(BaseModel):
    medicine_id: int
    quantity: int = Field(gt=0)


# A whole bill.
class SaleIn(BaseModel):
    customer_id: Optional[int] = None                              # None = walk-in customer
    payment_mode: Literal["CASH", "UPI", "CARD"] = "CASH"
    items: List[CartItemIn] = Field(min_length=1)


# A bill with a single medicine.
class SingleSaleIn(BaseModel):
    customer_id: Optional[int] = None
    medicine_id: int
    quantity: int = Field(gt=0)
    payment_mode: Literal["CASH", "UPI", "CARD"] = "CASH"


# A new customer.
class CustomerIn(BaseModel):
    customer_name: str = Field(min_length=1, max_length=100)
    phone: Optional[str] = Field(default=None, max_length=15)
    address: Optional[str] = Field(default=None, max_length=255)


@router.get("/customers")
def list_customers():
    """All customers."""
    return fetch_all("SELECT customer_id, customer_name, phone FROM customer ORDER BY customer_name")


@router.post("/customers", status_code=201)
def add_customer(customer: CustomerIn):
    """Add a customer. An empty phone is stored as NULL (many NULLs are allowed, repeated numbers are not)."""
    phone = customer.phone
    if phone == "":
        phone = None
    address = customer.address
    if address == "":
        address = None

    new_id = execute(
        "INSERT INTO customer (customer_name, phone, address) VALUES (%s, %s, %s)",
        (customer.customer_name, phone, address),
    )
    return {"customer_id": new_id, "message": "Customer added"}


@router.post("", status_code=201)
def make_bill(sale: SaleIn):
    """Sell a shopping cart: one bill, several medicines, all-or-nothing (procedure sp_make_bill)."""
    # The cart as JSON text, e.g. '[{"medicine_id": 1, "quantity": 5}]'
    items = []
    for item in sale.items:
        items.append({"medicine_id": item.medicine_id, "quantity": item.quantity})
    items_as_json = json.dumps(items)

    # sp_make_bill(customer_id, payment_mode, items, OUT sale_id)  -> the new id is the 4th argument
    out_values, result_sets = call_procedure("sp_make_bill", (sale.customer_id, sale.payment_mode, items_as_json, 0))
    new_sale_id = out_values[3]
    return {"sale_id": new_sale_id, "message": "Bill created and stock updated"}


@router.post("/single", status_code=201)
def make_single_sale(sale: SingleSaleIn):
    """Sell ONE medicine on a new bill (procedure sp_make_sale)."""
    # sp_make_sale(customer_id, medicine_id, quantity, payment_mode, OUT sale_id) -> the 5th argument
    out_values, result_sets = call_procedure(
        "sp_make_sale",
        (sale.customer_id, sale.medicine_id, sale.quantity, sale.payment_mode, 0),
    )
    new_sale_id = out_values[4]
    return {"sale_id": new_sale_id, "message": "Bill created and stock updated"}


@router.get("/{sale_id}/bill")
def get_bill(sale_id: int):
    """The bill of one sale (procedure sp_generate_bill).
    MySQL itself answers "Bill not found" (an error) when the sale does not exist."""
    out_values, result_sets = call_procedure("sp_generate_bill", (sale_id,))
    # The procedure returns TWO tables: first the bill lines, then one row of totals.
    lines = result_sets[0]
    totals = result_sets[1][0]
    return {"lines": lines, "totals": totals}


@router.get("")
def list_sales():
    """The 20 most recent bills."""
    return fetch_all("SELECT * FROM v_sale_list LIMIT 20")
