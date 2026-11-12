-- =====================================================================
-- FILE        : database/08_demo_queries.sql
-- WHAT IT DOES: 20 SELECT queries, from very simple to advanced, that show
--               every SQL concept expected in a DBMS course on OUR pharmacy
--               data. Each query has a comment saying WHAT IT SHOWS and
--               WHICH CONCEPT it uses. It only READS data (no changes).
-- DEPENDS ON  : the full database (run_all.sql). Q18 and Q19 also use views.
-- USED BY     : you - for practice and for the live demo in the viva.
-- RUN ORDER   : after run_all.sql. Select ONE query and run it (Workbench:
--               Ctrl+Enter runs the query where the cursor is).
--
-- CONCEPT MAP
--   Q1-Q3    SELECT, WHERE, LIKE, ORDER BY, LIMIT
--   Q4-Q6    aggregate functions, GROUP BY, HAVING
--   Q7-Q9    INNER JOIN on 3+ tables, LEFT JOIN
--   Q10-Q12  subqueries (scalar, IN, correlated)
--   Q13-Q14  EXISTS / NOT EXISTS
--   Q15-Q16  date functions: CURDATE, DATEDIFF, DATE_ADD, DATE_FORMAT
--   Q17      CASE
--   Q18      UNION
--   Q19-Q20  window functions: RANK, SUM() OVER
--
-- Row counts in the comments are for the original sample data.
-- =====================================================================

USE pharmacy_db;

-- =====================================================================
-- Q1. List all medicines alphabetically.
-- CONCEPT: SELECT specific columns + ORDER BY (default order is ascending).
-- EXPECTED: 25 rows.
-- =====================================================================
SELECT medicine_id, medicine_name, generic_name, manufacturer
FROM medicine
ORDER BY medicine_name;

-- =====================================================================
-- Q2. Prescription-only medicines whose name starts with the letter A.
-- CONCEPT: WHERE with two conditions joined by AND, and LIKE with the wildcard %
--          ('A%' = starts with A; '%cin%' would mean "contains cin").
-- EXPECTED: Amlodipine 5mg, Amoxicillin Clavulanate 625, Atorvastatin 10mg, Azithromycin 250mg.
-- =====================================================================
SELECT medicine_id, medicine_name, manufacturer
FROM medicine
WHERE requires_prescription = TRUE
  AND medicine_name LIKE 'A%'
ORDER BY medicine_name;

-- =====================================================================
-- Q3. The 5 batches with the highest selling price.
-- CONCEPT: JOIN to get the medicine name + ORDER BY ... DESC + LIMIT (keep only the first rows).
-- EXPECTED: 5 rows, Amoxicillin Clavulanate (218 and 215) at the top.
-- =====================================================================
SELECT m.medicine_name, b.batch_no, b.selling_price
FROM batch AS b
JOIN medicine AS m ON m.medicine_id = b.medicine_id
ORDER BY b.selling_price DESC
LIMIT 5;

-- =====================================================================
-- Q4. How many medicines are there in each category?
-- CONCEPT: aggregate function COUNT(*) with GROUP BY (one result row per group).
-- EXPECTED: 6 rows, Tablet = 10.
-- =====================================================================
SELECT c.category_name, COUNT(*) AS number_of_medicines
FROM medicine AS m
JOIN category AS c ON c.category_id = m.category_id
GROUP BY c.category_name
ORDER BY number_of_medicines DESC;

-- =====================================================================
-- Q5. Only the categories that have MORE THAN 3 medicines.
-- CONCEPT: HAVING filters GROUPS after aggregation. (WHERE filters single rows BEFORE grouping,
--          so it cannot use COUNT(*).)
-- EXPECTED: 2 rows - Tablet (10) and Syrup (5).
-- =====================================================================
SELECT c.category_name, COUNT(*) AS number_of_medicines
FROM medicine AS m
JOIN category AS c ON c.category_id = m.category_id
GROUP BY c.category_name
HAVING COUNT(*) > 3
ORDER BY number_of_medicines DESC;

-- =====================================================================
-- Q6. Price range and stock value of each category.
-- CONCEPT: several aggregates at once - MIN, AVG, MAX, SUM - with ROUND to tidy decimals.
--          stock value = quantity x cost price, added up over all batches.
-- EXPECTED: 6 rows.
-- =====================================================================
SELECT c.category_name,
       COUNT(b.batch_id)                                  AS batches,
       MIN(b.selling_price)                               AS cheapest,
       ROUND(AVG(b.selling_price), 2)                     AS average_price,
       MAX(b.selling_price)                               AS dearest,
       ROUND(SUM(b.quantity_in_stock * b.cost_price), 2)  AS stock_value_at_cost
FROM category AS c
JOIN medicine AS m ON m.category_id = c.category_id
JOIN batch    AS b ON b.medicine_id = m.medicine_id
GROUP BY c.category_name
ORDER BY stock_value_at_cost DESC;

-- =====================================================================
-- Q7. Full stock list: batch + medicine + category + supplier in ONE result.
-- CONCEPT: INNER JOIN across 4 tables. A batch only knows medicine_id and supplier_id;
--          the joins translate those numbers into names.
-- EXPECTED: 40 rows (shown: first 15).
-- =====================================================================
SELECT m.medicine_name, c.category_name, b.batch_no, s.supplier_name,
       b.expiry_date, b.quantity_in_stock
FROM batch AS b
JOIN medicine AS m ON m.medicine_id = b.medicine_id
JOIN category AS c ON c.category_id = m.category_id
JOIN supplier AS s ON s.supplier_id = b.supplier_id
ORDER BY m.medicine_name, b.expiry_date
LIMIT 15;

-- =====================================================================
-- Q8. How much has each registered customer spent in total?
-- CONCEPT: INNER JOIN across customer -> sale -> sale_item, SUM of (quantity x price) per customer.
--          Walk-in bills have no customer row, so INNER JOIN leaves them out.
-- EXPECTED: 8 rows (one per customer).
-- =====================================================================
SELECT c.customer_name,
       COUNT(DISTINCT s.sale_id)               AS bills,
       SUM(si.quantity)                        AS units_bought,
       SUM(si.quantity * si.unit_price)        AS total_spent
FROM customer  AS c
JOIN sale      AS s  ON s.customer_id = c.customer_id
JOIN sale_item AS si ON si.sale_id    = s.sale_id
GROUP BY c.customer_id, c.customer_name
ORDER BY total_spent DESC;

-- =====================================================================
-- Q9. Units sold in the LAST 30 DAYS for EVERY medicine - including medicines that sold nothing (0).
-- CONCEPT: LEFT JOIN keeps every row of the left table even when there is no match
--          (the missing side becomes NULL), COALESCE turns NULL into 0.
--          The inner query (a "derived table") first adds up the recent sales per medicine.
-- EXPECTED: 25 rows; medicines not sold recently show 0 and appear at the bottom.
-- =====================================================================
SELECT m.medicine_name,
       COALESCE(recent.units_sold, 0) AS units_sold_last_30_days
FROM medicine AS m
LEFT JOIN (
        SELECT b.medicine_id, SUM(si.quantity) AS units_sold
        FROM sale_item AS si
        JOIN sale  AS s ON s.sale_id  = si.sale_id
        JOIN batch AS b ON b.batch_id = si.batch_id
        WHERE s.sale_date >= DATE_SUB(NOW(), INTERVAL 30 DAY)
        GROUP BY b.medicine_id
     ) AS recent ON recent.medicine_id = m.medicine_id
ORDER BY units_sold_last_30_days DESC, m.medicine_name;

-- =====================================================================
-- Q10. Batches priced ABOVE the average selling price of all batches.
-- CONCEPT: scalar subquery - an inner SELECT that returns ONE value which the outer query compares with.
-- EXPECTED: 17 rows (all the expensive batches).
-- =====================================================================
SELECT m.medicine_name, b.batch_no, b.selling_price
FROM batch AS b
JOIN medicine AS m ON m.medicine_id = b.medicine_id
WHERE b.selling_price > (SELECT AVG(selling_price) FROM batch)
ORDER BY b.selling_price DESC;

-- =====================================================================
-- Q11. Medicines that the supplier "MedPlus Distributors" has supplied.
-- CONCEPT: subquery with IN - the inner query returns a LIST of medicine ids,
--          the outer query keeps the medicines whose id is in that list.
-- EXPECTED: 7 medicines.
-- =====================================================================
SELECT medicine_id, medicine_name
FROM medicine
WHERE medicine_id IN (SELECT b.medicine_id
                      FROM batch AS b
                      JOIN supplier AS s ON s.supplier_id = b.supplier_id
                      WHERE s.supplier_name = 'MedPlus Distributors')
ORDER BY medicine_name;

-- =====================================================================
-- Q12. Batches that hold MORE stock than the average batch of THE SAME medicine.
-- CONCEPT: CORRELATED subquery - the inner query uses a column of the outer row (b1.medicine_id),
--          so it is re-evaluated for every outer row: "average stock of the batches of THIS medicine".
-- EXPECTED: 14 rows (a medicine with only ONE batch can never be above its own average).
-- =====================================================================
SELECT m.medicine_name, b1.batch_no, b1.quantity_in_stock
FROM batch AS b1
JOIN medicine AS m ON m.medicine_id = b1.medicine_id
WHERE b1.quantity_in_stock > (SELECT AVG(b2.quantity_in_stock)
                              FROM batch AS b2
                              WHERE b2.medicine_id = b1.medicine_id)
ORDER BY m.medicine_name;

-- =====================================================================
-- Q13. Medicines that currently have EXPIRED stock on the shelf.
-- CONCEPT: EXISTS - true as soon as the inner query finds at least one row (it does not
--          care what the row contains, so we write SELECT 1).
-- EXPECTED: 4 medicines (Paracetamol 500mg, Amoxicillin Clavulanate 625, Vitamin B-Complex, Clotrimazole cream).
-- =====================================================================
SELECT m.medicine_id, m.medicine_name
FROM medicine AS m
WHERE EXISTS (SELECT 1
              FROM batch AS b
              WHERE b.medicine_id = m.medicine_id
                AND b.expiry_date < CURDATE()
                AND b.quantity_in_stock > 0)
ORDER BY m.medicine_name;

-- =====================================================================
-- Q14. Suppliers from whom we have NOT bought anything in the last 45 days.
-- CONCEPT: NOT EXISTS - the opposite of EXISTS: true when the inner query finds NO row.
-- EXPECTED: 3 suppliers (Sri Balaji, Gupta & Sons, Careway) with the original sample dates.
-- =====================================================================
SELECT s.supplier_id, s.supplier_name
FROM supplier AS s
WHERE NOT EXISTS (SELECT 1
                  FROM purchase AS p
                  WHERE p.supplier_id = s.supplier_id
                    AND p.purchase_date >= DATE_SUB(CURDATE(), INTERVAL 45 DAY))
ORDER BY s.supplier_name;

-- =====================================================================
-- Q15. Batches that expire in the next 60 days, with a countdown.
-- CONCEPT: date functions - CURDATE() (today), DATE_ADD() (add an interval),
--          DATEDIFF() (days between two dates), DATE_FORMAT() (display format).
-- EXPECTED: about 9 rows, soonest first.
-- =====================================================================
SELECT m.medicine_name,
       b.batch_no,
       DATE_FORMAT(b.expiry_date, '%d-%b-%Y')  AS expires_on,
       DATEDIFF(b.expiry_date, CURDATE())      AS days_left,
       b.quantity_in_stock
FROM batch AS b
JOIN medicine AS m ON m.medicine_id = b.medicine_id
WHERE b.expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 60 DAY)
  AND b.quantity_in_stock > 0
ORDER BY b.expiry_date;

-- =====================================================================
-- Q16. Sales per month: number of bills and revenue.
-- CONCEPT: DATE_FORMAT(date, '%Y-%m') turns a date into 'year-month', which we can GROUP BY.
-- EXPECTED: 4 rows (the last 90 days touch 4 calendar months, the oldest and the newest only partly).
-- =====================================================================
SELECT DATE_FORMAT(s.sale_date, '%Y-%m')   AS sales_month,
       COUNT(DISTINCT s.sale_id)           AS bills,
       SUM(si.quantity * si.unit_price)    AS revenue
FROM sale AS s
JOIN sale_item AS si ON si.sale_id = s.sale_id
GROUP BY DATE_FORMAT(s.sale_date, '%Y-%m')
ORDER BY sales_month;

-- =====================================================================
-- Q17. Label every medicine's stock situation in plain words.
-- CONCEPT: CASE ... WHEN ... THEN ... ELSE ... END - an if/else inside a query.
--          The conditions are checked from top to bottom; the first true one wins.
-- EXPECTED: 25 rows; OUT OF STOCK = 1 (Vitamin B-Complex), LOW = 4, WELL STOCKED = a few, the rest OK.
-- =====================================================================
SELECT medicine_name,
       sellable_quantity,
       reorder_level,
       CASE
           WHEN sellable_quantity = 0                  THEN 'OUT OF STOCK'
           WHEN sellable_quantity <  reorder_level     THEN 'LOW'
           WHEN sellable_quantity >= reorder_level * 2 THEN 'WELL STOCKED'
           ELSE 'OK'
       END AS stock_status
FROM v_current_stock
ORDER BY sellable_quantity - reorder_level;

-- =====================================================================
-- Q18. One combined "problem list": expired batches, near-expiry batches and low-stock medicines.
-- CONCEPT: UNION ALL stacks the results of several SELECTs on top of each other.
--          Every SELECT must return the same number of columns of compatible types.
--          (UNION removes duplicate rows, UNION ALL keeps everything and is faster.)
-- EXPECTED: 4 + 7 + 5 = 16 rows with the original sample data.
-- =====================================================================
SELECT 'EXPIRED' AS problem_type,
       CONCAT(medicine_name, ' (', batch_no, ')') AS item,
       CONCAT('expired ', days_since_expiry, ' days ago, ', quantity_in_stock, ' units') AS detail
FROM v_expired_stock
UNION ALL
SELECT 'NEAR_EXPIRY',
       CONCAT(medicine_name, ' (', batch_no, ')'),
       CONCAT(days_left, ' days left, ', quantity_in_stock, ' units')
FROM v_expiring_soon
UNION ALL
SELECT 'LOW_STOCK',
       medicine_name,
       CONCAT('sellable ', sellable_quantity, ' < reorder level ', reorder_level)
FROM v_low_stock;

-- =====================================================================
-- Q19. Rank the medicines by revenue INSIDE their category.
-- CONCEPT: window function RANK() OVER (PARTITION BY ... ORDER BY ...).
--          PARTITION BY restarts the ranking for every category; the rows are NOT collapsed
--          like in GROUP BY. Equal revenues get the same rank.
--          The inner query is a CTE (WITH ... AS) = a named temporary result.
-- EXPECTED: one row per sold medicine; rank 1 appears once per category.
-- =====================================================================
WITH revenue_per_medicine AS (
    SELECT m.medicine_name,
           c.category_name,
           SUM(si.quantity * si.unit_price) AS revenue
    FROM sale_item AS si
    JOIN batch    AS b ON b.batch_id    = si.batch_id
    JOIN medicine AS m ON m.medicine_id = b.medicine_id
    JOIN category AS c ON c.category_id = m.category_id
    GROUP BY m.medicine_id, m.medicine_name, c.category_name
)
SELECT category_name,
       medicine_name,
       revenue,
       RANK() OVER (PARTITION BY category_name ORDER BY revenue DESC) AS rank_in_category
FROM revenue_per_medicine
ORDER BY category_name, rank_in_category;

-- =====================================================================
-- Q20. Daily sales with a RUNNING TOTAL and the rank of the best days.
-- CONCEPT: SUM(...) OVER (ORDER BY day) adds up everything from the first day up to the
--          current row = a cumulative / running total. RANK() OVER (ORDER BY ... DESC) ranks the days.
-- EXPECTED: one row per day that had sales; the last row's running_total equals all sales ever made.
-- =====================================================================
SELECT sale_day,
       day_total,
       SUM(day_total) OVER (ORDER BY sale_day)  AS running_total,
       RANK() OVER (ORDER BY day_total DESC)    AS best_day_rank
FROM (
        SELECT DATE(s.sale_date) AS sale_day,
               SUM(si.quantity * si.unit_price) AS day_total
        FROM sale AS s
        JOIN sale_item AS si ON si.sale_id = s.sale_id
        GROUP BY DATE(s.sale_date)
     ) AS daily
ORDER BY sale_day;
