-- =====================================================================
-- FILE        : database/06_procedures.sql
-- WHAT IT DOES: Creates the stored procedures = the BUSINESS LOGIC of the
--               pharmacy. A STORED PROCEDURE is a named program saved in the
--               database; you run it with  CALL procedure_name(arguments);
--
--   The 5 procedures from the brief
--     1. sp_add_purchase          add a purchase invoice with all its items/batches
--     2. sp_make_sale             sell ONE medicine, picking batches FEFO
--     3. sp_generate_bill         item-wise bill with GST and totals
--     4. sp_monthly_sales_report  sales summary for one month
--     5. sp_resolve_alert         mark an alert as RESOLVED
--
--   Helper procedures (they keep the five above short and avoid repeated code)
--     6. sp_add_medicine_to_sale     the FEFO engine used by 2 and 7
--     7. sp_make_bill                sell SEVERAL medicines on ONE bill (used by the web shopping cart)
--     8. sp_generate_expiry_alerts   create NEAR_EXPIRY / EXPIRED alerts (no duplicates)
--     9. sp_generate_low_stock_alerts  create LOW_STOCK alerts for every low medicine (no duplicates)
--
-- DEPENDS ON  : 02_tables.sql, 03_sample_data.sql (data), 04_views.sql
--               (v_sale_bill, v_low_stock) and 05_triggers.sql (the triggers
--               change stock when these procedures insert purchase/sale lines).
-- USED BY     : 07_events.sql (calls 8 and 9), 09_test_cases.sql,
--               backend/routes/purchases.py, sales.py, alerts.py, reports.py.
-- RUN ORDER   : 6th
--
-- WORDS YOU MUST BE ABLE TO EXPLAIN IN THE VIVA
--   DELIMITER      : see 05_triggers.sql - lets us write ';' inside a procedure body.
--   IN parameter   : a value that goes INTO the procedure (read only).
--   OUT parameter  : a value the procedure sends BACK to the caller (e.g. the new bill number).
--   TRANSACTION    : a group of changes that must ALL succeed or ALL be undone.
--                    START TRANSACTION ... COMMIT (save)  or  ROLLBACK (undo).
--                    This is the "A" (Atomicity) of ACID.
--   EXIT HANDLER   : "if any SQL error happens, run this block and then leave the
--                    procedure". We use it to ROLLBACK, then RESIGNAL (= pass the
--                    original error on, so the caller sees our clear message).
--   CURSOR         : lets a procedure walk through a query result ROW BY ROW:
--                    DECLARE -> OPEN -> FETCH (in a LOOP) -> CLOSE.
--                    A cursor ends with the NOT FOUND condition ("no more rows"),
--                    caught by a CONTINUE HANDLER that sets v_done = 1.
--   LOOP / LEAVE   : LOOP repeats forever until we LEAVE it.
--   JSON_TABLE     : turns a JSON array (sent by the web app) into rows we can read.
--
-- DECLARE ORDER inside a procedure (MySQL insists on this): variables -> cursors -> handlers.
-- =====================================================================

USE pharmacy_db;

DROP PROCEDURE IF EXISTS sp_add_purchase;
DROP PROCEDURE IF EXISTS sp_add_medicine_to_sale;
DROP PROCEDURE IF EXISTS sp_make_sale;
DROP PROCEDURE IF EXISTS sp_make_bill;
DROP PROCEDURE IF EXISTS sp_generate_bill;
DROP PROCEDURE IF EXISTS sp_monthly_sales_report;
DROP PROCEDURE IF EXISTS sp_resolve_alert;
DROP PROCEDURE IF EXISTS sp_generate_expiry_alerts;
DROP PROCEDURE IF EXISTS sp_generate_low_stock_alerts;

DELIMITER $$

-- =====================================================================
-- PROCEDURE 1 : sp_add_purchase
-- Records one purchase invoice and all of its items.
--
-- Parameters
--   p_supplier_id    IN  the supplier who sent the goods
--   p_invoice_no     IN  the supplier's invoice number
--   p_purchase_date  IN  invoice date (NULL = today)
--   p_items          IN  a JSON array, one object per item, for example:
--       [ {"medicine_id":1, "batch_no":"PCM-26A", "manufacture_date":"2026-08-01",
--          "expiry_date":"2028-07-31", "quantity":100, "unit_cost":22.00, "selling_price":31.00},
--         {"medicine_id":2, "batch_no":"AZI-24F", "quantity":10, "unit_cost":68.00} ]
--       * If the batch (medicine + this supplier + batch_no) is NEW, we create it,
--         and manufacture_date, expiry_date and selling_price are required.
--       * If the batch ALREADY exists, this is a top-up: only quantity and unit_cost are needed.
--   p_purchase_id    OUT the number of the new purchase invoice
--
-- What happens (all inside ONE transaction):
--   1. insert the purchase header
--   2. for every item: find or create the batch, insert the purchase_item
--      -> the trigger trg_purchase_item_after_insert then adds the quantity to the batch
--   3. COMMIT. If anything fails, ROLLBACK: no header, no batch, no stock change remains.
-- =====================================================================
CREATE PROCEDURE sp_add_purchase(
    IN  p_supplier_id    INT,
    IN  p_invoice_no     VARCHAR(30),
    IN  p_purchase_date  DATE,
    IN  p_items          JSON,
    OUT p_purchase_id    INT
)
BEGIN
    -- ---- variables ----
    DECLARE v_done        INT DEFAULT 0;      -- becomes 1 when the cursor has no more rows
    DECLARE v_medicine_id INT;                -- the columns of one item (filled by FETCH)
    DECLARE v_batch_no    VARCHAR(30);
    DECLARE v_mfd         DATE;
    DECLARE v_exp         DATE;
    DECLARE v_qty         INT;
    DECLARE v_cost        DECIMAL(10,2);
    DECLARE v_sell        DECIMAL(10,2);
    DECLARE v_batch_id    INT;                -- the batch we add stock to
    DECLARE v_message     VARCHAR(255);       -- text for error messages

    -- ---- cursor: walks through the JSON array, one item (row) at a time ----
    DECLARE cur_items CURSOR FOR
        SELECT jt.medicine_id, jt.batch_no, jt.manufacture_date, jt.expiry_date,
               jt.quantity, jt.unit_cost, jt.selling_price
          FROM JSON_TABLE(p_items, '$[*]' COLUMNS (
                   medicine_id      INT           PATH '$.medicine_id',
                   batch_no         VARCHAR(30)   PATH '$.batch_no',
                   manufacture_date DATE          PATH '$.manufacture_date',
                   expiry_date      DATE          PATH '$.expiry_date',
                   quantity         INT           PATH '$.quantity',
                   unit_cost        DECIMAL(10,2) PATH '$.unit_cost',
                   selling_price    DECIMAL(10,2) PATH '$.selling_price'
               )) AS jt;

    -- ---- handlers ----
    -- When FETCH has no more rows, MySQL raises NOT FOUND; we only set a flag and continue.
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    -- On ANY SQL error: undo everything, clear the OUT value, and re-raise the same error.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_purchase_id = NULL;
        RESIGNAL;
    END;

    -- ---- validation before we touch any table ----
    IF p_items IS NULL OR JSON_TYPE(p_items) <> 'ARRAY' OR JSON_LENGTH(p_items) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A purchase needs at least one item (items must be a non-empty JSON array)';
    END IF;

    -- ---- the transaction starts here ----
    START TRANSACTION;

    -- Step 1: the invoice header. COALESCE uses today's date when none was given.
    INSERT INTO purchase (supplier_id, invoice_no, purchase_date)
    VALUES (p_supplier_id, p_invoice_no, COALESCE(p_purchase_date, CURDATE()));

    -- LAST_INSERT_ID() = the AUTO_INCREMENT number just created. Save it NOW,
    -- because later inserts would change it.
    SET p_purchase_id = LAST_INSERT_ID();

    -- Step 2: process every item with the cursor.
    OPEN cur_items;
    item_loop: LOOP
        -- Read the next item into the variables.
        FETCH cur_items INTO v_medicine_id, v_batch_no, v_mfd, v_exp, v_qty, v_cost, v_sell;
        -- No more items? Leave the loop.
        IF v_done = 1 THEN
            LEAVE item_loop;
        END IF;

        -- Every item needs these four values.
        IF v_medicine_id IS NULL OR v_batch_no IS NULL OR v_qty IS NULL OR v_cost IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Every item needs medicine_id, batch_no, quantity and unit_cost';
        END IF;

        -- Does this exact lot (medicine + supplier + batch number) already exist?
        -- MAX() returns NULL when nothing matches and never raises NOT FOUND,
        -- so it cannot disturb the cursor's NOT FOUND handler.
        SELECT MAX(batch_id)
          INTO v_batch_id
          FROM batch
         WHERE medicine_id = v_medicine_id
           AND supplier_id = p_supplier_id
           AND batch_no    = v_batch_no;

        -- Not found -> create a new batch with quantity 0 (the trigger will add the stock).
        IF v_batch_id IS NULL THEN
            IF v_mfd IS NULL OR v_exp IS NULL OR v_sell IS NULL THEN
                -- MESSAGE_TEXT accepts only a literal or a variable (max 128 characters),
                -- so the text is built and cut in a variable first.
                SET v_message = LEFT(CONCAT('New batch ', v_batch_no,
                                            ' needs manufacture_date, expiry_date and selling_price'), 128);
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_message;
            END IF;

            INSERT INTO batch (medicine_id, supplier_id, batch_no, manufacture_date,
                               expiry_date, cost_price, selling_price, quantity_in_stock)
            VALUES (v_medicine_id, p_supplier_id, v_batch_no, v_mfd,
                    v_exp, v_cost, v_sell, 0);

            SET v_batch_id = LAST_INSERT_ID();
        END IF;

        -- Insert the purchase line. Trigger trg_purchase_item_before_insert checks the supplier,
        -- trigger trg_purchase_item_after_insert adds v_qty to the batch stock.
        INSERT INTO purchase_item (purchase_id, batch_id, quantity, unit_cost)
        VALUES (p_purchase_id, v_batch_id, v_qty, v_cost);
    END LOOP item_loop;
    CLOSE cur_items;

    -- Step 3: everything worked - make the changes permanent.
    COMMIT;
END$$


-- =====================================================================
-- PROCEDURE 6 (helper) : sp_add_medicine_to_sale        *** THIS IS THE FEFO ENGINE ***
-- Adds ONE medicine to an EXISTING bill by taking units from batches in
-- FEFO order = First Expired, First Out: the batch that expires EARLIEST
-- is sold first, so old stock does not go to waste.
--   * Expired batches are never used.
--   * If one batch does not hold enough units, the sale is SPLIT across
--     the next batches (one sale_item line per batch).
--
-- Example: Paracetamol, customer wants 40.
--   batch PCM-24B (expires first) has 31  -> line 1: 31 units
--   batch PCM-25A (expires later) has 150 -> line 2: 9 units
--
-- It does NOT start or commit a transaction itself. The caller
-- (sp_make_sale or sp_make_bill) owns the transaction, so that several
-- medicines can be sold on one bill all-or-nothing.
-- =====================================================================
CREATE PROCEDURE sp_add_medicine_to_sale(
    IN p_sale_id      INT,
    IN p_medicine_id  INT,
    IN p_quantity     INT
)
BEGIN
    -- ---- variables ----
    DECLARE v_done        INT DEFAULT 0;          -- cursor finished flag
    DECLARE v_remaining   INT;                    -- units still to be found
    DECLARE v_available   INT;                    -- total sellable units of the medicine
    DECLARE v_batch_id    INT;                    -- columns of the batch just fetched
    DECLARE v_batch_stock INT;
    DECLARE v_price       DECIMAL(10,2);
    DECLARE v_take        INT;                    -- units taken from this batch
    DECLARE v_name        VARCHAR(100);           -- medicine name and GST rate
    DECLARE v_gst         DECIMAL(5,2);
    DECLARE v_message     VARCHAR(255);

    -- ---- cursor: sellable batches of this medicine, earliest expiry first ----
    -- FOR UPDATE locks these rows until the transaction ends, so a second
    -- cashier cannot sell the same units at the same time.
    DECLARE cur_batches CURSOR FOR
        SELECT batch_id, quantity_in_stock, selling_price
          FROM batch
         WHERE medicine_id       = p_medicine_id
           AND quantity_in_stock > 0
           AND expiry_date      >= CURDATE()
         ORDER BY expiry_date ASC, batch_id ASC
           FOR UPDATE;

    -- ---- handler: end of cursor ----
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    -- ---- validation ----
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantity must be at least 1';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM medicine WHERE medicine_id = p_medicine_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Medicine not found';
    END IF;

    -- Read the name and GST rate once (they are copied into every sale line).
    SELECT medicine_name, gst_percent INTO v_name, v_gst
      FROM medicine
     WHERE medicine_id = p_medicine_id;

    -- Is there enough SELLABLE (non-expired) stock in total?
    SELECT COALESCE(SUM(quantity_in_stock), 0) INTO v_available
      FROM batch
     WHERE medicine_id = p_medicine_id
       AND expiry_date >= CURDATE();

    IF v_available < p_quantity THEN
        SET v_message = LEFT(CONCAT('Insufficient stock for ', v_name,
                                    ': requested ', p_quantity, ', sellable ', v_available), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_message;
    END IF;

    -- ---- the FEFO loop ----
    SET v_remaining = p_quantity;     -- at the start we still need all units
    SET v_done = 0;                   -- reset the cursor flag

    OPEN cur_batches;
    fefo_loop: LOOP
        FETCH cur_batches INTO v_batch_id, v_batch_stock, v_price;
        IF v_done = 1 THEN
            LEAVE fefo_loop;          -- no more batches
        END IF;

        -- Take whatever this batch can give, but never more than we still need.
        IF v_batch_stock < v_remaining THEN
            SET v_take = v_batch_stock;
        ELSE
            SET v_take = v_remaining;
        END IF;

        -- One bill line per batch. unit_price and gst_percent are the SNAPSHOT of today's values.
        -- The BEFORE trigger re-checks stock and expiry; the AFTER trigger reduces the batch stock.
        INSERT INTO sale_item (sale_id, batch_id, quantity, unit_price, gst_percent)
        VALUES (p_sale_id, v_batch_id, v_take, v_price, v_gst);

        SET v_remaining = v_remaining - v_take;

        -- Found everything? Stop early.
        IF v_remaining = 0 THEN
            LEAVE fefo_loop;
        END IF;
    END LOOP fefo_loop;
    CLOSE cur_batches;

    -- Safety net: should never happen because of the stock check above.
    IF v_remaining > 0 THEN
        SET v_message = LEFT(CONCAT('Could not allocate all units of ', v_name), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_message;
    END IF;
END$$


-- =====================================================================
-- PROCEDURE 2 : sp_make_sale
-- Creates a NEW bill containing ONE medicine (FEFO, split across batches if needed).
--
-- Parameters
--   p_customer_id   IN  customer number, or NULL for a walk-in customer
--   p_medicine_id   IN  the medicine to sell
--   p_quantity      IN  how many units
--   p_payment_mode  IN  'CASH', 'UPI' or 'CARD'
--   p_sale_id       OUT the new bill number
-- Everything is one transaction: if the stock is not enough, no bill is created.
-- =====================================================================
CREATE PROCEDURE sp_make_sale(
    IN  p_customer_id   INT,
    IN  p_medicine_id   INT,
    IN  p_quantity      INT,
    IN  p_payment_mode  VARCHAR(10),
    OUT p_sale_id       INT
)
BEGIN
    -- On any error: undo, clear the OUT value, pass the error on.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_sale_id = NULL;
        RESIGNAL;
    END;

    -- Validate the simple inputs first.
    IF p_payment_mode IS NULL OR p_payment_mode NOT IN ('CASH', 'UPI', 'CARD') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment mode must be CASH, UPI or CARD';
    END IF;

    IF p_customer_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM customer WHERE customer_id = p_customer_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Customer not found';
    END IF;

    START TRANSACTION;

    -- Create the bill header (sale_date uses its DEFAULT = now).
    INSERT INTO sale (customer_id, payment_mode)
    VALUES (p_customer_id, p_payment_mode);

    SET p_sale_id = LAST_INSERT_ID();      -- the new bill number

    -- Add the medicine to the bill using FEFO.
    CALL sp_add_medicine_to_sale(p_sale_id, p_medicine_id, p_quantity);

    COMMIT;
END$$


-- =====================================================================
-- PROCEDURE 7 (helper) : sp_make_bill
-- Like sp_make_sale, but for a whole SHOPPING CART: one bill with SEVERAL
-- medicines, all-or-nothing. The web page sends the cart as JSON:
--      [ {"medicine_id":1, "quantity":5}, {"medicine_id":4, "quantity":2} ]
-- Each medicine may appear only once in the cart (the page adds up repeats).
-- =====================================================================
CREATE PROCEDURE sp_make_bill(
    IN  p_customer_id   INT,
    IN  p_payment_mode  VARCHAR(10),
    IN  p_items         JSON,
    OUT p_sale_id       INT
)
BEGIN
    -- ---- variables ----
    DECLARE v_done        INT DEFAULT 0;
    DECLARE v_medicine_id INT;
    DECLARE v_quantity    INT;
    DECLARE v_duplicates  INT DEFAULT 0;

    -- ---- cursor over the cart items ----
    DECLARE cur_cart CURSOR FOR
        SELECT jt.medicine_id, jt.quantity
          FROM JSON_TABLE(p_items, '$[*]' COLUMNS (
                   medicine_id INT PATH '$.medicine_id',
                   quantity    INT PATH '$.quantity'
               )) AS jt;

    -- ---- handlers ----
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_sale_id = NULL;
        RESIGNAL;
    END;

    -- ---- validation ----
    IF p_payment_mode IS NULL OR p_payment_mode NOT IN ('CASH', 'UPI', 'CARD') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment mode must be CASH, UPI or CARD';
    END IF;

    IF p_items IS NULL OR JSON_TYPE(p_items) <> 'ARRAY' OR JSON_LENGTH(p_items) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The bill needs at least one item';
    END IF;

    IF p_customer_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM customer WHERE customer_id = p_customer_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Customer not found';
    END IF;

    -- A medicine listed twice would try to use the same batch twice on one bill.
    -- (number of rows) - (number of different medicines) = number of repeats.
    SELECT COUNT(*) - COUNT(DISTINCT jt.medicine_id)
      INTO v_duplicates
      FROM JSON_TABLE(p_items, '$[*]' COLUMNS (medicine_id INT PATH '$.medicine_id')) AS jt;

    IF v_duplicates > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A medicine appears more than once in the bill - add the quantities together';
    END IF;

    -- ---- the transaction ----
    START TRANSACTION;

    INSERT INTO sale (customer_id, payment_mode)
    VALUES (p_customer_id, p_payment_mode);

    SET p_sale_id = LAST_INSERT_ID();

    OPEN cur_cart;
    cart_loop: LOOP
        FETCH cur_cart INTO v_medicine_id, v_quantity;
        IF v_done = 1 THEN
            LEAVE cart_loop;
        END IF;

        -- FEFO for this medicine. If it fails, the error reaches our EXIT HANDLER:
        -- the WHOLE bill (all earlier medicines too) is rolled back.
        CALL sp_add_medicine_to_sale(p_sale_id, v_medicine_id, v_quantity);
    END LOOP cart_loop;
    CLOSE cur_cart;

    COMMIT;
END$$


-- =====================================================================
-- PROCEDURE 3 : sp_generate_bill
-- Returns TWO result sets for one bill:
--   result set 1 = the item lines (what to print in the table)
--   result set 2 = the totals: taxable value, GST (split into CGST + SGST),
--                  and the grand total
-- Usage:  CALL sp_generate_bill(5);
-- It only READS data, so it needs no transaction.
-- =====================================================================
CREATE PROCEDURE sp_generate_bill(
    IN p_sale_id INT
)
BEGIN
    -- The bill must exist.
    IF NOT EXISTS (SELECT 1 FROM sale WHERE sale_id = p_sale_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Bill not found';
    END IF;

    -- Result set 1: one row per item line (the view already calculates line_total, GST and taxable value).
    SELECT sale_id, sale_date, customer_name, customer_phone, payment_mode,
           medicine_name, batch_no, expiry_date,
           quantity, unit_price, gst_percent,
           line_total, gst_amount, taxable_value
      FROM v_sale_bill
     WHERE sale_id = p_sale_id
     ORDER BY sale_item_id;

    -- Result set 2: the totals of the bill.
    -- In India GST inside one state is split equally into CGST and SGST.
    -- sgst = total GST - cgst, so the two always add up exactly.
    SELECT sale_id,
           COUNT(*)                                   AS item_lines,
           SUM(quantity)                              AS total_units,
           SUM(taxable_value)                         AS taxable_total,
           SUM(gst_amount)                            AS gst_total,
           ROUND(SUM(gst_amount) / 2, 2)              AS cgst,
           SUM(gst_amount) - ROUND(SUM(gst_amount) / 2, 2) AS sgst,
           SUM(line_total)                            AS grand_total
      FROM v_sale_bill
     WHERE sale_id = p_sale_id
     GROUP BY sale_id;
END$$


-- =====================================================================
-- PROCEDURE 4 : sp_monthly_sales_report
-- Returns THREE result sets for one month:
--   1. summary          : bills, units, total sales, GST collected, average bill
--   2. by payment mode  : how much was paid by CASH / UPI / CARD
--   3. top 10 medicines : best sellers of that month
-- Usage:  CALL sp_monthly_sales_report(11, 2026);
-- =====================================================================
CREATE PROCEDURE sp_monthly_sales_report(
    IN p_month INT,
    IN p_year  INT
)
BEGIN
    DECLARE v_start DATE;     -- first day of the month
    DECLARE v_end   DATE;     -- first day of the NEXT month

    -- Validate the inputs.
    IF p_month IS NULL OR p_month < 1 OR p_month > 12 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Month must be between 1 and 12';
    END IF;
    IF p_year IS NULL OR p_year < 2000 OR p_year > 2100 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Year must be between 2000 and 2100';
    END IF;

    -- Build the first day of the month, e.g. year 2026, month 11 -> '2026-11-01'.
    -- LPAD(month, 2, '0') turns 5 into '05'.
    SET v_start = CAST(CONCAT(p_year, '-', LPAD(p_month, 2, '0'), '-01') AS DATE);
    SET v_end   = DATE_ADD(v_start, INTERVAL 1 MONTH);

    -- Result set 1: the summary. We use  >= start AND < end  so that every moment of the
    -- last day (23:59:59) is included, and an index on sale_date can be used.
    SELECT p_month                                   AS report_month,
           p_year                                    AS report_year,
           COUNT(DISTINCT sale_id)                   AS total_bills,
           COALESCE(SUM(quantity), 0)                AS total_units,
           COALESCE(SUM(line_total), 0)              AS total_sales,
           COALESCE(SUM(gst_amount), 0)              AS total_gst_collected,
           COALESCE(ROUND(SUM(line_total) / NULLIF(COUNT(DISTINCT sale_id), 0), 2), 0) AS average_bill_value
      FROM v_sale_bill
     WHERE sale_date >= v_start
       AND sale_date <  v_end;

    -- Result set 2: sales by payment mode.
    SELECT payment_mode,
           COUNT(DISTINCT sale_id) AS bills,
           SUM(line_total)         AS amount
      FROM v_sale_bill
     WHERE sale_date >= v_start
       AND sale_date <  v_end
     GROUP BY payment_mode
     ORDER BY amount DESC;

    -- Result set 3: the 10 best-selling medicines of the month.
    SELECT medicine_name,
           SUM(quantity)   AS units_sold,
           SUM(line_total) AS revenue
      FROM v_sale_bill
     WHERE sale_date >= v_start
       AND sale_date <  v_end
     GROUP BY medicine_name
     ORDER BY units_sold DESC, revenue DESC
     LIMIT 10;
END$$


-- =====================================================================
-- PROCEDURE 5 : sp_resolve_alert
-- Marks one OPEN alert as RESOLVED and records the time.
-- Fails with a clear message if the alert does not exist or is already resolved.
-- Usage:  CALL sp_resolve_alert(3);
-- =====================================================================
CREATE PROCEDURE sp_resolve_alert(
    IN p_alert_id INT
)
BEGIN
    DECLARE v_status VARCHAR(10);      -- current status of the alert

    -- Look up the alert. If it does not exist, v_status stays NULL.
    SELECT status INTO v_status
      FROM stock_alert
     WHERE alert_id = p_alert_id;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alert not found';
    ELSEIF v_status = 'RESOLVED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alert is already resolved';
    ELSE
        -- Both columns change together, which keeps CHECK chk_alert_status satisfied.
        UPDATE stock_alert
           SET status      = 'RESOLVED',
               resolved_at = NOW()
         WHERE alert_id = p_alert_id;

        -- Show the updated alert as confirmation.
        SELECT alert_id, alert_type, status, resolved_at
          FROM stock_alert
         WHERE alert_id = p_alert_id;
    END IF;
END$$


-- =====================================================================
-- PROCEDURE 8 (helper) : sp_generate_expiry_alerts
-- Creates alerts for batches that still have stock:
--   * NEAR_EXPIRY : expires within the next 30 days (today included)
--   * EXPIRED     : expiry date already passed
-- NO DUPLICATES: a batch gets a new alert only if it has no OPEN alert of that type.
-- When a batch becomes EXPIRED, its old OPEN NEAR_EXPIRY alert is closed
-- automatically (the EXPIRED alert replaces it).
-- Called every day by the event evt_daily_stock_alerts (07_events.sql).
-- Returns one row with the counts, handy when you run it by hand.
-- =====================================================================
CREATE PROCEDURE sp_generate_expiry_alerts()
BEGIN
    DECLARE v_near_added    INT DEFAULT 0;     -- how many NEAR_EXPIRY alerts we created
    DECLARE v_expired_added INT DEFAULT 0;     -- how many EXPIRED alerts we created
    DECLARE v_superseded    INT DEFAULT 0;     -- how many old NEAR_EXPIRY alerts we closed

    -- 1) NEAR_EXPIRY alerts.
    --    INSERT ... SELECT inserts one alert for every batch the SELECT returns.
    --    NOT EXISTS skips batches that already have an OPEN NEAR_EXPIRY alert.
    INSERT INTO stock_alert (alert_type, batch_id, message)
    SELECT 'NEAR_EXPIRY',
           b.batch_id,
           LEFT(CONCAT(m.medicine_name, ' batch ', b.batch_no, ' expires on ', b.expiry_date,
                       ' (', DATEDIFF(b.expiry_date, CURDATE()), ' days left, ',
                       b.quantity_in_stock, ' units in stock)'), 255)
      FROM batch    AS b
      JOIN medicine AS m ON m.medicine_id = b.medicine_id
     WHERE b.quantity_in_stock > 0
       AND b.expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY)
       AND NOT EXISTS (SELECT 1
                         FROM stock_alert AS a
                        WHERE a.batch_id   = b.batch_id
                          AND a.alert_type = 'NEAR_EXPIRY'
                          AND a.status     = 'OPEN');
    SET v_near_added = ROW_COUNT();            -- ROW_COUNT() = rows affected by the last statement

    -- 2) EXPIRED alerts (same idea).
    INSERT INTO stock_alert (alert_type, batch_id, message)
    SELECT 'EXPIRED',
           b.batch_id,
           LEFT(CONCAT(m.medicine_name, ' batch ', b.batch_no, ' expired on ', b.expiry_date,
                       ' (', DATEDIFF(CURDATE(), b.expiry_date), ' days ago, ',
                       b.quantity_in_stock, ' units still in stock)'), 255)
      FROM batch    AS b
      JOIN medicine AS m ON m.medicine_id = b.medicine_id
     WHERE b.quantity_in_stock > 0
       AND b.expiry_date < CURDATE()
       AND NOT EXISTS (SELECT 1
                         FROM stock_alert AS a
                        WHERE a.batch_id   = b.batch_id
                          AND a.alert_type = 'EXPIRED'
                          AND a.status     = 'OPEN');
    SET v_expired_added = ROW_COUNT();

    -- 3) Close NEAR_EXPIRY alerts of batches that have now expired.
    --    "alert_id > 0" is only there to satisfy MySQL Workbench's Safe Updates mode
    --    (it demands a key column in the WHERE of every UPDATE).
    UPDATE stock_alert
       SET status      = 'RESOLVED',
           resolved_at = NOW()
     WHERE alert_id > 0
       AND alert_type = 'NEAR_EXPIRY'
       AND status     = 'OPEN'
       AND batch_id IN (SELECT batch_id FROM batch WHERE expiry_date < CURDATE());
    SET v_superseded = ROW_COUNT();

    -- Report what happened.
    SELECT v_near_added    AS near_expiry_alerts_added,
           v_expired_added AS expired_alerts_added,
           v_superseded    AS near_expiry_alerts_closed;
END$$


-- =====================================================================
-- PROCEDURE 9 (helper) : sp_generate_low_stock_alerts
-- Creates a LOW_STOCK alert for EVERY medicine whose sellable stock is below
-- its reorder level (that is exactly what the view v_low_stock lists),
-- unless that medicine already has an OPEN LOW_STOCK alert.
-- The trigger trg_batch_after_update_low_stock reacts the moment a sale
-- lowers the stock; this procedure is the daily "safety sweep" that also
-- catches medicines that were already low before any sale happened.
-- =====================================================================
CREATE PROCEDURE sp_generate_low_stock_alerts()
BEGIN
    DECLARE v_added INT DEFAULT 0;

    INSERT INTO stock_alert (alert_type, medicine_id, message)
    SELECT 'LOW_STOCK',
           l.medicine_id,
           LEFT(CONCAT('Sellable stock of ', l.medicine_name, ' is ', l.sellable_quantity,
                       ', below reorder level ', l.reorder_level), 255)
      FROM v_low_stock AS l
     WHERE NOT EXISTS (SELECT 1
                         FROM stock_alert AS a
                        WHERE a.medicine_id = l.medicine_id
                          AND a.alert_type  = 'LOW_STOCK'
                          AND a.status      = 'OPEN');
    SET v_added = ROW_COUNT();

    SELECT v_added AS low_stock_alerts_added;
END$$

-- Put the normal end-of-statement mark ";" back.
DELIMITER ;

-- Show the procedures that now exist.
SHOW PROCEDURE STATUS WHERE Db = 'pharmacy_db';
