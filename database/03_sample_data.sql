-- =====================================================================
-- FILE        : database/03_sample_data.sql
-- WHAT IT DOES: Fills the tables with realistic Indian pharmacy data:
--                 8 suppliers, 6 categories, 25 medicines, 40 batches,
--                 15 purchases (41 purchase lines), 8 customers,
--                 30 sales (77 sale lines) spread over the last 90 days.
--               All dates are calculated from CURDATE() so the demo is
--               correct on ANY day you run it:
--                 * 4 batches are already EXPIRED
--                 * 7 batches expire within the next 30 days
--                 * 5 medicines have sellable stock BELOW their reorder level
-- DEPENDS ON  : 02_tables.sql (the tables must exist and be empty).
-- USED BY     : 04_views.sql (views read this data), 08_demo_queries.sql,
--               09_test_cases.sql, and the web app.
-- RUN ORDER   : 3rd.   (Triggers are created LATER, in 05_triggers.sql.)
--
-- IMPORTANT DESIGN NOTE - why stock is calculated with one UPDATE:
--   In the finished system, the triggers change batch.quantity_in_stock
--   automatically whenever a purchase_item or sale_item is inserted.
--   But triggers do not exist yet when this file runs, so nothing would
--   update the stock. Instead, at the end of this file ONE update sets
--       quantity_in_stock = (total purchased) - (total sold)
--   for every batch. This guarantees that the sample data is consistent.
--
-- ALL IDS ARE WRITTEN EXPLICITLY (supplier_id, medicine_id, batch_id ...)
--   so that later rows can refer to them safely. Normally you let
--   AUTO_INCREMENT choose the id; here we choose them ourselves.
-- =====================================================================

USE pharmacy_db;

-- ---------------------------------------------------------------------
-- 1. SUPPLIERS (8 rows)
--    Columns: supplier_id, supplier_name, contact_person, phone, email, address, gst_no
--    Every gst_no is exactly 15 characters (a CHECK constraint enforces it).
-- ---------------------------------------------------------------------
INSERT INTO supplier (supplier_id, supplier_name, contact_person, phone, email, address, gst_no) VALUES
(1, 'MedPlus Distributors',              'Rakesh Gupta',   '9822012345', 'orders@medplus.example.com',   'Plot 14, Bhosari MIDC, Pune, Maharashtra',        '27AABCM1234A1Z5'),
(2, 'HealthFirst Pharma',                'Anita Deshmukh', '9820098765', 'sales@healthfirst.example.com', '210 Andheri Industrial Estate, Mumbai',            '27AAECH5678B1Z2'),
(3, 'Sri Balaji Medical Agencies',       'K. Venkatesh',   '9849123456', 'info@sribalaji.example.com',   '5-9-12 Abids Road, Hyderabad, Telangana',          '36AAFCS4321C1Z8'),
(4, 'Apex Pharma Traders',               'Sunil Verma',    '9811234567', 'apex@apextraders.example.com', 'B-22 Lawrence Road, New Delhi',                    '07AAHCA9876D1Z3'),
(5, 'LifeLine Drug House',               'Meera Nair',     '9846001122', 'lifeline@lifeline.example.com','Market Road, Ernakulam, Kochi, Kerala',            '32AABCL2468E1Z6'),
(6, 'Gupta & Sons Wholesale Pharma',     'Amit Gupta',     '9830567890', 'gupta.sons@guptapharma.example.com', '17 Chitpur Road, Kolkata, West Bengal',       '19AAGFG1357F1Z9'),
(7, 'Careway Healthcare Distributors',   'Priya Iyer',     '9840223344', 'care@careway.example.com',     '88 Mount Road, Chennai, Tamil Nadu',               '33AAJCC8642G1Z1'),
(8, 'Sai Krupa Pharma Distributors',     'Nitin Patil',    '9823345566', 'saikrupa@saikrupa.example.com','Satpur MIDC, Nashik, Maharashtra',                 '27AAKCS9753H1Z4');

-- ---------------------------------------------------------------------
-- 2. CATEGORIES (6 rows)
-- ---------------------------------------------------------------------
INSERT INTO category (category_id, category_name, description) VALUES
(1, 'Tablet',    'Solid oral dose, swallowed with water'),
(2, 'Capsule',   'Medicine enclosed in a gelatin shell'),
(3, 'Syrup',     'Liquid medicine taken by mouth (syrups, suspensions, solutions)'),
(4, 'Injection', 'Sterile medicine given by injection (vials and ampoules)'),
(5, 'Ointment',  'Creams, gels and ointments applied on the skin'),
(6, 'Drops',     'Eye and ear drops');

-- ---------------------------------------------------------------------
-- 3. MEDICINES (25 rows)
--    Columns: medicine_id, medicine_name, generic_name, manufacturer,
--             category_id, reorder_level, requires_prescription, gst_percent
--    (GST rates here are only illustrative sample values.)
-- ---------------------------------------------------------------------
INSERT INTO medicine (medicine_id, medicine_name, generic_name, manufacturer, category_id, reorder_level, requires_prescription, gst_percent) VALUES
-- ----- Tablets (category 1) -----
(1,  'Paracetamol 500mg',            'Paracetamol',                          'Cipla',              1, 100, FALSE,  5.00),
(2,  'Azithromycin 250mg',           'Azithromycin',                         'Zydus Lifesciences', 1,  40, TRUE,   5.00),
(3,  'Pantoprazole 40mg',            'Pantoprazole',                         'Sun Pharma',         1,  60, TRUE,   5.00),
(4,  'Cetirizine 10mg',              'Cetirizine',                           'Cipla',              1,  50, FALSE,  5.00),
(5,  'Metformin 500mg',              'Metformin',                            'USV',                1,  80, TRUE,   5.00),
(6,  'Amlodipine 5mg',               'Amlodipine',                           'Torrent Pharma',     1,  60, TRUE,   5.00),
(7,  'Atorvastatin 10mg',            'Atorvastatin',                         'Lupin',              1,  40, TRUE,   5.00),
(8,  'Amoxicillin Clavulanate 625',  'Amoxicillin + Clavulanic Acid',        'Alkem Laboratories', 1,  40, TRUE,   5.00),
(9,  'Ibuprofen 400mg',              'Ibuprofen',                            'Mankind Pharma',     1,  50, FALSE,  5.00),
(10, 'Vitamin C 500mg Chewable',     'Ascorbic Acid',                        'Abbott',             1,  30, FALSE, 18.00),
-- ----- Capsules (category 2) -----
(11, 'Omeprazole 20mg',              'Omeprazole',                           'Dr. Reddys',         2,  50, TRUE,   5.00),
(12, 'Doxycycline 100mg',            'Doxycycline',                          'Intas',              2,  30, TRUE,   5.00),
(13, 'Vitamin B-Complex',            'Vitamin B Complex',                    'Abbott',             2,  30, FALSE, 18.00),
-- ----- Syrups (category 3) -----
(14, 'Cetirizine Syrup 60ml',        'Cetirizine',                           'Alkem Laboratories', 3,  20, FALSE,  5.00),
(15, 'Cough Syrup 100ml',            'Dextromethorphan',                     'Glenmark',           3,  20, FALSE,  5.00),
(16, 'Paracetamol Suspension 60ml',  'Paracetamol',                          'Mankind Pharma',     3,  25, FALSE,  5.00),
(17, 'Antacid Gel 170ml',            'Aluminium Hydroxide + Magnesium Hydroxide', 'Pfizer',        3,  20, FALSE,  5.00),
(18, 'Lactulose Solution 100ml',     'Lactulose',                            'Abbott',             3,  15, TRUE,   5.00),
-- ----- Injections (category 4) -----
(19, 'Ceftriaxone 1g Injection',     'Ceftriaxone',                          'Lupin',              4,  30, TRUE,   5.00),
(20, 'Diclofenac 75mg Injection',    'Diclofenac',                           'Alkem Laboratories', 4,  20, TRUE,   5.00),
(21, 'Human Insulin 40IU Vial 10ml', 'Human Insulin',                        'Wockhardt',          4,  15, TRUE,   5.00),
-- ----- Ointments (category 5) -----
(22, 'Povidone Iodine 5% Ointment',  'Povidone Iodine',                      'Win-Medicare',       5,  20, FALSE, 12.00),
(23, 'Diclofenac Gel 30g',           'Diclofenac',                           'Glenmark',           5,  20, FALSE,  5.00),
(24, 'Clotrimazole 1% Cream 15g',    'Clotrimazole',                         'Glenmark',           5,  20, FALSE,  5.00),
-- ----- Drops (category 6) -----
(25, 'Ciprofloxacin Eye Drops 5ml',  'Ciprofloxacin',                        'Cipla',              6,  15, TRUE,   5.00);

-- ---------------------------------------------------------------------
-- 4. BATCHES (40 rows)
--    Columns: batch_id, medicine_id, supplier_id, batch_no, manufacture_date,
--             expiry_date, cost_price, selling_price
--    quantity_in_stock is NOT written here: it starts at 0 (the DEFAULT) and is
--    calculated at the end of this file.
--
--    Dates are relative to today:
--      DATE_SUB(CURDATE(), INTERVAL 25 DAY) = 25 days ago
--      DATE_ADD(CURDATE(), INTERVAL 18 DAY) = 18 days from today
--
--    Status legend used in the comments:
--      EXPIRED   = expiry date already passed
--      NEAR      = expires within the next 30 days
--      (no tag)  = healthy, expires later than 30 days from now
-- ---------------------------------------------------------------------
INSERT INTO batch (batch_id, medicine_id, supplier_id, batch_no, manufacture_date, expiry_date, cost_price, selling_price) VALUES
-- Paracetamol 500mg (medicine 1) - three batches: good for showing FEFO (earliest expiry sells first)
(1,  1,  1, 'PCM-23K',  DATE_SUB(CURDATE(), INTERVAL 760 DAY), DATE_SUB(CURDATE(), INTERVAL 25 DAY),  20.00,  28.00),  -- EXPIRED
(2,  1,  1, 'PCM-24B',  DATE_SUB(CURDATE(), INTERVAL 700 DAY), DATE_ADD(CURDATE(), INTERVAL 18 DAY),  21.00,  30.00),  -- NEAR
(3,  1,  4, 'PCM-25A',  DATE_SUB(CURDATE(), INTERVAL 200 DAY), DATE_ADD(CURDATE(), INTERVAL 520 DAY), 22.00,  31.00),
-- Azithromycin 250mg (medicine 2)
(4,  2,  2, 'AZI-24F',  DATE_SUB(CURDATE(), INTERVAL 640 DAY), DATE_ADD(CURDATE(), INTERVAL 95 DAY),  68.00,  92.00),
(5,  2,  2, 'AZI-25C',  DATE_SUB(CURDATE(), INTERVAL 150 DAY), DATE_ADD(CURDATE(), INTERVAL 575 DAY), 70.00,  95.00),
-- Pantoprazole 40mg (medicine 3)
(6,  3,  3, 'PAN-24D',  DATE_SUB(CURDATE(), INTERVAL 500 DAY), DATE_ADD(CURDATE(), INTERVAL 230 DAY), 75.00, 112.00),
(7,  3,  1, 'PAN-25D2', DATE_SUB(CURDATE(), INTERVAL 80 DAY),  DATE_ADD(CURDATE(), INTERVAL 650 DAY), 77.00, 114.00),
-- Cetirizine 10mg (medicine 4)
(8,  4,  1, 'CTZ-24A',  DATE_SUB(CURDATE(), INTERVAL 690 DAY), DATE_ADD(CURDATE(), INTERVAL 22 DAY),  14.00,  22.00),  -- NEAR
(9,  4,  5, 'CTZ-25B',  DATE_SUB(CURDATE(), INTERVAL 120 DAY), DATE_ADD(CURDATE(), INTERVAL 610 DAY), 15.00,  23.00),
-- Metformin 500mg (medicine 5)
(10, 5,  3, 'MET-24C',  DATE_SUB(CURDATE(), INTERVAL 400 DAY), DATE_ADD(CURDATE(), INTERVAL 330 DAY), 22.00,  34.00),
(11, 5,  8, 'MET-25D',  DATE_SUB(CURDATE(), INTERVAL 90 DAY),  DATE_ADD(CURDATE(), INTERVAL 640 DAY), 23.00,  35.00),
-- Amlodipine 5mg (medicine 6)
(12, 6,  2, 'AML-24G',  DATE_SUB(CURDATE(), INTERVAL 550 DAY), DATE_ADD(CURDATE(), INTERVAL 180 DAY), 28.00,  44.00),
-- Atorvastatin 10mg (medicine 7)
(13, 7,  4, 'ATV-24H',  DATE_SUB(CURDATE(), INTERVAL 720 DAY), DATE_ADD(CURDATE(), INTERVAL 8 DAY),   55.00,  84.00),  -- NEAR
(14, 7,  7, 'ATV-25J',  DATE_SUB(CURDATE(), INTERVAL 100 DAY), DATE_ADD(CURDATE(), INTERVAL 630 DAY), 57.00,  88.00),
-- Amoxicillin Clavulanate 625 (medicine 8)
(15, 8,  3, 'AMX-24K',  DATE_SUB(CURDATE(), INTERVAL 742 DAY), DATE_SUB(CURDATE(), INTERVAL 12 DAY), 150.00, 215.00),  -- EXPIRED
(16, 8,  6, 'AMX-25M',  DATE_SUB(CURDATE(), INTERVAL 110 DAY), DATE_ADD(CURDATE(), INTERVAL 620 DAY),152.00, 218.00),
-- Ibuprofen 400mg (medicine 9)
(17, 9,  1, 'IBU-24L',  DATE_SUB(CURDATE(), INTERVAL 690 DAY), DATE_ADD(CURDATE(), INTERVAL 40 DAY),  19.00,  30.00),
(18, 9,  8, 'IBU-25N',  DATE_SUB(CURDATE(), INTERVAL 70 DAY),  DATE_ADD(CURDATE(), INTERVAL 660 DAY), 20.00,  32.00),
-- Vitamin C 500mg Chewable (medicine 10)
(19, 10, 7, 'VTC-25P',  DATE_SUB(CURDATE(), INTERVAL 130 DAY), DATE_ADD(CURDATE(), INTERVAL 600 DAY), 24.00,  40.00),
-- Omeprazole 20mg (medicine 11)
(20, 11, 2, 'OMP-24Q',  DATE_SUB(CURDATE(), INTERVAL 520 DAY), DATE_ADD(CURDATE(), INTERVAL 205 DAY), 33.00,  54.00),
(21, 11, 2, 'OMP-25R',  DATE_SUB(CURDATE(), INTERVAL 85 DAY),  DATE_ADD(CURDATE(), INTERVAL 645 DAY), 35.00,  55.00),
-- Doxycycline 100mg (medicine 12)
(22, 12, 4, 'DOX-24S',  DATE_SUB(CURDATE(), INTERVAL 715 DAY), DATE_ADD(CURDATE(), INTERVAL 15 DAY),  60.00,  92.00),  -- NEAR
-- Vitamin B-Complex (medicine 13)
(23, 13, 5, 'VBC-24T',  DATE_SUB(CURDATE(), INTERVAL 740 DAY), DATE_SUB(CURDATE(), INTERVAL 30 DAY),  22.00,  36.00),  -- EXPIRED
-- Cetirizine Syrup 60ml (medicine 14)
(24, 14, 1, 'CZS-24U',  DATE_SUB(CURDATE(), INTERVAL 600 DAY), DATE_ADD(CURDATE(), INTERVAL 120 DAY), 30.00,  48.00),
-- Cough Syrup 100ml (medicine 15)
(25, 15, 5, 'DXM-24V',  DATE_SUB(CURDATE(), INTERVAL 680 DAY), DATE_ADD(CURDATE(), INTERVAL 25 DAY),  62.00,  95.00),  -- NEAR
(26, 15, 5, 'DXM-25W',  DATE_SUB(CURDATE(), INTERVAL 60 DAY),  DATE_ADD(CURDATE(), INTERVAL 670 DAY), 64.00,  98.00),
-- Paracetamol Suspension 60ml (medicine 16)
(27, 16, 7, 'PCS-25X',  DATE_SUB(CURDATE(), INTERVAL 140 DAY), DATE_ADD(CURDATE(), INTERVAL 590 DAY), 25.00,  40.00),
-- Antacid Gel 170ml (medicine 17)
(28, 17, 3, 'ANT-24Y',  DATE_SUB(CURDATE(), INTERVAL 460 DAY), DATE_ADD(CURDATE(), INTERVAL 265 DAY), 72.00, 108.00),
-- Lactulose Solution 100ml (medicine 18)
(29, 18, 2, 'LAC-24Z',  DATE_SUB(CURDATE(), INTERVAL 560 DAY), DATE_ADD(CURDATE(), INTERVAL 170 DAY),120.00, 172.00),
-- Ceftriaxone 1g Injection (medicine 19)
(30, 19, 6, 'CEF-24A1', DATE_SUB(CURDATE(), INTERVAL 390 DAY), DATE_ADD(CURDATE(), INTERVAL 340 DAY), 40.00,  64.00),
(31, 19, 4, 'CEF-25A2', DATE_SUB(CURDATE(), INTERVAL 75 DAY),  DATE_ADD(CURDATE(), INTERVAL 655 DAY), 42.00,  66.00),
-- Diclofenac 75mg Injection (medicine 20)
(32, 20, 8, 'DIC-24B1', DATE_SUB(CURDATE(), INTERVAL 700 DAY), DATE_ADD(CURDATE(), INTERVAL 28 DAY),  12.00,  20.00),  -- NEAR
-- Human Insulin 40IU Vial (medicine 21)
(33, 21, 7, 'INS-25C1', DATE_SUB(CURDATE(), INTERVAL 90 DAY),  DATE_ADD(CURDATE(), INTERVAL 640 DAY),130.00, 160.00),
(34, 21, 7, 'INS-25C2', DATE_SUB(CURDATE(), INTERVAL 80 DAY),  DATE_ADD(CURDATE(), INTERVAL 650 DAY),132.00, 162.00),
-- Povidone Iodine 5% Ointment (medicine 22)
(35, 22, 3, 'PVI-24D1', DATE_SUB(CURDATE(), INTERVAL 650 DAY), DATE_ADD(CURDATE(), INTERVAL 60 DAY),  55.00,  85.00),
-- Diclofenac Gel 30g (medicine 23)
(36, 23, 1, 'DGL-25E1', DATE_SUB(CURDATE(), INTERVAL 110 DAY), DATE_ADD(CURDATE(), INTERVAL 620 DAY), 78.00, 120.00),
-- Clotrimazole 1% Cream 15g (medicine 24)
(37, 24, 8, 'CLO-24F1', DATE_SUB(CURDATE(), INTERVAL 640 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY),   44.00,  68.00),  -- EXPIRED
(38, 24, 1, 'CLO-25F2', DATE_SUB(CURDATE(), INTERVAL 95 DAY),  DATE_ADD(CURDATE(), INTERVAL 635 DAY), 46.00,  70.00),
-- Ciprofloxacin Eye Drops 5ml (medicine 25)
(39, 25, 5, 'CIP-24G1', DATE_SUB(CURDATE(), INTERVAL 715 DAY), DATE_ADD(CURDATE(), INTERVAL 12 DAY),  40.00,  64.00),  -- NEAR
(40, 25, 5, 'CIP-25G2', DATE_SUB(CURDATE(), INTERVAL 55 DAY),  DATE_ADD(CURDATE(), INTERVAL 675 DAY), 42.00,  66.00);

-- ---------------------------------------------------------------------
-- 5. PURCHASES (15 invoice headers, oldest first)
--    Columns: purchase_id, supplier_id, invoice_no, purchase_date
-- ---------------------------------------------------------------------
INSERT INTO purchase (purchase_id, supplier_id, invoice_no, purchase_date) VALUES
(1,  1, 'INV-MP-2204', DATE_SUB(CURDATE(), INTERVAL 150 DAY)),
(2,  2, 'INV-HF-0917', DATE_SUB(CURDATE(), INTERVAL 140 DAY)),
(3,  3, 'INV-SB-3381', DATE_SUB(CURDATE(), INTERVAL 130 DAY)),
(4,  4, 'INV-AP-0455', DATE_SUB(CURDATE(), INTERVAL 120 DAY)),
(5,  1, 'INV-MP-2251', DATE_SUB(CURDATE(), INTERVAL 105 DAY)),
(6,  5, 'INV-LL-1102', DATE_SUB(CURDATE(), INTERVAL 95 DAY)),
(7,  2, 'INV-HF-0951', DATE_SUB(CURDATE(), INTERVAL 80 DAY)),
(8,  6, 'INV-GS-7720', DATE_SUB(CURDATE(), INTERVAL 70 DAY)),
(9,  7, 'INV-CW-0338', DATE_SUB(CURDATE(), INTERVAL 60 DAY)),
(10, 3, 'INV-SB-3420', DATE_SUB(CURDATE(), INTERVAL 50 DAY)),
(11, 8, 'INV-SK-0219', DATE_SUB(CURDATE(), INTERVAL 40 DAY)),
(12, 1, 'INV-MP-2309', DATE_SUB(CURDATE(), INTERVAL 30 DAY)),
(13, 4, 'INV-AP-0501', DATE_SUB(CURDATE(), INTERVAL 22 DAY)),
(14, 5, 'INV-LL-1167', DATE_SUB(CURDATE(), INTERVAL 14 DAY)),
(15, 2, 'INV-HF-1008', DATE_SUB(CURDATE(), INTERVAL 7 DAY));

-- ---------------------------------------------------------------------
-- 6. PURCHASE ITEMS (41 invoice lines)
--    Columns: purchase_id, batch_id, quantity, unit_cost
--    RULE: the batch must belong to the SAME supplier as the purchase.
--          (A check query at the end of this file proves it.)
--    Purchase 13 contains a TOP-UP: batch 3 (Paracetamol PCM-25A) was
--    already delivered in purchase 4 and arrives again here at a slightly
--    different cost. Same batch row, two purchase lines.
-- ---------------------------------------------------------------------
INSERT INTO purchase_item (purchase_id, batch_id, quantity, unit_cost) VALUES
-- Purchase 1 (MedPlus Distributors)
(1,  1,  26, 20.00),
(1,  8,  30, 14.00),
-- Purchase 2 (HealthFirst Pharma)
(2,  4,  20, 68.00),
(2,  12, 40, 28.00),
(2,  20, 45, 33.00),
-- Purchase 3 (Sri Balaji Medical Agencies)
(3,  6,  60, 75.00),
(3,  10, 70, 22.00),
(3,  15, 20, 150.00),
-- Purchase 4 (Apex Pharma Traders)
(4,  3,  100, 22.00),
(4,  13, 24, 55.00),
(4,  22, 24, 60.00),
-- Purchase 5 (MedPlus Distributors)
(5,  2,  50, 21.00),
(5,  17, 45, 19.00),
(5,  24, 40, 30.00),
-- Purchase 6 (LifeLine Drug House)
(6,  9,  60, 15.00),
(6,  23, 20, 22.00),
(6,  25, 20, 62.00),
(6,  39, 10, 40.00),
-- Purchase 7 (HealthFirst Pharma)
(7,  5,  18, 70.00),
(7,  29, 20, 120.00),
-- Purchase 8 (Gupta & Sons)
(8,  16, 30, 152.00),
(8,  30, 30, 40.00),
-- Purchase 9 (Careway Healthcare)
(9,  14, 36, 57.00),
(9,  19, 50, 24.00),
(9,  27, 30, 25.00),
(9,  33, 12, 130.00),
(9,  34, 10, 132.00),
-- Purchase 10 (Sri Balaji Medical Agencies)
(10, 28, 25, 72.00),
(10, 35, 25, 55.00),
-- Purchase 11 (Sai Krupa Pharma)
(11, 11, 50, 23.00),
(11, 18, 40, 20.00),
(11, 32, 30, 12.00),
(11, 37, 15, 44.00),
-- Purchase 12 (MedPlus Distributors)
(12, 7,  40, 77.00),
(12, 36, 22, 78.00),
(12, 38, 28, 46.00),
-- Purchase 13 (Apex Pharma Traders) - includes the TOP-UP of batch 3
(13, 31, 40, 42.00),
(13, 3,  80, 23.00),
-- Purchase 14 (LifeLine Drug House)
(14, 26, 30, 64.00),
(14, 40, 12, 42.00),
-- Purchase 15 (HealthFirst Pharma)
(15, 21, 34, 35.00);

-- ---------------------------------------------------------------------
-- 7. CUSTOMERS (8 rows). Walk-in customers have no row here.
-- ---------------------------------------------------------------------
INSERT INTO customer (customer_id, customer_name, phone, address) VALUES
(1, 'Rahul Sharma',    '9876543210', '12 MG Road, Camp, Pune'),
(2, 'Priya Menon',     '9847012345', '7 Lane 5, Koregaon Park, Pune'),
(3, 'Amit Kulkarni',   '9822098220', 'Flat 302, Sai Heights, Kothrud, Pune'),
(4, 'Sneha Patil',     '9890123456', '21 Baner Road, Pune'),
(5, 'Mohammed Irfan',  '9701234567', '9 Salunke Vihar, Wanowrie, Pune'),
(6, 'Kavita Joshi',    '9765432109', 'B-14 Aundh, Pune'),
(7, 'Suresh Reddy',    '9885012345', '33 Hadapsar Industrial Estate, Pune'),
(8, 'Anjali Desai',    '9930011223', 'Wing C, Viman Nagar, Pune');

-- ---------------------------------------------------------------------
-- 8. SALES (30 bill headers, oldest first, over the last 88 days)
--    Columns: sale_id, customer_id, sale_date, payment_mode
--    customer_id NULL = walk-in customer.
--    TIMESTAMP(date, time) joins a date and a time of day into a DATETIME.
-- ---------------------------------------------------------------------
INSERT INTO sale (sale_id, customer_id, sale_date, payment_mode) VALUES
(1,  1,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 88 DAY), '10:15:00'), 'UPI'),
(2,  NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 85 DAY), '11:40:00'), 'CASH'),
(3,  2,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 82 DAY), '17:05:00'), 'CASH'),
(4,  3,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 79 DAY), '09:50:00'), 'UPI'),
(5,  NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 75 DAY), '13:25:00'), 'CARD'),
(6,  4,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 72 DAY), '18:10:00'), 'CASH'),
(7,  5,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 68 DAY), '10:30:00'), 'UPI'),
(8,  NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 64 DAY), '12:00:00'), 'CASH'),
(9,  1,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 60 DAY), '19:20:00'), 'UPI'),
(10, 6,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 56 DAY), '16:45:00'), 'CARD'),
(11, NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 52 DAY), '11:15:00'), 'CASH'),
(12, 7,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 48 DAY), '14:30:00'), 'UPI'),
(13, NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 44 DAY), '10:05:00'), 'CASH'),
(14, 2,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 38 DAY), '17:50:00'), 'UPI'),
(15, 8,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 36 DAY), '12:35:00'), 'CASH'),
(16, NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 32 DAY), '15:10:00'), 'CARD'),
(17, 3,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 28 DAY), '09:40:00'), 'UPI'),
(18, NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 26 DAY), '18:30:00'), 'CASH'),
(19, 5,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 21 DAY), '11:55:00'), 'UPI'),
(20, NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 20 DAY), '13:05:00'), 'CASH'),
(21, 6,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 17 DAY), '16:20:00'), 'CASH'),
(22, 4,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 13 DAY), '10:45:00'), 'CARD'),
(23, NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 12 DAY), '14:15:00'), 'UPI'),
(24, NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 10 DAY), '19:00:00'), 'CASH'),
(25, 7,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 8 DAY),  '12:20:00'), 'UPI'),
(26, NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 6 DAY),  '17:35:00'), 'CASH'),
(27, 1,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 4 DAY),  '10:10:00'), 'UPI'),
(28, NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 3 DAY),  '15:50:00'), 'CARD'),
(29, 8,    TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 2 DAY),  '11:30:00'), 'CASH'),
(30, NULL, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 0 DAY),  '09:30:00'), 'UPI');

-- ---------------------------------------------------------------------
-- 9. SALE ITEMS (77 bill lines)
--    A sale_item must store the price and GST that applied ON THAT BILL.
--    To avoid typing 77 prices by hand (and making typing mistakes), we do it in two steps:
--      Step A: put only (sale_id, batch_id, quantity) in a TEMPORARY table.
--              A temporary table lives only for this connection and vanishes afterwards.
--      Step B: copy those rows into sale_item, and let a JOIN fetch the
--              selling price from batch and the GST rate from medicine.
--    That "copy the price at the time of sale" is exactly the snapshot idea.
-- ---------------------------------------------------------------------

-- Step A: the temporary list of bill lines.
CREATE TEMPORARY TABLE tmp_sale_lines (
    sale_id   INT NOT NULL,   -- which bill
    batch_id  INT NOT NULL,   -- which batch the units came from
    quantity  INT NOT NULL    -- how many units
);

-- Every row below is: (sale_id, batch_id, quantity).
-- Each sale only uses batches that were already purchased and not yet expired on the sale date.
INSERT INTO tmp_sale_lines (sale_id, batch_id, quantity) VALUES
(1,  1, 5),  (1,  8, 2),
(2,  2, 4),
(3,  15, 1), (3,  6, 2), (3, 10, 3),
(4,  3, 6),  (4,  4, 1),
(5,  12, 3), (5, 17, 2),
(6,  23, 2), (6, 24, 1),
(7,  1, 4),  (7,  9, 2), (7, 25, 1),
(8,  2, 5),  (8, 13, 2),
(9,  22, 2), (9, 20, 3),
(10, 5, 2),  (10, 29, 1),
(11, 3, 8),  (11, 8, 3),
(12, 16, 1), (12, 14, 2), (12, 19, 2),
(13, 17, 3), (13, 24, 2),
(14, 37, 2), (14, 32, 4),
(15, 4, 2),  (15, 12, 2), (15, 20, 2),
(16, 28, 1), (16, 35, 1), (16, 27, 2),
(17, 10, 4), (17, 6, 3),  (17, 33, 1),
(18, 1, 3),  (18, 2, 3),
(19, 30, 2), (19, 31, 2),
(20, 25, 2), (20, 39, 1),
(21, 3, 10), (21, 38, 1), (21, 36, 1),
(22, 15, 1), (22, 13, 2), (22, 22, 3),
(23, 7, 3),  (23, 18, 4), (23, 26, 2),
(24, 2, 4),  (24, 8, 2),  (24, 9, 3),
(25, 14, 2), (25, 34, 1), (25, 5, 2),
(26, 21, 4), (26, 19, 2), (26, 40, 1),
(27, 3, 6),  (27, 4, 1),  (27, 11, 3),
(28, 12, 2), (28, 29, 1), (28, 16, 1),
(29, 2, 3),  (29, 9, 2),  (29, 24, 1), (29, 38, 2),
(30, 20, 2), (30, 7, 2),  (30, 35, 1), (30, 33, 1);

-- Step B: copy into the real table, fetching price and GST with JOINs.
--   b.selling_price comes from the batch table  -> becomes sale_item.unit_price
--   m.gst_percent   comes from the medicine table -> becomes sale_item.gst_percent
INSERT INTO sale_item (sale_id, batch_id, quantity, unit_price, gst_percent)
SELECT t.sale_id,
       t.batch_id,
       t.quantity,
       b.selling_price,
       m.gst_percent
FROM tmp_sale_lines AS t
JOIN batch    AS b ON b.batch_id    = t.batch_id
JOIN medicine AS m ON m.medicine_id = b.medicine_id
ORDER BY t.sale_id, t.batch_id;

-- The temporary table has done its job - remove it.
DROP TEMPORARY TABLE tmp_sale_lines;

-- ---------------------------------------------------------------------
-- 10. OPENING STOCK  (see the design note at the top of this file)
--     For every batch:  quantity_in_stock = total purchased - total sold.
--     COALESCE(x, 0) turns "no rows found" (NULL) into 0.
--     "WHERE batch_id > 0" is only there because MySQL Workbench's
--     Safe Updates mode refuses an UPDATE that has no WHERE on a key column.
-- ---------------------------------------------------------------------
UPDATE batch
SET quantity_in_stock =
      COALESCE((SELECT SUM(pi.quantity) FROM purchase_item AS pi WHERE pi.batch_id = batch.batch_id), 0)
    - COALESCE((SELECT SUM(si.quantity) FROM sale_item     AS si WHERE si.batch_id = batch.batch_id), 0)
WHERE batch_id > 0;

-- =====================================================================
-- CHECKS - run these to see that the data loaded correctly
-- =====================================================================

-- Check 1: how many rows are in each table?
-- Expected: supplier 8, category 6, medicine 25, batch 40, purchase 15,
--           purchase_item 41, customer 8, sale 30, sale_item 77, stock_alert 0
SELECT 'supplier'      AS table_name, COUNT(*) AS row_count FROM supplier
UNION ALL SELECT 'category',      COUNT(*) FROM category
UNION ALL SELECT 'medicine',      COUNT(*) FROM medicine
UNION ALL SELECT 'batch',         COUNT(*) FROM batch
UNION ALL SELECT 'purchase',      COUNT(*) FROM purchase
UNION ALL SELECT 'purchase_item', COUNT(*) FROM purchase_item
UNION ALL SELECT 'customer',      COUNT(*) FROM customer
UNION ALL SELECT 'sale',          COUNT(*) FROM sale
UNION ALL SELECT 'sale_item',     COUNT(*) FROM sale_item
UNION ALL SELECT 'stock_alert',   COUNT(*) FROM stock_alert;

-- Check 2: does every purchase line add stock to a batch of the SAME supplier?
-- Expected: 0 rows (any row returned would be a data mistake).
SELECT pi.purchase_item_id, p.supplier_id AS purchase_supplier, b.supplier_id AS batch_supplier
FROM purchase_item AS pi
JOIN purchase AS p ON p.purchase_id = pi.purchase_id
JOIN batch    AS b ON b.batch_id    = pi.batch_id
WHERE p.supplier_id <> b.supplier_id;

-- Check 3: batches by expiry status.
-- Expected: EXPIRED 4, NEAR_EXPIRY (within 30 days) 7, OK 29.
SELECT CASE
           WHEN expiry_date < CURDATE()                              THEN 'EXPIRED'
           WHEN expiry_date <= DATE_ADD(CURDATE(), INTERVAL 30 DAY)  THEN 'NEAR_EXPIRY'
           ELSE 'OK'
       END AS expiry_status,
       COUNT(*) AS number_of_batches
FROM batch
GROUP BY expiry_status
ORDER BY number_of_batches;
