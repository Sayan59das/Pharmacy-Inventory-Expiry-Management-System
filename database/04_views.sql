-- =====================================================================
-- FILE        : database/04_views.sql
-- WHAT IT DOES: Creates 13 views. A VIEW is a saved SELECT query with a
--               name. It stores NO data of its own - every time you
--               query the view, MySQL runs the saved SELECT on the real
--               tables, so the answer is always up to date.
--               Why views?  (1) Write a long join once, reuse it everywhere.
--                           (2) The backend can simply run
--                               "SELECT * FROM v_low_stock" - no SQL logic
--                               is needed in Python.
-- DEPENDS ON  : 02_tables.sql (tables) and 03_sample_data.sql (data to see).
-- USED BY     : 05_triggers.sql / 06_procedures.sql (some reuse these views),
--               08_demo_queries.sql, 09_test_cases.sql, backend/routes/*.py.
-- RUN ORDER   : 4th
--
-- THE VIEWS
--   1. v_current_stock               total / sellable / expired stock per medicine
--   2. v_expiring_soon               batches that expire within the next 30 days
--   3. v_expired_stock               batches that have already expired but still have stock
--   4. v_low_stock                   medicines whose sellable stock is below the reorder level
--   5. v_supplier_purchase_summary   how much we bought from each supplier
--   6. v_top_selling_medicines       medicines ranked by units sold
--   7. v_sale_bill                   every line of every bill, with GST (filter by sale_id)
--   8. v_open_alerts                 alerts that are still OPEN, with readable names
--   9. v_medicine_catalog            medicine details + stock + the price of the batch that sells next
--  10. v_batch_details               every batch with supplier, days left and an expiry status
--  11. v_purchase_list               one row per purchase invoice with its totals
--  12. v_sale_list                   one row per bill with its totals
--  13. v_dashboard_summary           ONE row with the numbers shown on the dashboard
--  (Views 9-13 exist so that the web app only has to run "SELECT * FROM view".)
--
-- TWO DEFINITIONS USED EVERYWHERE IN THIS PROJECT
--   EXPIRED  : expiry_date <  today      (a batch is still sellable ON its expiry date)
--   SELLABLE : expiry_date >= today      (stock that is allowed to be sold)
--   The low-stock rule counts only SELLABLE stock, because expired medicine
--   can never be sold, so it must not hide a shortage.
-- =====================================================================

USE pharmacy_db;

-- ---------------------------------------------------------------------
-- VIEW 1 : v_current_stock
-- One row per medicine with its stock added up over all its batches.
-- CREATE OR REPLACE VIEW = create it, or overwrite it if it already exists.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_current_stock AS
SELECT
    m.medicine_id,                                   -- the medicine
    m.medicine_name,
    c.category_name,
    m.reorder_level,                                 -- the alert threshold
    -- Total units in ALL batches (expired ones included).
    -- COALESCE turns NULL into 0 for a medicine that has no batch at all.
    COALESCE(SUM(b.quantity_in_stock), 0) AS total_quantity,
    -- Units that can still be sold: only batches that have NOT expired.
    -- CASE adds the quantity when the condition is true, otherwise adds 0.
    COALESCE(SUM(CASE WHEN b.expiry_date >= CURDATE() THEN b.quantity_in_stock ELSE 0 END), 0) AS sellable_quantity,
    -- Units sitting in expired batches (should be removed from the shelf).
    COALESCE(SUM(CASE WHEN b.expiry_date <  CURDATE() THEN b.quantity_in_stock ELSE 0 END), 0) AS expired_quantity
FROM medicine AS m
JOIN category AS c ON c.category_id = m.category_id          -- get the category name
LEFT JOIN batch AS b ON b.medicine_id = m.medicine_id        -- LEFT JOIN keeps medicines that have no batch yet
GROUP BY m.medicine_id, m.medicine_name, c.category_name, m.reorder_level;

-- ---------------------------------------------------------------------
-- VIEW 2 : v_expiring_soon
-- Batches that still have stock and expire within the next 30 days
-- (today is included). Earliest expiry first.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_expiring_soon AS
SELECT
    b.batch_id,
    m.medicine_id,
    m.medicine_name,
    b.batch_no,
    s.supplier_name,
    b.expiry_date,
    DATEDIFF(b.expiry_date, CURDATE()) AS days_left,                       -- days remaining before expiry
    b.quantity_in_stock,
    ROUND(b.quantity_in_stock * b.cost_price, 2) AS stock_value_at_cost    -- money at risk
FROM batch AS b
JOIN medicine AS m ON m.medicine_id = b.medicine_id
JOIN supplier AS s ON s.supplier_id = b.supplier_id
WHERE b.quantity_in_stock > 0                                              -- ignore empty batches
  AND b.expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY)
ORDER BY b.expiry_date;

-- ---------------------------------------------------------------------
-- VIEW 3 : v_expired_stock
-- Batches that have already expired but still have units on the shelf.
-- Most recently expired first.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_expired_stock AS
SELECT
    b.batch_id,
    m.medicine_id,
    m.medicine_name,
    b.batch_no,
    s.supplier_name,
    b.expiry_date,
    DATEDIFF(CURDATE(), b.expiry_date) AS days_since_expiry,               -- how long ago it expired
    b.quantity_in_stock,
    ROUND(b.quantity_in_stock * b.cost_price, 2) AS loss_value             -- money lost if thrown away
FROM batch AS b
JOIN medicine AS m ON m.medicine_id = b.medicine_id
JOIN supplier AS s ON s.supplier_id = b.supplier_id
WHERE b.quantity_in_stock > 0
  AND b.expiry_date < CURDATE()
ORDER BY b.expiry_date DESC;

-- ---------------------------------------------------------------------
-- VIEW 4 : v_low_stock
-- Medicines whose SELLABLE stock is below the reorder level.
-- Built on top of view 1 (a view can use another view).
-- A medicine whose batches are all expired shows sellable_quantity = 0.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_low_stock AS
SELECT
    medicine_id,
    medicine_name,
    category_name,
    reorder_level,
    sellable_quantity,
    expired_quantity,
    reorder_level - sellable_quantity AS shortfall                         -- how many units we are short
FROM v_current_stock
WHERE sellable_quantity < reorder_level
ORDER BY shortfall DESC;

-- ---------------------------------------------------------------------
-- VIEW 5 : v_supplier_purchase_summary
-- One row per supplier: number of invoices, units bought, money spent,
-- and the date of the last purchase.
-- LEFT JOINs keep a supplier even if we never bought anything from it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_supplier_purchase_summary AS
SELECT
    s.supplier_id,
    s.supplier_name,
    COUNT(DISTINCT p.purchase_id)                      AS number_of_purchases,  -- DISTINCT: an invoice with 3 lines must count once
    COALESCE(SUM(pi.quantity), 0)                      AS total_units_bought,
    COALESCE(SUM(pi.quantity * pi.unit_cost), 0)       AS total_amount_spent,   -- units x cost, added up
    MAX(p.purchase_date)                               AS last_purchase_date
FROM supplier AS s
LEFT JOIN purchase      AS p  ON p.supplier_id  = s.supplier_id
LEFT JOIN purchase_item AS pi ON pi.purchase_id = p.purchase_id
GROUP BY s.supplier_id, s.supplier_name
ORDER BY total_amount_spent DESC;

-- ---------------------------------------------------------------------
-- VIEW 6 : v_top_selling_medicines
-- Medicines ranked by the number of units sold (all time).
-- Path: sale_item -> batch -> medicine (a sale line only knows its batch).
-- Only medicines that have been sold at least once appear (INNER JOIN).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_top_selling_medicines AS
SELECT
    m.medicine_id,
    m.medicine_name,
    c.category_name,
    SUM(si.quantity)                      AS units_sold,
    COUNT(DISTINCT si.sale_id)            AS number_of_bills,      -- on how many different bills it appeared
    SUM(si.quantity * si.unit_price)      AS total_revenue         -- money earned (GST included)
FROM sale_item AS si
JOIN batch    AS b ON b.batch_id    = si.batch_id
JOIN medicine AS m ON m.medicine_id = b.medicine_id
JOIN category AS c ON c.category_id = m.category_id
GROUP BY m.medicine_id, m.medicine_name, c.category_name
ORDER BY units_sold DESC, total_revenue DESC;

-- ---------------------------------------------------------------------
-- VIEW 7 : v_sale_bill
-- Every line of every bill, ready to print. A view cannot take a
-- parameter, so it lists ALL bills; to see one bill just filter:
--       SELECT * FROM v_sale_bill WHERE sale_id = 5;
--
-- GST MATH (selling prices are MRP, which already INCLUDES GST in India):
--   line_total    = quantity x unit_price               (what the customer pays)
--   gst_amount    = line_total x gst% / (100 + gst%)    (the GST part hidden inside it)
--   taxable_value = line_total - gst_amount             (price before GST)
--   Example: 60.00 at 5% GST -> gst_amount = 60 x 5 / 105 = 2.86, taxable = 57.14.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_sale_bill AS
SELECT
    s.sale_id,                                                            -- bill number
    s.sale_date,
    COALESCE(c.customer_name, 'Walk-in Customer') AS customer_name,       -- NULL customer = walk-in
    c.phone                                       AS customer_phone,
    s.payment_mode,
    si.sale_item_id,
    m.medicine_name,
    b.batch_no,
    b.expiry_date,
    si.quantity,
    si.unit_price,
    si.gst_percent,
    ROUND(si.quantity * si.unit_price, 2) AS line_total,
    ROUND(si.quantity * si.unit_price * si.gst_percent / (100 + si.gst_percent), 2) AS gst_amount,
    ROUND(si.quantity * si.unit_price, 2)
      - ROUND(si.quantity * si.unit_price * si.gst_percent / (100 + si.gst_percent), 2) AS taxable_value
FROM sale AS s
JOIN sale_item AS si ON si.sale_id     = s.sale_id
JOIN batch     AS b  ON b.batch_id     = si.batch_id
JOIN medicine  AS m  ON m.medicine_id  = b.medicine_id
LEFT JOIN customer AS c ON c.customer_id = s.customer_id                  -- LEFT JOIN: walk-in bills have no customer row
ORDER BY s.sale_id, si.sale_item_id;

-- ---------------------------------------------------------------------
-- VIEW 8 : v_open_alerts
-- Alerts that are still OPEN, with readable names.
-- stock_alert points to a medicine (LOW_STOCK) OR to a batch (expiry
-- alerts), so we join both ways and use COALESCE to pick whichever exists.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_open_alerts AS
SELECT
    a.alert_id,
    a.alert_type,
    COALESCE(m_direct.medicine_name, m_via_batch.medicine_name) AS medicine_name,  -- name from whichever link is filled
    b.batch_no,                                                                    -- NULL for LOW_STOCK alerts
    b.expiry_date,                                                                 -- NULL for LOW_STOCK alerts
    a.message,
    a.created_at
FROM stock_alert AS a
LEFT JOIN medicine AS m_direct    ON m_direct.medicine_id    = a.medicine_id       -- path 1: LOW_STOCK alerts
LEFT JOIN batch    AS b           ON b.batch_id              = a.batch_id          -- path 2: expiry alerts, step 1
LEFT JOIN medicine AS m_via_batch ON m_via_batch.medicine_id = b.medicine_id       --         expiry alerts, step 2
WHERE a.status = 'OPEN'
ORDER BY a.created_at DESC, a.alert_id DESC;

-- ---------------------------------------------------------------------
-- VIEW 9 : v_medicine_catalog
-- Everything the web pages need to show a medicine list and to fill the
-- "medicine" drop-down of the billing page: details, stock numbers and
-- the price/expiry of the batch that will be sold NEXT (FEFO = the sellable
-- batch with the earliest expiry date).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_medicine_catalog AS
SELECT
    m.medicine_id,
    m.medicine_name,
    m.generic_name,
    m.manufacturer,
    m.category_id,
    cs.category_name,
    m.reorder_level,
    m.requires_prescription,
    m.gst_percent,
    cs.total_quantity,
    cs.sellable_quantity,
    cs.expired_quantity,
    -- Price of the next batch to be sold: sellable, has stock, earliest expiry first.
    -- A subquery in the SELECT list returns exactly one value per medicine.
    (SELECT b.selling_price
       FROM batch AS b
      WHERE b.medicine_id = m.medicine_id
        AND b.quantity_in_stock > 0
        AND b.expiry_date >= CURDATE()
      ORDER BY b.expiry_date, b.batch_id
      LIMIT 1) AS current_price,
    -- Earliest expiry date among the sellable batches that still have stock.
    (SELECT MIN(b.expiry_date)
       FROM batch AS b
      WHERE b.medicine_id = m.medicine_id
        AND b.quantity_in_stock > 0
        AND b.expiry_date >= CURDATE()) AS next_expiry_date
FROM medicine AS m
JOIN v_current_stock AS cs ON cs.medicine_id = m.medicine_id          -- reuse view 1 for the stock numbers
ORDER BY m.medicine_name;

-- ---------------------------------------------------------------------
-- VIEW 10 : v_batch_details
-- Every batch with the supplier name, the days left before expiry and a
-- ready-made expiry status (EXPIRED / NEAR_EXPIRY / OK).
-- Used by the "Batches" panel of the medicines page.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_batch_details AS
SELECT
    b.batch_id,
    b.medicine_id,
    m.medicine_name,
    b.batch_no,
    s.supplier_name,
    b.manufacture_date,
    b.expiry_date,
    DATEDIFF(b.expiry_date, CURDATE()) AS days_left,                 -- negative number = already expired
    b.cost_price,
    b.selling_price,
    b.quantity_in_stock,
    CASE
        WHEN b.expiry_date <  CURDATE()                             THEN 'EXPIRED'
        WHEN b.expiry_date <= DATE_ADD(CURDATE(), INTERVAL 30 DAY)  THEN 'NEAR_EXPIRY'
        ELSE 'OK'
    END AS expiry_status
FROM batch AS b
JOIN medicine AS m ON m.medicine_id = b.medicine_id
JOIN supplier AS s ON s.supplier_id = b.supplier_id
ORDER BY b.medicine_id, b.expiry_date;

-- ---------------------------------------------------------------------
-- VIEW 11 : v_purchase_list
-- One row per purchase invoice: supplier, number of lines, units, money.
-- Newest first.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_purchase_list AS
SELECT
    p.purchase_id,
    p.invoice_no,
    p.purchase_date,
    s.supplier_id,
    s.supplier_name,
    COUNT(pi.purchase_item_id)                   AS item_lines,
    COALESCE(SUM(pi.quantity), 0)                AS total_units,
    COALESCE(SUM(pi.quantity * pi.unit_cost), 0) AS total_amount
FROM purchase AS p
JOIN supplier AS s ON s.supplier_id = p.supplier_id
LEFT JOIN purchase_item AS pi ON pi.purchase_id = p.purchase_id
GROUP BY p.purchase_id, p.invoice_no, p.purchase_date, s.supplier_id, s.supplier_name
ORDER BY p.purchase_date DESC, p.purchase_id DESC;

-- ---------------------------------------------------------------------
-- VIEW 12 : v_sale_list
-- One row per bill: customer, payment mode, number of lines, units and the
-- grand total. Built on view 7 (v_sale_bill). Newest first.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_sale_list AS
SELECT
    sale_id,
    sale_date,
    customer_name,
    payment_mode,
    COUNT(*)         AS item_lines,
    SUM(quantity)    AS total_units,
    SUM(line_total)  AS grand_total
FROM v_sale_bill
GROUP BY sale_id, sale_date, customer_name, payment_mode
ORDER BY sale_date DESC, sale_id DESC;

-- ---------------------------------------------------------------------
-- VIEW 13 : v_dashboard_summary
-- ONE row with all the numbers of the dashboard cards.
-- Each number is a small subquery that counts the rows of another view.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_dashboard_summary AS
SELECT
    (SELECT COUNT(*) FROM medicine)         AS total_medicines,
    (SELECT COUNT(*) FROM v_low_stock)      AS low_stock_count,
    (SELECT COUNT(*) FROM v_expiring_soon)  AS near_expiry_count,
    (SELECT COUNT(*) FROM v_expired_stock)  AS expired_count,
    (SELECT COUNT(*) FROM v_open_alerts)    AS open_alerts,
    (SELECT COALESCE(SUM(line_total), 0) FROM v_sale_bill WHERE DATE(sale_date) = CURDATE()) AS todays_sales,
    (SELECT COUNT(DISTINCT sale_id) FROM v_sale_bill WHERE DATE(sale_date) = CURDATE())      AS todays_bills;

-- Show the names of the views that now exist.
SHOW FULL TABLES WHERE Table_type = 'VIEW';
