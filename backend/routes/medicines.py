# =====================================================================
# FILE        : backend/routes/medicines.py
# WHAT IT DOES: The URLs for medicines:
#                 GET  /medicines/categories        list of categories (for drop-downs)
#                 GET  /medicines?search=para       list medicines with stock (optional search)
#                 GET  /medicines/{id}/batches      all batches of one medicine
#                 POST /medicines                   add a medicine
#                 PUT  /medicines/{id}              edit a medicine
# DEPENDS ON  : db.py and the MySQL views v_medicine_catalog and v_batch_details.
# USED BY     : frontend/src/api.js  ->  pages/Medicines.jsx, MedicineDetail.jsx, MedicineNew.jsx, Purchase.jsx, Sale.jsx
# =====================================================================

from typing import Optional                                   # Optional[str] = a string or None

from fastapi import APIRouter, HTTPException                  # APIRouter groups the URLs of this file
from pydantic import BaseModel, Field                         # BaseModel checks the JSON we receive

from db import execute, fetch_all, fetch_one

# Every URL in this file starts with /medicines.
router = APIRouter(prefix="/medicines", tags=["Medicines"])


# The JSON the website sends to add or edit a medicine.
# Pydantic checks the types; wrong input gets an automatic HTTP 422 answer.
class MedicineIn(BaseModel):
    medicine_name: str = Field(min_length=1, max_length=100)        # e.g. "Paracetamol 500mg"
    generic_name: str = Field(min_length=1, max_length=100)         # e.g. "Paracetamol"
    manufacturer: str = Field(min_length=1, max_length=100)         # e.g. "Cipla"
    category_id: int                                                # id from the category table
    reorder_level: int = Field(default=10, ge=0)                    # ge=0: 0 or more
    requires_prescription: bool = False                             # True = needs a prescription
    gst_percent: float = Field(default=5.0, ge=0, le=28)            # between 0 and 28 percent


@router.get("/categories")
def list_categories():
    """Every category, for the category drop-down."""
    return fetch_all("SELECT category_id, category_name FROM category ORDER BY category_name")


@router.get("")
def list_medicines(search: Optional[str] = None):
    """All medicines with their stock. ?search=text filters by name, generic name or maker."""
    if search:
        # The % signs mean "anything before/after". The text is passed as a parameter (%s), never glued into the SQL.
        pattern = "%" + search + "%"
        rows = fetch_all(
            "SELECT * FROM v_medicine_catalog "
            "WHERE medicine_name LIKE %s OR generic_name LIKE %s OR manufacturer LIKE %s",
            (pattern, pattern, pattern),
        )
    else:
        rows = fetch_all("SELECT * FROM v_medicine_catalog")

    # MySQL stores BOOLEAN as 0/1; turn it into true/false for the website.
    for row in rows:
        row["requires_prescription"] = bool(row["requires_prescription"])
    return rows


@router.get("/{medicine_id}/batches")
def list_batches(medicine_id: int):
    """Every batch of one medicine, earliest expiry first."""
    # (medicine_id,) - a tuple with one value needs the trailing comma
    return fetch_all("SELECT * FROM v_batch_details WHERE medicine_id = %s ORDER BY expiry_date", (medicine_id,))


@router.post("", status_code=201)
def add_medicine(medicine: MedicineIn):
    """Add a new medicine. MySQL checks the rules (unique name + maker, GST range ...)."""
    new_id = execute(
        "INSERT INTO medicine (medicine_name, generic_name, manufacturer, category_id, "
        "reorder_level, requires_prescription, gst_percent) VALUES (%s, %s, %s, %s, %s, %s, %s)",
        (medicine.medicine_name, medicine.generic_name, medicine.manufacturer, medicine.category_id,
         medicine.reorder_level, medicine.requires_prescription, medicine.gst_percent),
    )
    return {"medicine_id": new_id, "message": "Medicine added"}


@router.put("/{medicine_id}")
def edit_medicine(medicine_id: int, medicine: MedicineIn):
    """Change the details of an existing medicine (stock is NOT changed here)."""
    # First check that the medicine exists, so we can answer 404 (Not Found).
    existing = fetch_one("SELECT medicine_id FROM medicine WHERE medicine_id = %s", (medicine_id,))
    if existing is None:
        raise HTTPException(status_code=404, detail="Medicine not found")

    execute(
        "UPDATE medicine SET medicine_name = %s, generic_name = %s, manufacturer = %s, "
        "category_id = %s, reorder_level = %s, requires_prescription = %s, gst_percent = %s "
        "WHERE medicine_id = %s",
        (medicine.medicine_name, medicine.generic_name, medicine.manufacturer, medicine.category_id,
         medicine.reorder_level, medicine.requires_prescription, medicine.gst_percent, medicine_id),
    )
    return {"medicine_id": medicine_id, "message": "Medicine updated"}
