-- =====================================================================
-- FILE        : database/05_triggers.sql
-- WHAT IT DOES: Creates 5 triggers that keep stock correct AUTOMATICALLY.
--               A TRIGGER is a small program stored in the database that
--               MySQL runs by itself when a row is inserted, updated or
--               deleted. Nobody calls it - the data change calls it.
--
--   trg_purchase_item_before_insert  : refuse a purchase line whose batch belongs to
--                                      a different supplier than the invoice
--   trg_purchase_item_after_insert   : buying stock  -> ADD quantity to the batch
--   trg_sale_item_before_insert      : selling       -> BLOCK expired / insufficient stock
--   trg_sale_item_after_insert       : selling       -> REDUCE the batch quantity
--   trg_batch_after_update_low_stock : stock reduced -> raise a LOW_STOCK alert if needed
--
-- DEPENDS ON  : 02_tables.sql (tables), 04_views.sql is NOT needed here.
-- USED BY     : every INSERT into purchase_item / sale_item (for example the
--               ones done inside 06_procedures.sql), 09_test_cases.sql.
-- RUN ORDER   : 5th
--
-- BEFORE vs AFTER  (viva question!)
--   BEFORE INSERT : runs BEFORE the row is written. Use it to VALIDATE and to
--                   reject bad data - if the trigger raises an error, the row
--                   is never stored.
--   AFTER  INSERT : runs AFTER the row has been stored successfully. Use it for
--                   SIDE EFFECTS on other tables (change stock, write an alert).
--
-- NEW and OLD
--   NEW.column_name = the value in the row being INSERTED, or the value an UPDATE is changing TO.
--   OLD.column_name = the value the row had BEFORE an UPDATE or DELETE.
--   (INSERT has only NEW, DELETE has only OLD, UPDATE has both.)
--
-- SIGNAL SQLSTATE '45000'
--   45000 means "an error defined by the programmer". SIGNAL raises that error
--   with our own MESSAGE_TEXT. The failing statement is cancelled and the
--   message travels up to the user (or to the Python backend). MESSAGE_TEXT
--   can be at most 128 characters and must be a literal or a variable, so we
--   build the text in a variable first and cut it with LEFT(text, 128).
--
-- DELIMITER
--   A trigger body contains many statements, each ending with ';'. The mysql
--   client would think the first ';' ends the whole CREATE TRIGGER. So we
--   temporarily change the client's end-of-statement mark to $$ and put it back.
-- =====================================================================

USE pharmacy_db;

-- Remove old versions so this file can be run again.
DROP TRIGGER IF EXISTS trg_purchase_item_before_insert;
DROP TRIGGER IF EXISTS trg_purchase_item_after_insert;
DROP TRIGGER IF EXISTS trg_sale_item_before_insert;
DROP TRIGGER IF EXISTS trg_sale_item_after_insert;
DROP TRIGGER IF EXISTS trg_batch_after_update_low_stock;

-- From here on, "$$" ends a statement (instead of ";").
DELIMITER $$

-- =====================================================================
-- TRIGGER 1 : trg_purchase_item_before_insert   (BEFORE INSERT on purchase_item)
-- RULE: a purchase invoice may only bring stock into batches of the SAME
--       supplier. A foreign key cannot compare two columns that live in
--       two different tables, so a trigger does this check.
-- =====================================================================
CREATE TRIGGER trg_purchase_item_before_insert
BEFORE INSERT ON purchase_item
FOR EACH ROW                                  -- run once for every row inserted
BEGIN
    -- Variable that will count "wrong supplier" matches.
    DECLARE v_mismatch INT DEFAULT 0;

    -- Count rows where the invoice's supplier is different from the batch's supplier.
    -- (If the invoice or batch does not exist the count is 0 and the foreign key rejects the row later.)
    SELECT COUNT(*)
      INTO v_mismatch
      FROM purchase AS p
      JOIN batch    AS b ON b.batch_id = NEW.batch_id
     WHERE p.purchase_id = NEW.purchase_id
       AND p.supplier_id <> b.supplier_id;

    -- If any mismatch exists, cancel the insert with a clear message.
    IF v_mismatch > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Supplier mismatch: this batch belongs to a different supplier than the purchase invoice';
    END IF;
END$$

-- =====================================================================
-- TRIGGER 2 : trg_purchase_item_after_insert   (AFTER INSERT on purchase_item)
-- RULE: when a purchase line is saved, the units arrive in the batch,
--       so batch.quantity_in_stock goes UP by NEW.quantity.
-- This is the ONE place where buying increases stock.
-- =====================================================================
CREATE TRIGGER trg_purchase_item_after_insert
AFTER INSERT ON purchase_item
FOR EACH ROW
BEGIN
    -- Add the purchased quantity to the stock of that batch.
    -- (The WHERE uses the primary key, so only one row changes - and MySQL Workbench "Safe Updates" is happy.)
    UPDATE batch
       SET quantity_in_stock = quantity_in_stock + NEW.quantity
     WHERE batch_id = NEW.batch_id;
END$$

-- =====================================================================
-- TRIGGER 3 : trg_sale_item_before_insert   (BEFORE INSERT on sale_item)
-- RULES: 1) an expired batch can never be sold
--        2) you cannot sell more units than the batch holds
-- If a rule is broken, the sale line is NOT stored and the whole
-- statement fails with our message.
-- =====================================================================
CREATE TRIGGER trg_sale_item_before_insert
BEFORE INSERT ON sale_item
FOR EACH ROW
BEGIN
    -- Variables to hold what we read from the batch.
    DECLARE v_stock    INT;
    DECLARE v_expiry   DATE;
    DECLARE v_batch_no VARCHAR(30);
    -- Variable for the error text we build.
    DECLARE v_message  VARCHAR(255);

    -- Read the batch that is being sold.
    -- FOR UPDATE locks the row until our transaction ends, so two cashiers
    -- cannot sell the last units of the same batch at the same moment.
    SELECT quantity_in_stock, expiry_date, batch_no
      INTO v_stock, v_expiry, v_batch_no
      FROM batch
     WHERE batch_id = NEW.batch_id
       FOR UPDATE;

    -- RULE 1: expired batch. (A batch is still sellable ON its expiry date.)
    IF v_expiry < CURDATE() THEN
        -- Build the text and cut it to 128 characters (the limit of MESSAGE_TEXT).
        -- MESSAGE_TEXT accepts only a literal or a variable, so we cut the text BEFORE the SIGNAL.
        SET v_message = LEFT(CONCAT('Cannot sell batch ', v_batch_no, ': it expired on ', v_expiry), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_message;
    END IF;

    -- RULE 2: not enough stock in this batch.
    IF NEW.quantity > v_stock THEN
        SET v_message = LEFT(CONCAT('Insufficient stock in batch ', v_batch_no,
                                    ': requested ', NEW.quantity, ', available ', v_stock), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_message;
    END IF;
END$$

-- =====================================================================
-- TRIGGER 4 : trg_sale_item_after_insert   (AFTER INSERT on sale_item)
-- RULE: when a sale line is saved, the units leave the shelf, so
--       batch.quantity_in_stock goes DOWN by NEW.quantity.
-- This is the ONE place where selling reduces stock.
-- (This UPDATE then fires trigger 5 below - triggers can chain.)
-- =====================================================================
CREATE TRIGGER trg_sale_item_after_insert
AFTER INSERT ON sale_item
FOR EACH ROW
BEGIN
    -- Subtract the sold quantity from the stock of that batch.
    UPDATE batch
       SET quantity_in_stock = quantity_in_stock - NEW.quantity
     WHERE batch_id = NEW.batch_id;
END$$

-- =====================================================================
-- TRIGGER 5 : trg_batch_after_update_low_stock   (AFTER UPDATE on batch)
-- RULE: whenever a batch's stock goes DOWN, check the SELLABLE stock of
--       its medicine (all non-expired batches added together). If it is
--       below the medicine's reorder level, create a LOW_STOCK alert -
--       but only if no OPEN LOW_STOCK alert exists for that medicine yet
--       (no duplicates). Resolving alerts is done by hand with sp_resolve_alert.
-- Here both OLD and NEW exist, because this is an UPDATE.
-- =====================================================================
CREATE TRIGGER trg_batch_after_update_low_stock
AFTER UPDATE ON batch
FOR EACH ROW
BEGIN
    -- Variables used in the checks.
    DECLARE v_sellable    INT;            -- sellable units of the medicine
    DECLARE v_reorder     INT;            -- its reorder level
    DECLARE v_name        VARCHAR(100);   -- its name (for the message)
    DECLARE v_open_alerts INT;            -- how many OPEN LOW_STOCK alerts it already has

    -- Only act when stock was REDUCED (OLD value is bigger than NEW value).
    IF NEW.quantity_in_stock < OLD.quantity_in_stock THEN

        -- Read the reorder level and name of the medicine this batch belongs to.
        SELECT reorder_level, medicine_name
          INTO v_reorder, v_name
          FROM medicine
         WHERE medicine_id = NEW.medicine_id;

        -- Add up the stock of all NON-EXPIRED batches of that medicine.
        SELECT COALESCE(SUM(quantity_in_stock), 0)
          INTO v_sellable
          FROM batch
         WHERE medicine_id = NEW.medicine_id
           AND expiry_date >= CURDATE();

        -- Is the sellable stock below the reorder level?
        IF v_sellable < v_reorder THEN

            -- Does an OPEN LOW_STOCK alert for this medicine already exist?
            SELECT COUNT(*)
              INTO v_open_alerts
              FROM stock_alert
             WHERE alert_type  = 'LOW_STOCK'
               AND status      = 'OPEN'
               AND medicine_id = NEW.medicine_id;

            -- Create the alert only if there is none (avoids duplicates).
            IF v_open_alerts = 0 THEN
                INSERT INTO stock_alert (alert_type, medicine_id, message)
                VALUES ('LOW_STOCK',
                        NEW.medicine_id,
                        LEFT(CONCAT('Sellable stock of ', v_name, ' is ', v_sellable,
                                    ', below reorder level ', v_reorder), 255));
            END IF;
        END IF;
    END IF;
END$$

-- Put the normal end-of-statement mark ";" back.
DELIMITER ;

-- Show the triggers that now exist.
SHOW TRIGGERS;
