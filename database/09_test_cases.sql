-- =====================================================================
-- FILE        : database/09_test_cases.sql
-- WHAT IT DOES: Tests every view, trigger, procedure and the event, including
--               the FAILURE cases (selling expired stock, selling more than
--               exists, a purchase that fails half-way ...).
--               Every check writes PASS or FAIL into a results table, and a
--               summary at the very end tells you how many passed.
-- DEPENDS ON  : the FRESH database built by run_all.sql (the expected
--               numbers assume the original sample data).
-- USED BY     : you, before the viva and before every demo.
-- RUN ORDER   : run run_all.sql FIRST, then this file.
--
-- WARNING: some tests change data for real (they call the procedures, which
--          COMMIT). When you finish, run run_all.sql again to get a clean database.
--
-- HOW TO READ A TEST
--   * "EXPECTED:" comments say what must happen.
--   * Tests that must FAIL show an ERROR 1644 (45000) message - that is the CORRECT result.
--     Afterwards a PASS/FAIL check proves that nothing was changed (all-or-nothing).
--   * The tests that need START TRANSACTION ... ROLLBACK leave the database untouched.
--
-- HOW TO RUN
--   Command line (continues after the expected errors):
--         mysql -u root -p --force < 09_test_cases.sql
--   MySQL Workbench: it stops at the first error. Select ONE test block and run it
--   with Ctrl+Shift+Enter. If a block stopped in the middle of a transaction, type
--   ROLLBACK; and run it.
-- =====================================================================

USE pharmacy_db;

-- ---------------------------------------------------------------------
-- The results table. TEMPORARY = it disappears when you disconnect.
-- ENGINE = MyISAM is chosen on purpose: MyISAM is NOT transactional, so a PASS/FAIL row
-- written between START TRANSACTION and ROLLBACK is NOT undone by the ROLLBACK.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS test_results;
CREATE TEMPORARY TABLE test_results (
    seq          INT AUTO_INCREMENT PRIMARY KEY,   -- keeps the tests in the order they ran
    test_id      VARCHAR(10),                      -- e.g. A1, B3
    description  VARCHAR(160),                     -- what was checked
    result       VARCHAR(4)                        -- PASS or FAIL
) ENGINE = MyISAM;


-- #####################################################################
-- PART A - VIEWS  (read-only checks against the original sample data)
-- #####################################################################

-- A1 v_current_stock: Paracetamol 500mg has batches of 14 (expired), 31 and 150 units.
-- EXPECTED: total 195, sellable 181, expired 14.
INSERT INTO test_results (test_id, description, result)
SELECT 'A1', 'v_current_stock: Paracetamol total 195, sellable 181, expired 14',
       IF(total_quantity = 195 AND sellable_quantity = 181 AND expired_quantity = 14, 'PASS', 'FAIL')
FROM v_current_stock WHERE medicine_id = 1;

-- A2 v_low_stock lists the medicines whose SELLABLE stock is below the reorder level.
-- EXPECTED: 5 medicines.
INSERT INTO test_results (test_id, description, result)
SELECT 'A2', 'v_low_stock returns 5 medicines', IF(COUNT(*) = 5, 'PASS', 'FAIL') FROM v_low_stock;

-- A3 v_expiring_soon: batches with stock that expire within 30 days.  EXPECTED: 7.
INSERT INTO test_results (test_id, description, result)
SELECT 'A3', 'v_expiring_soon returns 7 batches', IF(COUNT(*) = 7, 'PASS', 'FAIL') FROM v_expiring_soon;

-- A4 v_expired_stock: expired batches that still hold stock.  EXPECTED: 4.
INSERT INTO test_results (test_id, description, result)
SELECT 'A4', 'v_expired_stock returns 4 batches', IF(COUNT(*) = 4, 'PASS', 'FAIL') FROM v_expired_stock;

-- A5 v_sale_bill for bill 1: 5 x 28.00 + 2 x 22.00 = 184.00; GST inside = 6.67 + 2.10 = 8.77.
INSERT INTO test_results (test_id, description, result)
SELECT 'A5', 'v_sale_bill: bill 1 has 2 lines, total 184.00, GST 8.77',
       IF(COUNT(*) = 2 AND SUM(line_total) = 184.00 AND SUM(gst_amount) = 8.77, 'PASS', 'FAIL')
FROM v_sale_bill WHERE sale_id = 1;

-- A6 v_supplier_purchase_summary: 8 suppliers; MedPlus Distributors (id 1) spent 10129.00.
INSERT INTO test_results (test_id, description, result)
SELECT 'A6', 'v_supplier_purchase_summary: 8 suppliers, MedPlus total 10129.00',
       IF(COUNT(*) = 8 AND SUM(CASE WHEN supplier_id = 1 THEN total_amount_spent ELSE 0 END) = 10129.00, 'PASS', 'FAIL')
FROM v_supplier_purchase_summary;

-- A7 v_top_selling_medicines: Paracetamol 500mg sold most (61 units).
INSERT INTO test_results (test_id, description, result)
SELECT 'A7', 'v_top_selling_medicines: first row is Paracetamol 500mg with 61 units',
       IF(medicine_name = 'Paracetamol 500mg' AND units_sold = 61, 'PASS', 'FAIL')
FROM v_top_selling_medicines LIMIT 1;

-- A8 v_medicine_catalog: the next batch to be sold (FEFO) for Paracetamol is batch 2 (price 30.00).
INSERT INTO test_results (test_id, description, result)
SELECT 'A8', 'v_medicine_catalog: Paracetamol current_price 30.00 = FEFO batch 2',
       IF(c.current_price = 30.00 AND c.next_expiry_date = (SELECT expiry_date FROM batch WHERE batch_id = 2), 'PASS', 'FAIL')
FROM v_medicine_catalog AS c WHERE c.medicine_id = 1;

-- A9 v_open_alerts: run_all.sql created 5 LOW_STOCK + 7 NEAR_EXPIRY + 4 EXPIRED alerts.
INSERT INTO test_results (test_id, description, result)
SELECT 'A9', 'v_open_alerts shows 16 open alerts after run_all.sql', IF(COUNT(*) = 16, 'PASS', 'FAIL') FROM v_open_alerts;


-- #####################################################################
-- PART B - TRIGGERS  (every block uses a transaction and ends with ROLLBACK,
--          so the data is not changed)
-- #####################################################################

-- ---------------------------------------------------------------------
-- B1 trg_purchase_item_after_insert: a purchase line ADDS stock.
-- Batch 3 (Paracetamol PCM-25A, supplier 4) holds 150. Buy 10 more from supplier 4.
-- EXPECTED: stock becomes 160 inside the transaction, and 150 again after ROLLBACK.
-- ---------------------------------------------------------------------
SET @stock_before = (SELECT quantity_in_stock FROM batch WHERE batch_id = 3);
START TRANSACTION;
INSERT INTO purchase (supplier_id, invoice_no, purchase_date) VALUES (4, 'INV-TEST-B1', CURDATE());
INSERT INTO purchase_item (purchase_id, batch_id, quantity, unit_cost) VALUES (LAST_INSERT_ID(), 3, 10, 22.00);
INSERT INTO test_results (test_id, description, result)
SELECT 'B1', 'purchase_item AFTER INSERT adds 10 units to the batch (150 -> 160)',
       IF(quantity_in_stock = @stock_before + 10, 'PASS', 'FAIL') FROM batch WHERE batch_id = 3;
ROLLBACK;
INSERT INTO test_results (test_id, description, result)
SELECT 'B1b', 'ROLLBACK restores the stock to 150',
       IF(quantity_in_stock = @stock_before, 'PASS', 'FAIL') FROM batch WHERE batch_id = 3;

-- ---------------------------------------------------------------------
-- B2 trg_purchase_item_before_insert: wrong supplier is refused.
-- Batch 1 belongs to supplier 1 but the invoice is from supplier 4.
-- EXPECTED: ERROR 1644 (45000): Supplier mismatch: this batch belongs to a different supplier than the purchase invoice
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO purchase (supplier_id, invoice_no, purchase_date) VALUES (4, 'INV-TEST-B2', CURDATE());
INSERT INTO purchase_item (purchase_id, batch_id, quantity, unit_cost) VALUES (LAST_INSERT_ID(), 1, 5, 20.00);
ROLLBACK;
INSERT INTO test_results (test_id, description, result)
SELECT 'B2', 'purchase_item with a batch of another supplier was refused (nothing saved)',
       IF(COUNT(*) = 0, 'PASS', 'FAIL') FROM purchase WHERE invoice_no = 'INV-TEST-B2';

-- ---------------------------------------------------------------------
-- B3 trg_sale_item_before_insert, rule 1: an EXPIRED batch cannot be sold.
-- Batch 1 (PCM-23K) expired 25 days ago.
-- EXPECTED: ERROR 1644 (45000): Cannot sell batch PCM-23K: it expired on <date>
-- ---------------------------------------------------------------------
SET @sales_before = (SELECT COUNT(*) FROM sale);
SET @items_before = (SELECT COUNT(*) FROM sale_item);
START TRANSACTION;
INSERT INTO sale (customer_id, payment_mode) VALUES (NULL, 'CASH');
INSERT INTO sale_item (sale_id, batch_id, quantity, unit_price, gst_percent) VALUES (LAST_INSERT_ID(), 1, 1, 28.00, 5.00);
ROLLBACK;
INSERT INTO test_results (test_id, description, result)
SELECT 'B3', 'sale_item for an EXPIRED batch was refused (no sale, no item saved)',
       IF((SELECT COUNT(*) FROM sale) = @sales_before AND (SELECT COUNT(*) FROM sale_item) = @items_before
          AND (SELECT quantity_in_stock FROM batch WHERE batch_id = 1) = 14, 'PASS', 'FAIL');

-- ---------------------------------------------------------------------
-- B4 trg_sale_item_before_insert, rule 2: you cannot sell more than the batch holds.
-- Batch 8 (Cetirizine CTZ-24A) holds 23 units; we try to sell 24.
-- EXPECTED: ERROR 1644 (45000): Insufficient stock in batch CTZ-24A: requested 24, available 23
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO sale (customer_id, payment_mode) VALUES (NULL, 'CASH');
INSERT INTO sale_item (sale_id, batch_id, quantity, unit_price, gst_percent) VALUES (LAST_INSERT_ID(), 8, 24, 22.00, 5.00);
ROLLBACK;
INSERT INTO test_results (test_id, description, result)
SELECT 'B4', 'sale_item with quantity above the batch stock was refused',
       IF((SELECT COUNT(*) FROM sale_item) = @items_before AND (SELECT quantity_in_stock FROM batch WHERE batch_id = 8) = 23, 'PASS', 'FAIL');

-- ---------------------------------------------------------------------
-- B5 trg_sale_item_after_insert: a sale line REDUCES stock.
-- Sell 2 units of batch 8 (23 -> 21), then ROLLBACK (back to 23).
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO sale (customer_id, payment_mode) VALUES (NULL, 'CASH');
INSERT INTO sale_item (sale_id, batch_id, quantity, unit_price, gst_percent) VALUES (LAST_INSERT_ID(), 8, 2, 22.00, 5.00);
INSERT INTO test_results (test_id, description, result)
SELECT 'B5', 'sale_item AFTER INSERT reduces batch stock 23 -> 21',
       IF(quantity_in_stock = 21, 'PASS', 'FAIL') FROM batch WHERE batch_id = 8;
ROLLBACK;
INSERT INTO test_results (test_id, description, result)
SELECT 'B5b', 'ROLLBACK restores batch 8 to 23',
       IF(quantity_in_stock = 23, 'PASS', 'FAIL') FROM batch WHERE batch_id = 8;

-- ---------------------------------------------------------------------
-- B6 trg_batch_after_update_low_stock: LOW_STOCK alert is created ONCE.
-- Cetirizine 10mg: reorder level 50, sellable stock 76 (batch 8: 23, batch 9: 53), no open alert yet.
--   step 1: sell 27 from batch 9  -> sellable 49 < 50  -> ONE new LOW_STOCK alert
--   step 2: sell 1 more           -> still low         -> NO second alert (no duplicates)
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO sale (customer_id, payment_mode) VALUES (NULL, 'CASH');
INSERT INTO sale_item (sale_id, batch_id, quantity, unit_price, gst_percent) VALUES (LAST_INSERT_ID(), 9, 27, 23.00, 5.00);
INSERT INTO test_results (test_id, description, result)
SELECT 'B6', 'Stock falls below reorder level -> exactly 1 OPEN LOW_STOCK alert for Cetirizine',
       IF(COUNT(*) = 1, 'PASS', 'FAIL') FROM stock_alert
WHERE alert_type = 'LOW_STOCK' AND status = 'OPEN' AND medicine_id = 4;

INSERT INTO sale (customer_id, payment_mode) VALUES (NULL, 'CASH');
INSERT INTO sale_item (sale_id, batch_id, quantity, unit_price, gst_percent) VALUES (LAST_INSERT_ID(), 9, 1, 23.00, 5.00);
INSERT INTO test_results (test_id, description, result)
SELECT 'B6b', 'A further sale does NOT create a duplicate OPEN alert',
       IF(COUNT(*) = 1, 'PASS', 'FAIL') FROM stock_alert
WHERE alert_type = 'LOW_STOCK' AND status = 'OPEN' AND medicine_id = 4;
ROLLBACK;
INSERT INTO test_results (test_id, description, result)
SELECT 'B6c', 'ROLLBACK also removes the alert (it was part of the transaction)',
       IF(COUNT(*) = 0, 'PASS', 'FAIL') FROM stock_alert
WHERE alert_type = 'LOW_STOCK' AND status = 'OPEN' AND medicine_id = 4;


-- #####################################################################
-- PART C - STORED PROCEDURES  (these COMMIT: they change the data for real)
-- #####################################################################

-- ---------------------------------------------------------------------
-- C1 sp_add_purchase - SUCCESS with a top-up AND a new batch in one invoice.
--   item 1: existing batch PCM-25A of supplier 4 -> top-up of 20 units (batch 3: 150 -> 170)
--   item 2: NEW batch AML-26Z (Amlodipine) of 60 units
-- EXPECTED: @pid_c1 is set, stock +20, a new batch with 60 units, 2 purchase_item rows.
-- ---------------------------------------------------------------------
SET @stock3_before    = (SELECT quantity_in_stock FROM batch WHERE batch_id = 3);
SET @purchases_before = (SELECT COUNT(*) FROM purchase);
SET @batches_before   = (SELECT COUNT(*) FROM batch);

CALL sp_add_purchase(
    4, 'INV-TEST-C1', CURDATE(),
    JSON_ARRAY(
        JSON_OBJECT('medicine_id', 1, 'batch_no', 'PCM-25A', 'quantity', 20, 'unit_cost', 23.50),
        JSON_OBJECT('medicine_id', 6, 'batch_no', 'AML-26Z',
                    'manufacture_date', DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 30 DAY), '%Y-%m-%d'),
                    'expiry_date',      DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 700 DAY), '%Y-%m-%d'),
                    'quantity', 60, 'unit_cost', 29.00, 'selling_price', 45.00)
    ),
    @pid_c1);

INSERT INTO test_results (test_id, description, result)
SELECT 'C1', 'sp_add_purchase returned a purchase id and created ONE purchase with 2 items',
       IF(@pid_c1 IS NOT NULL AND (SELECT COUNT(*) FROM purchase) = @purchases_before + 1
          AND (SELECT COUNT(*) FROM purchase_item WHERE purchase_id = @pid_c1) = 2, 'PASS', 'FAIL');
INSERT INTO test_results (test_id, description, result)
SELECT 'C1b', 'top-up: existing batch 3 gained 20 units, no duplicate batch row for PCM-25A',
       IF((SELECT quantity_in_stock FROM batch WHERE batch_id = 3) = @stock3_before + 20
          AND (SELECT COUNT(*) FROM batch WHERE batch_no = 'PCM-25A') = 1, 'PASS', 'FAIL');
INSERT INTO test_results (test_id, description, result)
SELECT 'C1c', 'new batch AML-26Z was created with 60 units, cost 29.00, MRP 45.00',
       IF(quantity_in_stock = 60 AND cost_price = 29.00 AND selling_price = 45.00
          AND (SELECT COUNT(*) FROM batch) = @batches_before + 1, 'PASS', 'FAIL')
FROM batch WHERE batch_no = 'AML-26Z';

-- ---------------------------------------------------------------------
-- C2 sp_add_purchase - FAILURE HALF-WAY must undo EVERYTHING (atomicity).
-- Item 1 is valid, item 2 has selling_price 10.00 below cost 90.00 (violates chk_batch_price).
-- EXPECTED: ERROR 3819 (HY000): Check constraint 'chk_batch_price' is violated.
--           Afterwards: no new purchase, batch 3 stock unchanged.
-- ---------------------------------------------------------------------
SET @purchases_before = (SELECT COUNT(*) FROM purchase);
SET @stock3_before    = (SELECT quantity_in_stock FROM batch WHERE batch_id = 3);
CALL sp_add_purchase(
    4, 'INV-TEST-C2', CURDATE(),
    JSON_ARRAY(
        JSON_OBJECT('medicine_id', 1, 'batch_no', 'PCM-25A', 'quantity', 5, 'unit_cost', 23.00),
        JSON_OBJECT('medicine_id', 7, 'batch_no', 'ATV-BAD', 'manufacture_date', '2026-01-01',
                    'expiry_date', '2028-01-01', 'quantity', 5, 'unit_cost', 90.00, 'selling_price', 10.00)
    ),
    @pid_c2);
INSERT INTO test_results (test_id, description, result)
SELECT 'C2', 'failed purchase left NOTHING behind (no header, stock unchanged, no new batch)',
       IF((SELECT COUNT(*) FROM purchase) = @purchases_before
          AND (SELECT quantity_in_stock FROM batch WHERE batch_id = 3) = @stock3_before
          AND (SELECT COUNT(*) FROM batch WHERE batch_no = 'ATV-BAD') = 0
          AND @pid_c2 IS NULL, 'PASS', 'FAIL');

-- ---------------------------------------------------------------------
-- C3 sp_add_purchase - the same supplier invoice number twice is refused.
-- EXPECTED: ERROR 1062 (23000): Duplicate entry '4-INV-TEST-C1' for key 'purchase.uq_purchase_invoice'
-- ---------------------------------------------------------------------
CALL sp_add_purchase(4, 'INV-TEST-C1', CURDATE(),
     JSON_ARRAY(JSON_OBJECT('medicine_id', 1, 'batch_no', 'PCM-25A', 'quantity', 5, 'unit_cost', 23.00)), @pid_c3);
INSERT INTO test_results (test_id, description, result)
SELECT 'C3', 'duplicate invoice number refused, stock not doubled',
       IF((SELECT COUNT(*) FROM purchase) = @purchases_before
          AND (SELECT quantity_in_stock FROM batch WHERE batch_id = 3) = @stock3_before, 'PASS', 'FAIL');

-- ---------------------------------------------------------------------
-- C4 sp_add_purchase - an invoice without items is refused.
-- EXPECTED: ERROR 1644 (45000): A purchase needs at least one item (items must be a non-empty JSON array)
-- ---------------------------------------------------------------------
CALL sp_add_purchase(4, 'INV-TEST-C4', CURDATE(), JSON_ARRAY(), @pid_c4);
INSERT INTO test_results (test_id, description, result)
SELECT 'C4', 'purchase with an empty item list refused',
       IF(COUNT(*) = 0, 'PASS', 'FAIL') FROM purchase WHERE invoice_no = 'INV-TEST-C4';

-- ---------------------------------------------------------------------
-- C5 sp_make_sale - FEFO with a SPLIT across two batches.
-- Paracetamol (medicine 1). Batches: 1 = expired (14 units, must be skipped),
--   2 = expires first, 31 units;  3 = expires later, 170 units.
-- Customer 1 wants 40 units  ->  31 from batch 2 + 9 from batch 3.
-- EXPECTED: 2 bill lines, batch 2 empty, batch 3 reduced by 9, expired batch 1 untouched.
-- ---------------------------------------------------------------------
SET @stock3_before = (SELECT quantity_in_stock FROM batch WHERE batch_id = 3);
CALL sp_make_sale(1, 1, 40, 'UPI', @sale_c5);

INSERT INTO test_results (test_id, description, result)
SELECT 'C5', 'FEFO: 40 units = 31 from batch 2 (earliest expiry) + 9 from batch 3',
       IF(COUNT(*) = 2 AND SUM(batch_id = 2 AND quantity = 31) = 1 AND SUM(batch_id = 3 AND quantity = 9) = 1, 'PASS', 'FAIL')
FROM sale_item WHERE sale_id = @sale_c5;
INSERT INTO test_results (test_id, description, result)
SELECT 'C5b', 'stock after FEFO sale: batch 2 = 0, batch 3 = old - 9, expired batch 1 untouched (14)',
       IF((SELECT quantity_in_stock FROM batch WHERE batch_id = 2) = 0
          AND (SELECT quantity_in_stock FROM batch WHERE batch_id = 3) = @stock3_before - 9
          AND (SELECT quantity_in_stock FROM batch WHERE batch_id = 1) = 14, 'PASS', 'FAIL');
INSERT INTO test_results (test_id, description, result)
SELECT 'C5c', 'price snapshot: line 1 at 30.00, line 2 at 31.00, GST 5.00 copied from the medicine',
       IF(SUM(batch_id = 2 AND unit_price = 30.00 AND gst_percent = 5.00) = 1
          AND SUM(batch_id = 3 AND unit_price = 31.00 AND gst_percent = 5.00) = 1, 'PASS', 'FAIL')
FROM sale_item WHERE sale_id = @sale_c5;

-- ---------------------------------------------------------------------
-- C6 sp_make_sale - MORE than the sellable stock.
-- Azithromycin has 30 sellable units; we ask for 31.
-- EXPECTED: ERROR 1644 (45000): Insufficient stock for Azithromycin 250mg: requested 31, sellable 30
--           No bill is created.
-- ---------------------------------------------------------------------
SET @sales_before = (SELECT COUNT(*) FROM sale);
CALL sp_make_sale(NULL, 2, 31, 'CASH', @sale_c6);
INSERT INTO test_results (test_id, description, result)
SELECT 'C6', 'selling more than available was refused, no bill created, stock unchanged',
       IF((SELECT COUNT(*) FROM sale) = @sales_before AND @sale_c6 IS NULL
          AND (SELECT SUM(quantity_in_stock) FROM batch WHERE medicine_id = 2) = 30, 'PASS', 'FAIL');

-- ---------------------------------------------------------------------
-- C7 sp_make_sale - a medicine whose only stock is EXPIRED cannot be sold.
-- Vitamin B-Complex (medicine 13): 18 units, all in an expired batch.
-- EXPECTED: ERROR 1644 (45000): Insufficient stock for Vitamin B-Complex: requested 1, sellable 0
-- ---------------------------------------------------------------------
CALL sp_make_sale(NULL, 13, 1, 'CASH', @sale_c7);
INSERT INTO test_results (test_id, description, result)
SELECT 'C7', 'medicine with only expired stock cannot be sold',
       IF((SELECT COUNT(*) FROM sale) = @sales_before AND (SELECT quantity_in_stock FROM batch WHERE batch_id = 23) = 18, 'PASS', 'FAIL');

-- ---------------------------------------------------------------------
-- C8 sp_make_sale - bad inputs. Each CALL must fail with its own message:
--   unknown medicine : ERROR 1644 (45000): Medicine not found
--   bad payment mode : ERROR 1644 (45000): Payment mode must be CASH, UPI or CARD
--   unknown customer : ERROR 1644 (45000): Customer not found
--   quantity zero    : ERROR 1644 (45000): Quantity must be at least 1
-- ---------------------------------------------------------------------
CALL sp_make_sale(NULL, 999, 1, 'CASH', @sale_c8a);
CALL sp_make_sale(NULL, 4, 1, 'CHEQUE', @sale_c8b);
CALL sp_make_sale(999, 4, 1, 'CASH', @sale_c8c);
CALL sp_make_sale(NULL, 4, 0, 'CASH', @sale_c8d);
INSERT INTO test_results (test_id, description, result)
SELECT 'C8', 'four invalid sale requests were all refused, no bill created',
       IF((SELECT COUNT(*) FROM sale) = @sales_before, 'PASS', 'FAIL');

-- ---------------------------------------------------------------------
-- C9 sp_make_bill - a cart with 3 medicines on ONE bill (customer 3, CARD).
--   Cetirizine 10mg x3 (batch 8), Ibuprofen 400mg x2 (batch 17), Omeprazole 20mg x1 (batch 20)
-- EXPECTED: 3 lines, 6 units, total 3x22 + 2x30 + 1x54 = 180.00.
--           Then sp_generate_bill shows the printed bill (2 result sets).
-- ---------------------------------------------------------------------
CALL sp_make_bill(3, 'CARD',
     JSON_ARRAY(JSON_OBJECT('medicine_id', 4,  'quantity', 3),
                JSON_OBJECT('medicine_id', 9,  'quantity', 2),
                JSON_OBJECT('medicine_id', 11, 'quantity', 1)),
     @bill_c9);
INSERT INTO test_results (test_id, description, result)
SELECT 'C9', 'sp_make_bill: 1 bill, 3 lines, 6 units, total 180.00',
       IF(COUNT(*) = 3 AND SUM(quantity) = 6 AND SUM(line_total) = 180.00, 'PASS', 'FAIL')
FROM v_sale_bill WHERE sale_id = @bill_c9;
INSERT INTO test_results (test_id, description, result)
SELECT 'C9b', 'stock reduced: batch 8 = 20, batch 17 = 38, batch 20 = 37',
       IF((SELECT quantity_in_stock FROM batch WHERE batch_id = 8)  = 20
          AND (SELECT quantity_in_stock FROM batch WHERE batch_id = 17) = 38
          AND (SELECT quantity_in_stock FROM batch WHERE batch_id = 20) = 37, 'PASS', 'FAIL');
CALL sp_generate_bill(@bill_c9);

-- ---------------------------------------------------------------------
-- C10 sp_make_bill - the 2nd medicine of the cart fails, the 1st must be UNDONE.
-- Cart: Cetirizine x1 (fine) + Azithromycin x1000 (impossible).
-- EXPECTED: ERROR 1644 (45000): Insufficient stock for Azithromycin 250mg: requested 1000, sellable 30
--           Afterwards: no new bill and Cetirizine stock is back to what it was.
-- ---------------------------------------------------------------------
SET @sales_before = (SELECT COUNT(*) FROM sale);
SET @stock8_before = (SELECT quantity_in_stock FROM batch WHERE batch_id = 8);
CALL sp_make_bill(NULL, 'CASH',
     JSON_ARRAY(JSON_OBJECT('medicine_id', 4, 'quantity', 1),
                JSON_OBJECT('medicine_id', 2, 'quantity', 1000)),
     @bill_c10);
INSERT INTO test_results (test_id, description, result)
SELECT 'C10', 'cart failed on item 2: whole bill rolled back (no bill, Cetirizine stock unchanged)',
       IF((SELECT COUNT(*) FROM sale) = @sales_before
          AND (SELECT quantity_in_stock FROM batch WHERE batch_id = 8) = @stock8_before AND @bill_c10 IS NULL, 'PASS', 'FAIL');

-- ---------------------------------------------------------------------
-- C11 sp_make_bill - the same medicine twice in one cart is refused.
-- EXPECTED: ERROR 1644 (45000): A medicine appears more than once in the bill - add the quantities together
-- ---------------------------------------------------------------------
CALL sp_make_bill(NULL, 'CASH',
     JSON_ARRAY(JSON_OBJECT('medicine_id', 4, 'quantity', 1),
                JSON_OBJECT('medicine_id', 4, 'quantity', 2)),
     @bill_c11);
INSERT INTO test_results (test_id, description, result)
SELECT 'C11', 'duplicate medicine in the cart refused',
       IF((SELECT COUNT(*) FROM sale) = @sales_before, 'PASS', 'FAIL');

-- ---------------------------------------------------------------------
-- C12 sp_generate_bill - the bill of sale 1 (two result sets).
-- EXPECTED result set 1: 2 lines (Paracetamol 5 x 28.00, Cetirizine 2 x 22.00).
-- EXPECTED result set 2: item_lines 2, total_units 7, taxable_total 175.23, gst_total 8.77,
--                        cgst 4.39, sgst 4.38, grand_total 184.00
-- ---------------------------------------------------------------------
CALL sp_generate_bill(1);

-- C12b unknown bill.  EXPECTED: ERROR 1644 (45000): Bill not found
CALL sp_generate_bill(999999);

-- ---------------------------------------------------------------------
-- C13 sp_monthly_sales_report - current month. EXPECTED: three result sets
-- (summary, payment modes, top medicines). The query below calculates the summary
-- directly; total_bills and total_sales must be the same numbers as in result set 1.
-- ---------------------------------------------------------------------
CALL sp_monthly_sales_report(MONTH(CURDATE()), YEAR(CURDATE()));

SELECT COUNT(DISTINCT sale_id) AS total_bills_check, SUM(line_total) AS total_sales_check
FROM v_sale_bill
WHERE YEAR(sale_date) = YEAR(CURDATE()) AND MONTH(sale_date) = MONTH(CURDATE());

-- C13b invalid month.  EXPECTED: ERROR 1644 (45000): Month must be between 1 and 12
CALL sp_monthly_sales_report(13, 2026);

-- ---------------------------------------------------------------------
-- C14 sp_resolve_alert
--   first call  : the alert becomes RESOLVED with a time stamp
--   second call : ERROR 1644 (45000): Alert is already resolved
--   unknown id  : ERROR 1644 (45000): Alert not found
-- ---------------------------------------------------------------------
SET @alert_id = (SELECT MIN(alert_id) FROM stock_alert WHERE status = 'OPEN');
CALL sp_resolve_alert(@alert_id);
INSERT INTO test_results (test_id, description, result)
SELECT 'C14', 'sp_resolve_alert: alert is RESOLVED and resolved_at is filled',
       IF(status = 'RESOLVED' AND resolved_at IS NOT NULL, 'PASS', 'FAIL')
FROM stock_alert WHERE alert_id = @alert_id;
CALL sp_resolve_alert(@alert_id);
CALL sp_resolve_alert(999999);


-- #####################################################################
-- PART D - ALERT GENERATION AND THE EVENT
-- #####################################################################

-- ---------------------------------------------------------------------
-- D1 The event exists and the scheduler is switched on.
-- EXPECTED: event_scheduler = ON, event status ENABLED.
-- ---------------------------------------------------------------------
INSERT INTO test_results (test_id, description, result)
SELECT 'D1', 'event_scheduler is ON and evt_daily_stock_alerts is ENABLED',
       IF(@@GLOBAL.event_scheduler = 'ON'
          AND (SELECT COUNT(*) FROM information_schema.EVENTS
                WHERE event_schema = 'pharmacy_db' AND event_name = 'evt_daily_stock_alerts'
                  AND status = 'ENABLED') = 1, 'PASS', 'FAIL');

-- ---------------------------------------------------------------------
-- D2 NO DUPLICATES: running the alert procedures again adds nothing.
-- First run them once so that every missing alert exists, then count, then run them twice more.
-- ---------------------------------------------------------------------
CALL sp_generate_expiry_alerts();
CALL sp_generate_low_stock_alerts();
SET @open_before = (SELECT COUNT(*) FROM stock_alert WHERE status = 'OPEN');
CALL sp_generate_expiry_alerts();
CALL sp_generate_expiry_alerts();
CALL sp_generate_low_stock_alerts();
CALL sp_generate_low_stock_alerts();
INSERT INTO test_results (test_id, description, result)
SELECT 'D2', 'running the alert procedures repeatedly creates NO duplicate OPEN alerts',
       IF((SELECT COUNT(*) FROM stock_alert WHERE status = 'OPEN') = @open_before
          AND (SELECT COUNT(*) FROM (SELECT batch_id, alert_type FROM stock_alert
                                     WHERE status = 'OPEN' AND batch_id IS NOT NULL
                                     GROUP BY batch_id, alert_type HAVING COUNT(*) > 1) AS d) = 0, 'PASS', 'FAIL');

-- ---------------------------------------------------------------------
-- D3 A NEAR_EXPIRY alert is replaced by an EXPIRED alert when the batch expires.
-- We simulate "one day passes" by moving the expiry date of batch 8 to yesterday, inside a
-- transaction that we ROLL BACK afterwards.
-- ---------------------------------------------------------------------
START TRANSACTION;
UPDATE batch SET expiry_date = DATE_SUB(CURDATE(), INTERVAL 1 DAY) WHERE batch_id = 8;
CALL sp_generate_expiry_alerts();
INSERT INTO test_results (test_id, description, result)
SELECT 'D3', 'expired batch 8: 1 OPEN EXPIRED alert, NEAR_EXPIRY alert closed',
       IF((SELECT COUNT(*) FROM stock_alert WHERE batch_id = 8 AND alert_type = 'EXPIRED' AND status = 'OPEN') = 1
          AND (SELECT COUNT(*) FROM stock_alert WHERE batch_id = 8 AND alert_type = 'NEAR_EXPIRY' AND status = 'OPEN') = 0
          AND (SELECT COUNT(*) FROM stock_alert WHERE batch_id = 8 AND alert_type = 'NEAR_EXPIRY' AND status = 'RESOLVED') = 1,
          'PASS', 'FAIL');
ROLLBACK;

-- ---------------------------------------------------------------------
-- D4 The scheduler REALLY runs an event on its own.
-- 1. Resolve the OPEN LOW_STOCK alert of Doxycycline (medicine 12, it is still below its reorder level).
-- 2. Create a one-time event that runs 2 seconds from now and calls the low-stock procedure.
-- 3. Wait 6 seconds. The event must have created the alert again - without anybody calling it.
-- (If the scheduler is OFF this test FAILS. Fix: SET GLOBAL event_scheduler = ON;)
-- ---------------------------------------------------------------------
CALL sp_generate_low_stock_alerts();
SET @doxy_alert = (SELECT MIN(alert_id) FROM stock_alert
                    WHERE alert_type = 'LOW_STOCK' AND status = 'OPEN' AND medicine_id = 12);
CALL sp_resolve_alert(@doxy_alert);

DROP EVENT IF EXISTS evt_test_once;
CREATE EVENT evt_test_once
    ON SCHEDULE AT CURRENT_TIMESTAMP + INTERVAL 2 SECOND
    ON COMPLETION NOT PRESERVE
    DO CALL sp_generate_low_stock_alerts();

SELECT SLEEP(6) AS waiting_for_the_event;

INSERT INTO test_results (test_id, description, result)
SELECT 'D4', 'the event scheduler ran the event by itself and re-created the LOW_STOCK alert',
       IF(COUNT(*) = 1, 'PASS', 'FAIL') FROM stock_alert
WHERE alert_type = 'LOW_STOCK' AND status = 'OPEN' AND medicine_id = 12;


-- #####################################################################
-- PART E - CONSISTENCY (reconciliation) after all the tests above
-- #####################################################################

-- E1 STOCK RECONCILIATION: for every batch, stored stock must equal (units purchased - units sold).
-- This proves that the triggers kept quantity_in_stock correct through every test.
-- EXPECTED: 0 mismatching batches.
INSERT INTO test_results (test_id, description, result)
SELECT 'E1', 'stock reconciliation: stored stock = purchased - sold for EVERY batch',
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM batch AS b
WHERE b.quantity_in_stock <>
      COALESCE((SELECT SUM(pi.quantity) FROM purchase_item AS pi WHERE pi.batch_id = b.batch_id), 0)
    - COALESCE((SELECT SUM(si.quantity) FROM sale_item     AS si WHERE si.batch_id = b.batch_id), 0);

-- E2 No batch has negative stock.
INSERT INTO test_results (test_id, description, result)
SELECT 'E2', 'no batch has negative stock', IF(MIN(quantity_in_stock) >= 0, 'PASS', 'FAIL') FROM batch;

-- E3 The view agrees with the raw table: totals match.
INSERT INTO test_results (test_id, description, result)
SELECT 'E3', 'v_current_stock total equals SUM(batch.quantity_in_stock)',
       IF((SELECT SUM(total_quantity) FROM v_current_stock) = (SELECT SUM(quantity_in_stock) FROM batch), 'PASS', 'FAIL');

-- E4 Every purchase line adds stock to a batch of the SAME supplier as the invoice.
INSERT INTO test_results (test_id, description, result)
SELECT 'E4', 'every purchase line matches the supplier of its batch',
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM purchase_item AS pi
JOIN purchase AS p ON p.purchase_id = pi.purchase_id
JOIN batch    AS b ON b.batch_id    = pi.batch_id
WHERE p.supplier_id <> b.supplier_id;

-- E5 No sale line was ever created for an expired batch AFTER its expiry date.
INSERT INTO test_results (test_id, description, result)
SELECT 'E5', 'no sale line was sold after the batch expiry date',
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM sale_item AS si
JOIN sale  AS s ON s.sale_id  = si.sale_id
JOIN batch AS b ON b.batch_id = si.batch_id
WHERE DATE(s.sale_date) > b.expiry_date;


-- #####################################################################
-- FINAL SUMMARY
-- #####################################################################

-- Every check in order.
SELECT test_id, result, description FROM test_results ORDER BY seq;

-- The score.  EXPECTED: FAIL = 0.
SELECT result, COUNT(*) AS number_of_checks FROM test_results GROUP BY result ORDER BY result;
