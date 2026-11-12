<!--
=====================================================================
FILE        : docs/normalization.md
WHAT IT DOES: Proves the database design is in Third Normal Form (3NF).
              Starts from one messy, unnormalized pharmacy bill and fixes it
              step by step: UNF -> 1NF -> 2NF -> 3NF, naming the problem
              (dependency) that is removed at every step. Then maps the result
              to the real tables and checks every table of the final design.
DEPENDS ON  : docs/er_diagram.md (table and column names come from there).
USED BY     : Nothing in code. It is the "why is the design like this" answer
              for the viva. database/02_tables.sql implements the final design.
READ ORDER  : 3rd (README.md -> er_diagram.md -> normalization.md).
=====================================================================
-->

# Normalization — from one messy bill to 3NF

## 1. The four ideas you need (memorise these)

| Term | Meaning in one line |
|------|---------------------|
| **Functional dependency (FD)** `A → B` | If you know A, you can find exactly one B. Example: `bill_no → bill_date`. |
| **1NF** | Every cell holds **one** value (no lists), and there are no repeating groups of columns. |
| **2NF** | 1NF **+** no **partial dependency**: no column depends on only *part* of a composite key. |
| **3NF** | 2NF **+** no **transitive dependency**: no non-key column depends on another non-key column. |

The slogan: *every non-key column must depend on **the key** (1NF), **the whole key** (2NF),
and **nothing but the key** (3NF)* — "so help me Codd".

**Why bother?** Un-normalized tables suffer three *anomalies* (shown in section 3):
update, insert and delete anomalies. Normalizing removes them.

---

## 2. Starting point — the unnormalized (UNF) pharmacy bill

This is the paper bill typed into one table, exactly as a beginner would do it.
**One row = one whole bill.** The items of a bill are stacked inside the same cells
(shown with line breaks).

Attributes of the UNF relation `PHARMACY_BILL`:

```
PHARMACY_BILL( bill_no, bill_date, customer_name, customer_phone, payment_mode,
               { medicine_name, category_name, gst_percent, batch_no, expiry_date,
                 supplier_name, supplier_gst_no, quantity, unit_price, line_total },
               bill_total )
```
The part inside `{ ... }` is a **repeating group** — it occurs once for *every item* on the bill.

| bill_no | bill_date | customer_name | customer_phone | payment_mode | medicine_name | category_name | gst_percent | batch_no | expiry_date | supplier_name | supplier_gst_no | quantity | unit_price | line_total | bill_total |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1001 | 2026-11-10 | Rahul Sharma | 9876543210 | UPI | Paracetamol 500mg<br>Azithromycin 250mg<br>Cetirizine Syrup 60ml | Tablet<br>Tablet<br>Syrup | 5.00<br>5.00<br>5.00 | PCM-24A<br>AZT-11B<br>CTZ-07C | 2027-05-31<br>2027-02-28<br>2027-08-31 | MedPlus Distributors<br>HealthFirst Pharma<br>MedPlus Distributors | 27AABCM1234A1Z5<br>27AAECH5678B1Z2<br>27AABCM1234A1Z5 | 2<br>1<br>1 | 30.00<br>95.00<br>48.00 | 60.00<br>95.00<br>48.00 | 203.00 |
| 1002 | 2026-11-11 | Rahul Sharma | 9876543210 | CASH | Paracetamol 500mg | Tablet | 5.00 | PCM-24A | 2027-05-31 | MedPlus Distributors | 27AABCM1234A1Z5 | 3 | 30.00 | 90.00 | 90.00 |

**What is wrong?** Bill 1001 has cells that contain *three values each* — you cannot search
"all bills that sold Azithromycin" with a simple `WHERE`, and a bill with 10 items would
need a 10-line cell. That is the 1NF violation.

### Business rules we assume (these decide the functional dependencies)

| # | Rule | Functional dependency |
|---|------|-----------------------|
| A1 | A bill number identifies one bill. | `bill_no → bill_date, customer_phone, payment_mode` |
| A2 | A customer is identified by phone number. | `customer_phone → customer_name` |
| A3 | A medicine is identified by its name (for this exercise). Its category and GST rate are fixed per medicine — **GST is decided per medicine, not per category.** | `medicine_name → category_name, gst_percent` |
| A4 | A batch is identified by medicine **and** batch number (the same text "B1" can exist for two different medicines). | `medicine_name, batch_no → expiry_date, supplier_name` |
| A5 | A supplier is identified by name; each has one GSTIN. | `supplier_name → supplier_gst_no` |
| A6 | A bill line is identified by bill, medicine and batch. The price on the line is the price **on the day of sale** (it may differ from today's price). | `bill_no, medicine_name, batch_no → quantity, unit_price` |
| A7 | Totals are calculations. | `line_total = quantity × unit_price`;  `bill_total = sum of the line totals` |

---

## 3. Why the UNF/flat design is dangerous (the three anomalies)

Look at the flat table in Step 1 below, where Rahul Sharma, "Paracetamol 500mg" and "MedPlus Distributors"
are each repeated many times.

| Anomaly | Example in this table | Result |
|---------|----------------------|--------|
| **Update** | Rahul changes his phone number. | You must edit every row of every bill he ever made. Miss one row and the database now contains two different phone numbers for the same person. |
| **Insert** | A new supplier "Apex Pharma" is registered but has not delivered anything yet. | There is no place to store it — a row needs a `bill_no`, which needs a sale. |
| **Delete** | The only line that sold *Azithromycin 250mg* is deleted (customer returned the bill). | We lose the information that Azithromycin is a Tablet, its GST rate, and the HealthFirst supplier's GSTIN — facts that have nothing to do with that bill. |

---

## 4. Step 1 — UNF → 1NF  (remove the repeating group)

**Rule applied:** make every cell atomic. Give every item its **own row** and repeat the bill
columns on each of those rows. The repeating group has become ordinary rows.

**New primary key:** one bill number is no longer enough to identify a row (bill 1001 has three rows).
A row is identified by **(bill_no, medicine_name, batch_no)** — rule A6.

`BILL_LINE( bill_no, medicine_name, batch_no, bill_date, customer_name, customer_phone, payment_mode, category_name, gst_percent, expiry_date, supplier_name, supplier_gst_no, quantity, unit_price, line_total, bill_total )`
Primary key: **(bill_no, medicine_name, batch_no)**

| **bill_no** | bill_date | customer_name | customer_phone | payment_mode | **medicine_name** | category_name | gst_percent | **batch_no** | expiry_date | supplier_name | supplier_gst_no | quantity | unit_price | line_total | bill_total |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1001 | 2026-11-10 | Rahul Sharma | 9876543210 | UPI | Paracetamol 500mg | Tablet | 5.00 | PCM-24A | 2027-05-31 | MedPlus Distributors | 27AABCM1234A1Z5 | 2 | 30.00 | 60.00 | 203.00 |
| 1001 | 2026-11-10 | Rahul Sharma | 9876543210 | UPI | Azithromycin 250mg | Tablet | 5.00 | AZT-11B | 2027-02-28 | HealthFirst Pharma | 27AAECH5678B1Z2 | 1 | 95.00 | 95.00 | 203.00 |
| 1001 | 2026-11-10 | Rahul Sharma | 9876543210 | UPI | Cetirizine Syrup 60ml | Syrup | 5.00 | CTZ-07C | 2027-08-31 | MedPlus Distributors | 27AABCM1234A1Z5 | 1 | 48.00 | 48.00 | 203.00 |
| 1002 | 2026-11-11 | Rahul Sharma | 9876543210 | CASH | Paracetamol 500mg | Tablet | 5.00 | PCM-24A | 2027-05-31 | MedPlus Distributors | 27AABCM1234A1Z5 | 3 | 30.00 | 90.00 | 90.00 |

**Status: 1NF ✔** (all cells atomic, no repeating group, has a primary key).
**But** notice the repetition: the bill date, customer and `bill_total` are copied on all three rows of bill 1001. That repetition is a symptom of the next problem.

---

## 5. Step 2 — 1NF → 2NF  (remove partial dependencies)

**Rule applied:** a column may not depend on only *part* of the composite key `(bill_no, medicine_name, batch_no)`.

Check every non-key column against the key:

| Dependency | Depends on | Verdict |
|------------|-----------|---------|
| `bill_no → bill_date, customer_name, customer_phone, payment_mode, bill_total` | **only `bill_no`** (1 of 3 key parts) | ❌ **Partial dependency** |
| `medicine_name → category_name, gst_percent` | **only `medicine_name`** (1 of 3 key parts) | ❌ **Partial dependency** |
| `(medicine_name, batch_no) → expiry_date, supplier_name, supplier_gst_no` | **2 of 3 key parts** | ❌ **Partial dependency** |
| `(bill_no, medicine_name, batch_no) → quantity, unit_price, line_total` | the **whole** key | ✔ fine |

**Fix:** move each group of partially-dependent columns to a new table whose key is exactly the part they depend on.
What stays behind (quantity, unit_price, line_total) keeps the full key.

```
BILL      ( bill_no*, bill_date, customer_name, customer_phone, payment_mode, bill_total )
MEDICINE  ( medicine_name*, category_name, gst_percent )
BATCH     ( medicine_name*, batch_no*, expiry_date, supplier_name, supplier_gst_no )
BILL_ITEM ( bill_no*, medicine_name*, batch_no*, quantity, unit_price, line_total )
              * = part of the primary key
```

**BILL** (bill_no is the key)

| bill_no | bill_date | customer_name | customer_phone | payment_mode | bill_total |
|---|---|---|---|---|---|
| 1001 | 2026-11-10 | Rahul Sharma | 9876543210 | UPI | 203.00 |
| 1002 | 2026-11-11 | Rahul Sharma | 9876543210 | CASH | 90.00 |

**MEDICINE** (medicine_name is the key)

| medicine_name | category_name | gst_percent |
|---|---|---|
| Paracetamol 500mg | Tablet | 5.00 |
| Azithromycin 250mg | Tablet | 5.00 |
| Cetirizine Syrup 60ml | Syrup | 5.00 |

**BATCH** (key = medicine_name + batch_no)

| medicine_name | batch_no | expiry_date | supplier_name | supplier_gst_no |
|---|---|---|---|---|
| Paracetamol 500mg | PCM-24A | 2027-05-31 | MedPlus Distributors | 27AABCM1234A1Z5 |
| Azithromycin 250mg | AZT-11B | 2027-02-28 | HealthFirst Pharma | 27AAECH5678B1Z2 |
| Cetirizine Syrup 60ml | CTZ-07C | 2027-08-31 | MedPlus Distributors | 27AABCM1234A1Z5 |

**BILL_ITEM** (key = bill_no + medicine_name + batch_no)

| bill_no | medicine_name | batch_no | quantity | unit_price | line_total |
|---|---|---|---|---|---|
| 1001 | Paracetamol 500mg | PCM-24A | 2 | 30.00 | 60.00 |
| 1001 | Azithromycin 250mg | AZT-11B | 1 | 95.00 | 95.00 |
| 1001 | Cetirizine Syrup 60ml | CTZ-07C | 1 | 48.00 | 48.00 |
| 1002 | Paracetamol 500mg | PCM-24A | 3 | 30.00 | 90.00 |

**Status: 2NF ✔.** `BILL` and `MEDICINE` have a one-column key, so a *partial* dependency is
impossible there. In `BATCH`, `expiry_date` needs both `medicine_name` and `batch_no`
(the batch number alone is ambiguous). In `BILL_ITEM`, `quantity` and `unit_price` need all three key parts.

**Still wrong:** MedPlus Distributors and its GSTIN are written twice in `BATCH`, and Rahul's
name is written twice in `BILL`. Time for Step 3.

---

## 6. Step 3 — 2NF → 3NF  (remove transitive dependencies)

**Rule applied:** no non-key column may depend on another non-key column.
The chain to look for is `key → X → Y` where both X and Y are non-key.

| # | Table | Chain (transitive dependency) | Why it is a problem | Fix |
|---|-------|-------------------------------|---------------------|-----|
| T1 | BILL | `bill_no → customer_phone → customer_name` | Rahul's name is repeated on every bill he makes. | New table **CUSTOMER(customer_phone\*, customer_name)**; BILL keeps only `customer_phone` as a foreign key. |
| T2 | BATCH | `(medicine_name, batch_no) → supplier_name → supplier_gst_no` | The supplier's GSTIN is repeated on every batch from that supplier. | New table **SUPPLIER(supplier_name\*, supplier_gst_no)**; BATCH keeps only `supplier_name` as a foreign key. |
| T3 | MEDICINE | `medicine_name → category_name → category_description` *(our real design stores a description for each category)* | The description would be repeated on every medicine of that category. | New table **CATEGORY(category_name\*, category_description)**; MEDICINE keeps `category_name` as a foreign key. |
| T4 | BILL_ITEM | `key → (quantity, unit_price) → line_total` | `line_total` is calculated from two other non-key columns. Store it, then edit the quantity, and the total is wrong. | **Drop `line_total`.** Calculate `quantity × unit_price` in a query. |
| T5 | BILL | `bill_total` = sum of the BILL_ITEM rows of that bill | Not a dependency inside one table, but it is stored data that can be calculated; it will go stale when an item changes. | **Drop `bill_total`.** Calculate `SUM(...)` in a view / procedure. |

### Result — the 3NF relations

```
CUSTOMER  ( customer_phone*, customer_name )
BILL      ( bill_no*, bill_date, customer_phone → CUSTOMER, payment_mode )
CATEGORY  ( category_name*, category_description )
MEDICINE  ( medicine_name*, category_name → CATEGORY, gst_percent )
SUPPLIER  ( supplier_name*, supplier_gst_no )
BATCH     ( medicine_name* → MEDICINE, batch_no*, expiry_date, supplier_name → SUPPLIER )
BILL_ITEM ( bill_no* → BILL, (medicine_name*, batch_no*) → BATCH, quantity, unit_price )
```

**CUSTOMER**

| customer_phone | customer_name |
|---|---|
| 9876543210 | Rahul Sharma |

**SUPPLIER**

| supplier_name | supplier_gst_no |
|---|---|
| MedPlus Distributors | 27AABCM1234A1Z5 |
| HealthFirst Pharma | 27AAECH5678B1Z2 |

**BILL**

| bill_no | bill_date | customer_phone | payment_mode |
|---|---|---|---|
| 1001 | 2026-11-10 | 9876543210 | UPI |
| 1002 | 2026-11-11 | 9876543210 | CASH |

**BATCH**

| medicine_name | batch_no | expiry_date | supplier_name |
|---|---|---|---|
| Paracetamol 500mg | PCM-24A | 2027-05-31 | MedPlus Distributors |
| Azithromycin 250mg | AZT-11B | 2027-02-28 | HealthFirst Pharma |
| Cetirizine Syrup 60ml | CTZ-07C | 2027-08-31 | MedPlus Distributors |

(`MEDICINE` and `BILL_ITEM` are the same as in Step 2, just without `line_total`.)

**Status: 3NF ✔.** Every fact is now stored in exactly one place. Rahul's phone changes in **1 row**;
a supplier can be inserted before any delivery; deleting a bill no longer deletes the medicine facts.

---

## 7. Step 4 — from the exercise to the real database

The exercise used natural keys (phone, names) to keep the dependencies easy to see. The real design
(`docs/er_diagram.md`) changes only these things, none of which break 3NF:

| Exercise table | Real table | What changed |
|----------------|-----------|--------------|
| CUSTOMER | `customer` | Surrogate key `customer_id`; `customer_phone` becomes `phone` with UNIQUE; `address` added. |
| BILL | `sale` | `bill_no` becomes `sale_id`; foreign key is `customer_id` and is **nullable** (walk-in). |
| CATEGORY | `category` | Surrogate key `category_id`; `category_name` is UNIQUE. |
| MEDICINE | `medicine` | Surrogate key; added `generic_name`, `manufacturer`, `reorder_level`, `requires_prescription`. |
| SUPPLIER | `supplier` | Surrogate key; `supplier_gst_no` becomes `gst_no` UNIQUE; added contact columns. |
| BATCH | `batch` | Composite key replaced by `batch_id` + UNIQUE(medicine_id, supplier_id, batch_no); added `manufacture_date`, `cost_price`, `selling_price`, `quantity_in_stock`. |
| BILL_ITEM | `sale_item` | Composite key replaced by `sale_item_id` + UNIQUE(sale_id, batch_id); medicine is reached through the batch; **added the `gst_percent` snapshot** (see below). |
| *(not in the bill)* | `purchase`, `purchase_item` | The buying side follows the **same header + line-item pattern** as `sale`, `sale_item`, so the same normalization steps apply. |
| *(not in the bill)* | `stock_alert` | System-generated warnings (new table). |

**Why `sale_item` stores `unit_price` and `gst_percent` while `medicine` / `batch` also have a price and GST rate:**
they are different facts. `batch.selling_price` / `medicine.gst_percent` answer *"what is the price/rate **today**?"*.
`sale_item.unit_price` / `sale_item.gst_percent` answer *"what did the customer pay **on that bill**?"* (rule A6).
Because the first can change, the second must be stored — otherwise an old bill would silently
change when a price is edited. This is not a transitive dependency; it is a separate historical fact about the line.
The same reasoning applies to `purchase_item.unit_cost`.

---

## 8. Proof — every table of the final design is in 3NF

For each table: list the candidate keys, list every functional dependency, and check that
**every determinant (left side of an FD) is a key**. If it is, there is no partial or transitive dependency.

| Table | Candidate keys | Functional dependencies (all of them) | Verdict |
|-------|----------------|----------------------------------------|---------|
| `supplier` | `supplier_id`; `gst_no` | `supplier_id → all other columns`; `gst_no → all other columns` | Both determinants are keys ✔ |
| `category` | `category_id`; `category_name` | `category_id → category_name, description`; `category_name → category_id, description` | ✔ |
| `medicine` | `medicine_id`; (`medicine_name`, `manufacturer`) | `medicine_id → all`; `(medicine_name, manufacturer) → all`. *Not* an FD: `category_id → gst_percent` (GST is decided per medicine — rule A3), `generic_name → category_id` (Paracetamol exists as tablet and as syrup). | ✔ |
| `batch` | `batch_id`; (`medicine_id`, `supplier_id`, `batch_no`) | `batch_id → all`; `(medicine_id, supplier_id, batch_no) → all`. *Not* an FD: `medicine_id → selling_price` (every batch has its own price), `expiry_date → anything`. | ✔ |
| `purchase` | `purchase_id`; (`supplier_id`, `invoice_no`) | `purchase_id → supplier_id, invoice_no, purchase_date`; `(supplier_id, invoice_no) → purchase_id, purchase_date` | ✔ |
| `purchase_item` | `purchase_item_id`; (`purchase_id`, `batch_id`) | `purchase_item_id → purchase_id, batch_id, quantity, unit_cost`; `(purchase_id, batch_id) → all`. `unit_cost` is **not** determined by `batch_id` alone (snapshot per invoice line). | ✔ |
| `customer` | `customer_id`; `phone` (when present) | `customer_id → customer_name, phone, address`; `phone → all` | ✔ |
| `sale` | `sale_id` | `sale_id → customer_id, sale_date, payment_mode`. Nothing else determines anything (a customer does not determine the payment mode or the time). | ✔ |
| `sale_item` | `sale_item_id`; (`sale_id`, `batch_id`) | `sale_item_id → all`; `(sale_id, batch_id) → quantity, unit_price, gst_percent`. `quantity`, `unit_price`, `gst_percent` are independent of each other. | ✔ |
| `stock_alert` | `alert_id` | `alert_id → alert_type, medicine_id, batch_id, message, status, created_at, resolved_at` | ✔ (see footnote F1) |

**BCNF as a bonus:** in all ten tables, every determinant is a candidate key, so the design also satisfies
Boyce–Codd Normal Form, the stricter version of 3NF.

---

## 9. Honest footnotes — deliberate, controlled redundancy

Normal forms only look *inside one table*. Four places in the design keep information that could be
calculated or that appears in two tables. They are on purpose, and each has a safety mechanism.
Being able to explain these in the viva is worth more than pretending they do not exist.

| # | What | Why we keep it | Safety mechanism |
|---|------|----------------|------------------|
| F1 | `stock_alert.status` can be worked out from `resolved_at` (NULL means OPEN). | Your brief asks for a status; `WHERE status = 'OPEN'` is clearer and easier to index than `WHERE resolved_at IS NULL`. | `CHECK` constraint: status and resolved_at can never disagree. |
| F2 | `batch.quantity_in_stock` is, in principle, *total purchased − total sold* for that batch. | Reading stock must be instant (every sale checks it); recalculating from all sales rows each time would be slow. This is the classic "denormalize for speed" decision. | Only the triggers change it, inside the same transaction as the sale/purchase; `CHECK (quantity_in_stock >= 0)`; `09_test_cases.sql` (test E1) runs a reconciliation query that compares the stored value with purchases − sales for every batch. |
| F3 | `batch.supplier_id` and `purchase.supplier_id` both identify the supplier. | `batch.supplier_id` was requested and makes "who gave us this batch?" one join. | The BEFORE INSERT trigger `trg_purchase_item_before_insert` refuses a purchase line whose batch belongs to another supplier (see er_diagram.md, decision 9; tested in B2 and E4). |
| F4 | `sale_item.unit_price`, `sale_item.gst_percent`, `purchase_item.unit_cost` look like copies of current prices. | They are historical facts (section 7), not copies. | Set once when the row is inserted; the application never edits them. |

---

## 10. Before vs after — the anomalies are gone

| Anomaly | In the flat table | In the 3NF design |
|---------|-------------------|--------------------|
| **Update** — customer changes phone | Edit every row of every bill (miss one → contradiction). | `UPDATE customer SET phone = ... WHERE customer_id = ...;` — **one row**. |
| **Insert** — new supplier, no purchase yet | Impossible without a fake bill. | `INSERT INTO supplier ...;` — works on its own. |
| **Delete** — the only Azithromycin sale is removed | Medicine, category, GST rate and supplier facts vanish. | Delete from `sale_item` only; `medicine`, `batch`, `supplier` rows remain. |
| **Totals** | `bill_total` can disagree with its items. | Totals are calculated by views/procedures — they cannot disagree. |

---

## 11. Viva one-liners from this document

* **What is normalization?** Splitting tables so each fact is stored once, to remove update, insert and delete anomalies.
* **1NF / 2NF / 3NF in one line each?** Atomic cells · no partial dependency on a composite key · no non-key → non-key dependency.
* **Which tables resolve many-to-many relationships?** `purchase_item` (purchase ↔ batch), `sale_item` (sale ↔ batch), `batch` (supplier ↔ medicine).
* **Is your design 3NF?** Yes — every determinant is a candidate key in all 10 tables (so it is BCNF too). The few deliberate redundancies (F1–F4) are explained and protected by constraints/triggers.
* **Why are totals not stored?** They are calculable; a stored copy can go out of sync with the item rows.
* **Why does `sale_item` store the price when `batch` already has one?** The batch price is today's price; the sale_item price is what was charged on that bill — it must never change.
