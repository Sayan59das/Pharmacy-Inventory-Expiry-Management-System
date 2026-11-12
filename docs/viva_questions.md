<!--
=====================================================================
FILE        : docs/viva_questions.md
WHAT IT DOES: 15 questions the examiner is likely to ask about THIS project, each with a short answer
              that uses our real tables, triggers and procedures.
DEPENDS ON  : the whole project (answers point to the files).
USED BY     : the team - read it LAST (docs/reading_order.md step 32), then cover the answers and try again.
READ ORDER  : last.
=====================================================================
-->

# 15 likely viva questions - with short answers

Tip: after each answer, show the file or run the query. Examiners love a live demo more than a recited definition.

---

### 1. What are primary key, foreign key and candidate key? Give examples from your project.
* **Primary key** uniquely identifies a row and is never NULL: `batch.batch_id`.
* **Candidate key** = any column set that could be the key. In `supplier`, both `supplier_id` and `gst_no` are candidates; we chose the small auto-number `supplier_id` as primary key and kept `gst_no` as `UNIQUE`.
* **Foreign key** is a column that must match a primary key elsewhere: `batch.medicine_id` -> `medicine.medicine_id`, so a batch can never refer to a medicine that does not exist.
* We use *surrogate* keys (auto-increment ids) because they are short, never change and make joins fast.

### 2. Why do you keep stock per batch and not per medicine?
Each batch has its **own expiry date, price and supplier**. If stock were a single number on `medicine`, we could not know *which* units expire first, could not sell oldest-first (FEFO), and could not raise expiry alerts. The medicine's total stock is calculated by adding its batches (view `v_current_stock`).

### 3. Explain many-to-many relationships. Which ones does your design have and how are they resolved?
A many-to-many link cannot be stored directly in one table, so it is split into two one-to-many links through a **junction table**. We have three: purchase <-> batch via `purchase_item`, sale <-> batch via `sale_item`, and supplier <-> medicine via `batch`. The junction tables also carry their own columns (`quantity`, `unit_price`, `expiry_date`...), which shows they are real entities.

### 4. What ON DELETE / ON UPDATE rules did you choose and why?
* `RESTRICT` for history that must not be orphaned: you cannot delete a medicine that has batches, or a batch that has been sold.
* `CASCADE` where a row has no meaning without its parent: deleting a bill deletes its `sale_item` lines.
* `SET NULL` for `sale.customer_id`: deleting a customer keeps the old bills as walk-in bills.
* `ON UPDATE CASCADE` as a safe default (our keys never change anyway); `stock_alert` uses `RESTRICT` because its `CHECK` constraint cannot coexist with `CASCADE`/`SET NULL` in MySQL.

### 5. Explain 1NF, 2NF and 3NF using your project. Is the design in 3NF?
We took a paper bill: **UNF** had a repeating group of items in one row. **1NF**: one row per item, atomic values. **2NF**: removed *partial* dependencies on the composite key `(bill_no, medicine, batch)` - e.g. `bill_date` depends on `bill_no` only, so it moved to `bill`. **3NF**: removed *transitive* dependencies - e.g. `bill_no -> customer_phone -> customer_name`, so `customer` became its own table; calculated columns like `line_total` were dropped. Yes, all 10 tables are in 3NF (and BCNF); `docs/normalization.md` has the proof. The few deliberate redundancies (like `quantity_in_stock`) are listed there with their safety checks.

### 6. Why don't you store the bill total, but you do store `quantity_in_stock`?
A bill total is *fully calculable* from its lines and cheap to compute, and a stored copy could go out of date, so it is calculated by `v_sale_bill` / `sp_generate_bill`. `quantity_in_stock` is also calculable (purchased - sold), but every sale needs it instantly; summing all history each time would be slow. So it is a conscious **denormalization for speed**, protected by triggers, a `CHECK (quantity_in_stock >= 0)` and a reconciliation test (`09_test_cases.sql`, E1).

### 7. Difference between a trigger and a stored procedure? BEFORE vs AFTER trigger? What are NEW and OLD?
A **procedure** is called by name (`CALL sp_make_sale(...)`); a **trigger** runs automatically when a row is inserted, updated or deleted and cannot be called. A **BEFORE** trigger runs before the row is written - we use it to *validate* (`trg_sale_item_before_insert` blocks expired or insufficient stock with `SIGNAL`). An **AFTER** trigger runs after the row is stored - we use it for *side effects* (`trg_sale_item_after_insert` reduces the stock). `NEW` is the row being inserted/changed to, `OLD` is the row before an update/delete.

### 8. What exactly happens inside MySQL when a medicine is sold?
`sp_make_bill` starts a transaction, inserts the `sale` row, and calls `sp_add_medicine_to_sale`, which inserts `sale_item` lines (one per batch). For each line: `trg_sale_item_before_insert` checks expiry and stock -> the row is saved -> `trg_sale_item_after_insert` reduces `batch.quantity_in_stock` -> that update fires `trg_batch_after_update_low_stock`, which inserts a LOW_STOCK alert if the sellable stock fell below the reorder level (and there is no open alert already). Then the procedure commits.

### 9. What are transactions and ACID? Where do you use them and what happens if the 2nd item fails?
A transaction groups statements so they all succeed or all fail. **A**tomicity (all-or-nothing), **C**onsistency (rules like CHECK always hold), **I**solation (concurrent users do not see half-done work; we also lock rows with `FOR UPDATE`), **D**urability (committed data survives a crash - InnoDB). `sp_add_purchase`, `sp_make_sale` and `sp_make_bill` use `START TRANSACTION ... COMMIT` and an `EXIT HANDLER FOR SQLEXCEPTION` that does `ROLLBACK` and `RESIGNAL`. If the 2nd item of a purchase or bill fails, the header, the 1st item and the stock change are all undone - tests C2 and C10 prove it.

### 10. What is FEFO and how did you implement it?
**First Expired, First Out**: sell the batch that expires earliest so old stock does not go to waste. `sp_add_medicine_to_sale` opens a **cursor** over the medicine's non-expired batches with stock, `ORDER BY expiry_date`, and loops: take `LEAST(still needed, batch stock)` into a `sale_item` line, and continue with the next batch until the quantity is covered - so one sale can be **split across batches**. Expired batches are never selected. Example: 40 Paracetamol = 31 from the batch expiring first + 9 from the next.

### 11. Which indexes did you create and why? Do indexes have a cost?
`idx_batch_medicine_expiry (medicine_id, expiry_date)` lets FEFO read a medicine's batches already sorted by expiry; `idx_batch_expiry (expiry_date)` serves the expiry views and the daily event; `idx_sale_date` and `idx_purchase_date` serve date reports; `idx_alert_status_type (status, alert_type)` serves the dashboard counts; `UNIQUE` constraints create indexes too, and MySQL indexes every foreign key. The cost: indexes use disk space and slow down INSERT/UPDATE a little, so we only add the ones our queries actually use.

### 12. What is a view? Why did you use views, and can you update through them?
A view is a **saved SELECT** with a name; it stores no data and is always up to date. We use 13: they hide long joins (`v_sale_bill`), keep the "sellable vs expired" definition in one place (`v_current_stock`), and let the backend run just `SELECT * FROM v_low_stock`. Our views use joins/aggregates, so they are read-only; simple one-table views can be updatable.

### 13. What is SQL injection and how does your backend prevent it?
Injection happens when user text is glued into the SQL string, e.g. `"... WHERE name = '" + text + "'"`; the text `x' OR '1'='1` then changes the query. We **never** build SQL from user text: routes use placeholders (`WHERE medicine_name LIKE %s`) and pass the values separately to `cursor.execute(sql, params)`; the driver treats them as data only. Everything else goes through stored procedures with typed parameters. (Our API test searches for `x' OR '1'='1` and gets an empty list.)

### 14. What is an EVENT, why did you need one, and how do you know it is running?
An event is MySQL's built-in scheduler (like a cron job). A medicine becomes "near expiry" just because *time passes* - no row changes - so no trigger can notice; a daily event (`evt_daily_stock_alerts`, 01:00) calls `sp_generate_expiry_alerts` and `sp_generate_low_stock_alerts`, which never create a second OPEN alert for the same batch. The scheduler must be on: `SET GLOBAL event_scheduler = ON;`. Check with `SHOW VARIABLES LIKE 'event_scheduler';` (ON), `SHOW EVENTS;`, or the process list. Test D4 creates a one-shot event and proves the scheduler fires it.

### 15. Why is the business logic inside MySQL and not in Python? How do you prove it works?
Rules in the database apply to **every** client (the web app, Workbench, a future mobile app) and cannot be bypassed by a bug in one program; they run next to the data, in one transaction, which is fast and safe. Python only calls procedures/views. We prove it with `09_test_cases.sql`: 45 automatic PASS/FAIL checks, including the failure cases (selling expired stock, selling more than available, a purchase that fails half-way) and a stock reconciliation (stored stock = purchased - sold for every batch).

---

## Bonus follow-ups the examiner may add

| Question | One-line answer |
|----------|-----------------|
| `WHERE` vs `HAVING`? | `WHERE` filters rows before grouping; `HAVING` filters groups after aggregation (query Q5). |
| `INNER JOIN` vs `LEFT JOIN`? | INNER keeps only matching rows; LEFT keeps every left row and fills NULL when there is no match (Q9). |
| `DELETE` vs `TRUNCATE` vs `DROP`? | DELETE removes chosen rows (can roll back); TRUNCATE empties the table fast; DROP removes the table itself. |
| Why `DECIMAL` for money? | It is exact; FLOAT can give 0.1 + 0.2 = 0.30000000000000004. |
| What is a cursor? | A pointer that walks a query result row by row inside a procedure: DECLARE, OPEN, FETCH in a loop, CLOSE. |
| What does `SIGNAL SQLSTATE '45000'` do? | Raises our own error with our own message and cancels the statement. |
| What is `RESIGNAL`? | Re-raises the original error after the handler did its cleanup (the `ROLLBACK`). |
| Why `utf8mb4`? | It stores every character, including symbols such as the rupee sign. |
| What is CORS? | A browser rule: a page from one origin may call another origin only if that server allows it; `main.py` allows it. |
| Why is `ENGINE = InnoDB` important? | It supports foreign keys and transactions (MyISAM supports neither). |
