<!--
=====================================================================
FILE        : docs/work_split.md
WHAT IT DOES: Divides the project among the 4 team members: who owns which files, what each person
              must be able to EXPLAIN in the viva, and in what order to work and hand over.
DEPENDS ON  : the whole project (it points to the files).
USED BY     : the team - read it together in the first meeting.
READ ORDER  : after docs/reading_order.md.
=====================================================================
-->

# Work split - 4 members

**Rule of the viva:** the examiner may ask ANY member about ANY file. The split below says who is the
*owner* (explains the details). Every member must still know the one-minute story of the whole project
(section 5) and must have run `run_all.sql`, the backend and the web pages at least once.

## 1. The split at a glance

| | Member 1 - **Design & Tables** | Member 2 - **Data & Queries** | Member 3 - **Automation & Tests** | Member 4 - **Backend, Frontend & Docs** |
|---|---|---|---|---|
| **Theme** | "What do we store and why?" | "What is in the database and how do we ask questions?" | "How does the database run itself?" | "How does a user reach the database?" |
| **Files** | `docs/er_diagram.md`<br>`docs/normalization.md`<br>`database/01_create_database.sql`<br>`database/02_tables.sql` | `database/03_sample_data.sql`<br>`database/04_views.sql`<br>`database/08_demo_queries.sql` | `database/05_triggers.sql`<br>`database/06_procedures.sql`<br>`database/07_events.sql`<br>`database/run_all.sql`<br>`database/09_test_cases.sql` | `backend/` (all files)<br>`frontend/` (all files)<br>`README.md`<br>`docs/file_connections.md`<br>`docs/reading_order.md`<br>`docs/work_split.md`<br>`docs/viva_questions.md` |
| **Size** | small, but the theory is deep | medium | the largest and the hardest | large (many files, but each is simple) |

> **Balance tip:** Member 3 has the most difficult code and Member 4 has the most files. If someone is
> overloaded, Member 2 (lighter) takes `docs/viva_questions.md` and the Member 4 flowchart documents.

## 2. What each member must be ready to explain

### Member 1 - Design & Tables
* Why the pharmacy needs 10 tables and what each table stores; stock is tracked **per batch** because each batch has its own expiry date.
* Primary key, foreign key, candidate key, surrogate key - an example of each from our tables.
* Cardinalities (1:N everywhere) and the **3 many-to-many** relationships resolved by `purchase_item`, `sale_item` and `batch`.
* Why every `ON DELETE` rule was chosen: `RESTRICT` (history must not vanish), `CASCADE` (a bill line dies with its bill), `SET NULL` (customer deleted -> bill stays as walk-in).
* Normalization on the "pharmacy bill": UNF -> 1NF -> 2NF -> 3NF, naming the dependency removed at each step; the proof table; the honest footnotes F1-F4.
* Every `CHECK`, `UNIQUE`, `DEFAULT` and each index in `02_tables.sql` and the reason it exists.
* **Demo role:** show the ER diagram and run `SHOW CREATE TABLE batch;`.

### Member 2 - Data & Queries
* How the sample data is built: ids written explicitly, dates relative to `CURDATE()`, the temporary table for sale lines, and why opening stock is one `UPDATE` (purchased - sold).
* The 13 views: what each one shows, which joins and `GROUP BY`s it uses, the "sellable vs expired" rule, why `v_sale_bill` cannot take a parameter and how the GST is extracted from the MRP.
* What a view is, why it stores no data, advantages (reuse, simplicity, security) and its limits.
* All 20 demo queries: explain any of them line by line - joins, `HAVING` vs `WHERE`, subquery vs correlated subquery, `EXISTS`, `CASE`, `UNION`, `RANK()` and `SUM() OVER`.
* **Demo role:** run 3-4 queries live (Q9 LEFT JOIN, Q12 correlated subquery, Q19 `RANK`, Q20 running total).

### Member 3 - Automation & Tests
* The 5 triggers: BEFORE vs AFTER, `NEW`/`OLD`, `SIGNAL SQLSTATE '45000'`, and the chain "sale line -> stock reduced -> LOW_STOCK alert".
* The 9 procedures: `IN`/`OUT` parameters, `DELIMITER`, transactions with `START TRANSACTION`/`COMMIT`/`ROLLBACK`, the `EXIT HANDLER` + `RESIGNAL`, the cursor loops, `JSON_TABLE`.
* **FEFO** (`sp_add_medicine_to_sale`): order by expiry, split across batches, `FOR UPDATE` locking, why expired batches are skipped.
* ACID with our examples: what happens when the 2nd item of a purchase or a bill fails (test C2, C10).
* The event: what it is, why a trigger cannot do the same job, how to switch the scheduler on and check it (`SHOW VARIABLES LIKE 'event_scheduler'`).
* `09_test_cases.sql`: the failure cases, the stock reconciliation query (E1), what PASS/FAIL means.
* **Demo role:** sell 40 Paracetamol and show the FEFO split; try to sell expired stock; run `09_test_cases.sql`.

### Member 4 - Backend, Frontend & Docs
* The request journey: button click -> page script -> `api.js` -> FastAPI route -> `db.py` -> MySQL -> back to the page.
* Why Python holds **no** business logic and how every route only calls a view or a procedure.
* **SQL injection** and how parameterized queries (`%s`) prevent it; also XSS and why `escapeHtml()` exists.
* CORS (what it is and why it is enabled), how MySQL `SIGNAL` messages become HTTP 400 answers (`main.py`), HTTP status codes used (200, 201, 400, 404, 409, 422, 503).
* How `callproc` returns `OUT` parameters and several result sets; why the cart is sent as JSON.
* The pages: dashboard, medicines, suppliers, purchase, sale (cart + printable bill), reports.
* `README.md` setup steps, the two flowcharts, and `docs/viva_questions.md`.
* **Demo role:** run the whole web demo (see section 4).

## 3. Order of work and hand-over

```
Member 1: ER diagram + 02_tables.sql  ──►  Member 2: 03_sample_data + 04_views  ──►  Member 3: 05..07 + 09
                                                                                   │
                                                  Member 4: backend + frontend ◄───┘ (can start with GET pages as soon as the views exist)
```

| Week | Member 1 | Member 2 | Member 3 | Member 4 |
|------|----------|----------|----------|----------|
| 1 | ER diagram, `normalization.md` | read ER doc; plan the sample data | read ER doc; plan triggers on paper | set up folders, MySQL, Python; build `db.py`, `main.py` |
| 2 | `01`, `02_tables.sql`; hand over | `03_sample_data.sql`, `04_views.sql` | `05_triggers.sql`, `06_procedures.sql` | read-only routes + dashboard / medicines pages |
| 3 | review Member 3's constraints and trigger logic | `08_demo_queries.sql`; hand over views | `07_events.sql`, `run_all.sql`, `09_test_cases.sql` | purchase / sale / reports pages, `README.md` |
| 4 | **everyone:** full rebuild with `run_all.sql`, run `09_test_cases.sql` (all PASS), practise the viva with `docs/viva_questions.md`, rehearse the demo |

**Cross-review (every member checks another member's files once):** 1 reviews 3, 3 reviews 4, 4 reviews 2, 2 reviews 1.

## 4. Suggested viva demo (about 8 minutes)

1. **(Member 1, 1 min)** Open `er_diagram.md`: 10 tables, stock per batch, 3 junction tables.
2. **(Member 2, 2 min)** In MySQL run `SELECT * FROM v_low_stock;`, `v_expiring_soon`, and one window-function query.
3. **(Member 3, 2 min)** `CALL sp_make_sale(NULL, 1, 40, 'CASH', @id);` then show the two bill lines (FEFO split) and the lower stock; then try to sell an expired medicine and show the error and the rollback.
4. **(Member 4, 2 min)** In the browser: dashboard -> sale page -> add two medicines -> Generate bill -> print; buy stock on the purchase page; show the alert on the dashboard.
5. **(everyone, 1 min)** `09_test_cases.sql` summary: all checks PASS.

## 5. The one-minute story every member must be able to tell

> "Our pharmacy system stores everything in MySQL. Stock is counted per batch because every batch has its own
> expiry date. When a medicine is sold, the procedure `sp_make_bill` takes units from the batch that expires first
> (FEFO); triggers check that the batch is not expired and has enough stock, reduce the stock and create a LOW_STOCK
> alert if needed. A daily event creates NEAR_EXPIRY and EXPIRED alerts. Procedures use transactions so a bill or a
> purchase is saved completely or not at all. The Python backend only calls views and procedures with parameterized
> queries, and the web pages call the backend. The design is in 3NF, and 45 test checks prove that the rules work."

## 6. Files nobody owns alone

* `.env` (each member's own MySQL password; never commit it).
* Git hygiene: commit small, write clear messages, never edit another member's file without telling them.
