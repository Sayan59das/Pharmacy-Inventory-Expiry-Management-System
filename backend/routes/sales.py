# =====================================================================
# FILE        : backend/routes/sales.py
# WHAT IT DOES: The URLs for selling and billing:
#                 GET  /sales/customers      list customers (for the customer drop-down)
#                 POST /sales/customers      add a customer
#                 POST /sales                sell a whole shopping cart on ONE bill   -> procedure sp_make_bill
#                 POST /sales/single         sell ONE medicine on a new bill          -> procedure sp_make_sale
#                 GET  /sales/{id}/bill      the printable bill with GST and totals   -> procedure sp_generate_bill
#                 GET  /sales                the 20 most recent bills                 -> view v_sale_list
# DEPENDS ON  : db.py, procedures sp_make_bill / sp_make_sale / sp_generate_bill, view v_sale_list.
# USED BY     : frontend/js/api.js  ->  frontend/js/sale.js
#
# FEFO (First Expired, First Out) is done by MySQL inside sp_add_medicine_to_sale: Python never
# chooses a batch. If the stock is not enough, or a batch has expired, MySQL answers with an
# error message and NOTHING is saved.
# =====================================================================

import json                                                   # json.dumps turns a Python list into JSON text
from typing import List, Literal, Optional                    # Literal["CASH", ...] = only these exact values

from fastapi import APIRouter, HTTPException                  # APIRouter groups URLs; HTTPException sends an error answer
from pydantic import BaseModel, Field                         # describes and validates incoming JSON

from db import get_connection                                 # opens a MySQL connection

# All URLs in this file start with /sales.
router = APIRouter(prefix="/sales", tags=["Sales"])


# One cart line: which medicine and how many units. (The batch is chosen by MySQL, not by us.)
class CartItemIn(BaseModel):
    medicine_id: int
    quantity: int = Field(gt=0)


# A whole bill.
class SaleIn(BaseModel):
    customer_id: Optional[int] = None                              # None = walk-in customer
    payment_mode: Literal["CASH", "UPI", "CARD"] = "CASH"          # only these three are accepted
    items: List[CartItemIn] = Field(min_length=1)                  # at least one medicine


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
    """Return all customers."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute("SELECT customer_id, customer_name, phone FROM customer ORDER BY customer_name")
        return cursor.fetchall()
    finally:
        connection.close()


@router.post("/customers", status_code=201)
def add_customer(customer: CustomerIn):
    """Add a customer. An empty phone number is stored as NULL (many NULLs are allowed, repeated numbers are not)."""
    connection = get_connection()
    try:
        cursor = connection.cursor()
        cursor.execute(
            "INSERT INTO customer (customer_name, phone, address) VALUES (%s, %s, %s)",
            (customer.customer_name, customer.phone or None, customer.address or None),
        )
        return {"customer_id": cursor.lastrowid, "message": "Customer added"}
    finally:
        connection.close()


@router.post("", status_code=201)
def make_bill(sale: SaleIn):
    """Sell a shopping cart: one bill, several medicines, all-or-nothing (procedure sp_make_bill)."""
    # The cart as JSON text, e.g. '[{"medicine_id": 1, "quantity": 5}]'.
    items_as_json = json.dumps([item.model_dump() for item in sale.items])

    connection = get_connection()
    try:
        cursor = connection.cursor()
        # The last argument (0) is a placeholder for the OUT parameter p_sale_id.
        result = cursor.callproc("sp_make_bill", (sale.customer_id, sale.payment_mode, items_as_json, 0))
        return {"sale_id": result[3], "message": "Bill created and stock updated"}
    finally:
        connection.close()


@router.post("/single", status_code=201)
def make_single_sale(sale: SingleSaleIn):
    """Sell ONE medicine on a new bill (procedure sp_make_sale)."""
    connection = get_connection()
    try:
        cursor = connection.cursor()
        result = cursor.callproc(
            "sp_make_sale",
            (sale.customer_id, sale.medicine_id, sale.quantity, sale.payment_mode, 0),
        )
        return {"sale_id": result[4], "message": "Bill created and stock updated"}
    finally:
        connection.close()


@router.get("/{sale_id}/bill")
def get_bill(sale_id: int):
    """Return the bill of one sale: its lines and its totals (procedure sp_generate_bill)."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.callproc("sp_generate_bill", (sale_id,))
        # The procedure returns TWO result sets: first the lines, then the totals.
        # stored_results() gives us one cursor per result set.
        result_sets = [result.fetchall() for result in cursor.stored_results()]
        if len(result_sets) < 2 or len(result_sets[1]) == 0:
            raise HTTPException(status_code=404, detail="Bill not found")
        return {"lines": result_sets[0], "totals": result_sets[1][0]}
    finally:
        connection.close()


@router.get("")
def list_sales():
    """Return the 20 most recent bills."""
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute("SELECT * FROM v_sale_list LIMIT 20")
        return cursor.fetchall()
    finally:
        connection.close()
