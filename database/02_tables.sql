-- =====================================================================
-- FILE        : database/02_tables.sql
-- WHAT IT DOES: Creates all 10 tables of the pharmacy database with their
--               primary keys, foreign keys, CHECK/UNIQUE/NOT NULL/DEFAULT
--               rules and indexes.
-- DEPENDS ON  : 01_create_database.sql (the database must exist).
--               Design source: docs/er_diagram.md  (read that first).
-- USED BY     : 03_sample_data.sql (fills the tables), 04_views.sql,
--               05_triggers.sql, 06_procedures.sql, 07_events.sql
--               (all of them use the tables created here).
-- RUN ORDER   : 2nd
--
-- QUICK GLOSSARY (for the viva)
--   PRIMARY KEY : the column that uniquely identifies a row.
--   FOREIGN KEY : a column that must match a primary key in another table.
--   NOT NULL    : the column must always have a value.
--   UNIQUE      : no two rows may have the same value (NULLs are allowed).
--   CHECK       : a rule every row must satisfy (e.g. quantity >= 0).
--   DEFAULT     : the value used when the INSERT does not give one.
--   INDEX       : a sorted "lookup list" that makes searches faster.
--   InnoDB      : the MySQL storage engine that supports foreign keys
--                 and transactions (we need both).
-- =====================================================================

-- Work inside our project database.
USE pharmacy_db;

-- ---------------------------------------------------------------------
-- Drop old tables first (children before parents) so this file can be
-- run again without errors. A child table has a foreign key pointing to
-- a parent, so the child must be dropped first.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stock_alert;     -- child of medicine and batch
DROP TABLE IF EXISTS sale_item;       -- child of sale and batch
DROP TABLE IF EXISTS sale;            -- child of customer
DROP TABLE IF EXISTS customer;
DROP TABLE IF EXISTS purchase_item;   -- child of purchase and batch
DROP TABLE IF EXISTS purchase;        -- child of supplier
DROP TABLE IF EXISTS batch;           -- child of medicine and supplier
DROP TABLE IF EXISTS medicine;        -- child of category
DROP TABLE IF EXISTS category;
DROP TABLE IF EXISTS supplier;


-- =====================================================================
-- TABLE 1 : supplier
-- A company we buy medicines from.
-- =====================================================================
CREATE TABLE supplier (
    supplier_id     INT           NOT NULL AUTO_INCREMENT,  -- unique number, MySQL fills it automatically
    supplier_name   VARCHAR(100)  NOT NULL,                 -- company name, must be given
    contact_person  VARCHAR(100)  NULL,                     -- name of our contact there (optional)
    phone           VARCHAR(15)   NOT NULL,                 -- we must be able to call the supplier
    email           VARCHAR(100)  NULL,                     -- optional
    address         VARCHAR(255)  NULL,                     -- optional
    gst_no          CHAR(15)      NOT NULL,                 -- GSTIN is always exactly 15 characters

    -- The primary key: identifies one supplier.
    PRIMARY KEY (supplier_id),

    -- One GST number can belong to only one supplier.
    -- (UNIQUE automatically creates an index, so searching by GST number is fast too.)
    CONSTRAINT uq_supplier_gst_no UNIQUE (gst_no),

    -- A GSTIN must have exactly 15 characters (a shorter value is rejected).
    CONSTRAINT chk_supplier_gst_length CHECK (CHAR_LENGTH(gst_no) = 15)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- =====================================================================
-- TABLE 2 : category
-- The form of a medicine: Tablet, Syrup, Injection ...
-- =====================================================================
CREATE TABLE category (
    category_id    INT           NOT NULL AUTO_INCREMENT,   -- unique number
    category_name  VARCHAR(50)   NOT NULL,                  -- e.g. 'Tablet'
    description    VARCHAR(255)  NULL,                      -- optional explanation

    PRIMARY KEY (category_id),

    -- 'Tablet' may be stored only once.
    CONSTRAINT uq_category_name UNIQUE (category_name)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- =====================================================================
-- TABLE 3 : medicine
-- A product we sell. One row = one name from one manufacturer.
-- NOTE: stock is NOT stored here. Stock lives in the batch table.
-- =====================================================================
CREATE TABLE medicine (
    medicine_id            INT           NOT NULL AUTO_INCREMENT,  -- unique number
    medicine_name          VARCHAR(100)  NOT NULL,                 -- name with strength, e.g. 'Paracetamol 500mg'
    generic_name           VARCHAR(100)  NOT NULL,                 -- active ingredient (salt), e.g. 'Paracetamol'
    manufacturer           VARCHAR(100)  NOT NULL,                 -- company that makes it
    category_id            INT           NOT NULL,                 -- which category it belongs to (FK)
    reorder_level          INT           NOT NULL DEFAULT 10,      -- raise LOW_STOCK when total stock goes below this
    requires_prescription  BOOLEAN       NOT NULL DEFAULT FALSE,   -- TRUE = needs a doctor's prescription
    gst_percent            DECIMAL(5,2)  NOT NULL DEFAULT 5.00,    -- GST rate in percent (e.g. 5.00)

    PRIMARY KEY (medicine_id),

    -- FOREIGN KEY: every medicine must belong to an existing category.
    --   ON DELETE RESTRICT : you cannot delete a category while medicines still use it
    --                        (otherwise those medicines would lose their category).
    --   ON UPDATE CASCADE  : if a category_id value ever changed, medicines follow it automatically.
    CONSTRAINT fk_medicine_category FOREIGN KEY (category_id)
        REFERENCES category (category_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    -- The same product from the same manufacturer cannot be entered twice.
    -- This UNIQUE index also speeds up searching a medicine by name
    -- (a search on the first column, medicine_name, can use it).
    CONSTRAINT uq_medicine_name_maker UNIQUE (medicine_name, manufacturer),

    -- The reorder level cannot be negative.
    CONSTRAINT chk_medicine_reorder CHECK (reorder_level >= 0),

    -- GST in India is between 0% and 28%.
    CONSTRAINT chk_medicine_gst CHECK (gst_percent BETWEEN 0 AND 28),

    -- INDEX on generic_name: pharmacists often search "which medicines contain Paracetamol?".
    INDEX idx_medicine_generic (generic_name)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;
-- (MySQL also creates an index on category_id automatically because it is a foreign key.)


-- =====================================================================
-- TABLE 4 : batch   <-- stock is tracked HERE
-- One manufacturing lot of a medicine. Each batch has its own expiry date,
-- price and quantity, so stock must be counted per batch.
-- =====================================================================
CREATE TABLE batch (
    batch_id           INT            NOT NULL AUTO_INCREMENT,  -- unique number
    medicine_id        INT            NOT NULL,                 -- which medicine this lot is (FK)
    supplier_id        INT            NOT NULL,                 -- which supplier delivered it (FK)
    batch_no           VARCHAR(30)    NOT NULL,                 -- number printed on the strip/box
    manufacture_date   DATE           NOT NULL,                 -- when it was made
    expiry_date        DATE           NOT NULL,                 -- when it expires
    cost_price         DECIMAL(10,2)  NOT NULL,                 -- price we pay per unit
    selling_price      DECIMAL(10,2)  NOT NULL,                 -- MRP per unit, GST included
    quantity_in_stock  INT            NOT NULL DEFAULT 0,       -- units left on the shelf

    PRIMARY KEY (batch_id),

    -- FOREIGN KEY to medicine.
    --   RESTRICT : a medicine that has batches (stock history) cannot be deleted.
    --   CASCADE  : follow the medicine_id if it ever changes.
    CONSTRAINT fk_batch_medicine FOREIGN KEY (medicine_id)
        REFERENCES medicine (medicine_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    -- FOREIGN KEY to supplier. Same reasoning: purchase history must not lose its supplier.
    CONSTRAINT fk_batch_supplier FOREIGN KEY (supplier_id)
        REFERENCES supplier (supplier_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    -- The same lot from the same supplier is ONE row. A second delivery of
    -- that lot tops up this row instead of creating a duplicate.
    -- This unique index starts with medicine_id, so it also serves
    -- "find all batches of one medicine".
    CONSTRAINT uq_batch_lot UNIQUE (medicine_id, supplier_id, batch_no),

    -- Business rule: a medicine must expire AFTER it was made.
    CONSTRAINT chk_batch_dates CHECK (expiry_date > manufacture_date),

    -- Business rule: prices cannot be negative.
    CONSTRAINT chk_batch_cost CHECK (cost_price >= 0),

    -- Business rule: we never sell below our cost price.
    CONSTRAINT chk_batch_price CHECK (selling_price >= cost_price),

    -- Business rule: stock can never go below zero.
    CONSTRAINT chk_batch_qty CHECK (quantity_in_stock >= 0),

    -- INDEX 1 (medicine_id, expiry_date): used by FEFO selling
    -- ("give me the batches of THIS medicine, earliest expiry first").
    -- MySQL can read the batches already sorted by expiry date, with no extra sorting.
    INDEX idx_batch_medicine_expiry (medicine_id, expiry_date),

    -- INDEX 2 (expiry_date): used by the expiry views and the daily event
    -- ("which batches expire in the next 30 days / have already expired?").
    -- Those queries look at ALL medicines, so they need an index on expiry_date alone.
    INDEX idx_batch_expiry (expiry_date)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;
-- (MySQL also creates an index on supplier_id automatically because it is a foreign key.)


-- =====================================================================
-- TABLE 5 : purchase
-- The header of a purchase invoice from a supplier.
-- =====================================================================
CREATE TABLE purchase (
    purchase_id    INT          NOT NULL AUTO_INCREMENT,    -- unique number
    supplier_id    INT          NOT NULL,                   -- who we bought from (FK)
    invoice_no     VARCHAR(30)  NOT NULL,                   -- the supplier's own invoice number
    purchase_date  DATE         NOT NULL DEFAULT (CURDATE()), -- default = today

    PRIMARY KEY (purchase_id),

    -- FOREIGN KEY to supplier.
    --   RESTRICT : a supplier we have bought from cannot be deleted (accounting history).
    CONSTRAINT fk_purchase_supplier FOREIGN KEY (supplier_id)
        REFERENCES supplier (supplier_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    -- The same supplier invoice cannot be entered twice. This prevents
    -- counting the same delivery two times (which would double the stock).
    CONSTRAINT uq_purchase_invoice UNIQUE (supplier_id, invoice_no),

    -- INDEX on purchase_date: reports such as "purchases this month" filter by date.
    INDEX idx_purchase_date (purchase_date)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- =====================================================================
-- TABLE 6 : purchase_item
-- One line of a purchase invoice. It connects a purchase to a batch
-- (this resolves the many-to-many relationship purchase <-> batch).
-- =====================================================================
CREATE TABLE purchase_item (
    purchase_item_id  INT            NOT NULL AUTO_INCREMENT,  -- unique number
    purchase_id       INT            NOT NULL,                 -- which invoice (FK)
    batch_id          INT            NOT NULL,                 -- which batch was received (FK)
    quantity          INT            NOT NULL,                 -- how many units arrived
    unit_cost         DECIMAL(10,2)  NOT NULL,                 -- price per unit on THIS invoice (a snapshot)

    PRIMARY KEY (purchase_item_id),

    -- FOREIGN KEY to purchase.
    --   CASCADE on delete : an invoice line has no meaning without its invoice,
    --                       so deleting the invoice deletes its lines too.
    CONSTRAINT fk_pitem_purchase FOREIGN KEY (purchase_id)
        REFERENCES purchase (purchase_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    -- FOREIGN KEY to batch.
    --   RESTRICT : a batch that was purchased cannot be deleted.
    CONSTRAINT fk_pitem_batch FOREIGN KEY (batch_id)
        REFERENCES batch (batch_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    -- A batch can appear only once on one invoice.
    -- This index starts with purchase_id, so it also speeds up "show all lines of invoice X".
    CONSTRAINT uq_pitem_purchase_batch UNIQUE (purchase_id, batch_id),

    -- You must receive at least 1 unit; the price cannot be negative.
    CONSTRAINT chk_pitem_quantity CHECK (quantity > 0),
    CONSTRAINT chk_pitem_cost CHECK (unit_cost >= 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;
-- (MySQL also creates an index on batch_id automatically because it is a foreign key.)


-- =====================================================================
-- TABLE 7 : customer
-- A registered customer. Walk-in customers do not need a row here.
-- =====================================================================
CREATE TABLE customer (
    customer_id    INT           NOT NULL AUTO_INCREMENT,   -- unique number
    customer_name  VARCHAR(100)  NOT NULL,                  -- customer's name
    phone          VARCHAR(15)   NULL,                      -- optional; if given it must be unique
    address        VARCHAR(255)  NULL,                      -- optional

    PRIMARY KEY (customer_id),

    -- Two customers cannot share a phone number. MySQL allows many NULLs
    -- in a UNIQUE column, so customers without a phone are fine.
    -- This index also makes "find customer by phone" fast at the billing counter.
    CONSTRAINT uq_customer_phone UNIQUE (phone)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- =====================================================================
-- TABLE 8 : sale
-- The header of a bill (one row = one bill).
-- =====================================================================
CREATE TABLE sale (
    sale_id       INT                         NOT NULL AUTO_INCREMENT,       -- this is the bill number
    customer_id   INT                         NULL,                          -- NULL = walk-in customer
    sale_date     DATETIME                    NOT NULL DEFAULT CURRENT_TIMESTAMP, -- default = right now
    payment_mode  ENUM('CASH','UPI','CARD')   NOT NULL DEFAULT 'CASH',      -- only these 3 values are allowed

    PRIMARY KEY (sale_id),

    -- FOREIGN KEY to customer.
    --   SET NULL : if a customer record is deleted, the old bills must stay
    --              (they are accounting records). The bill simply becomes a
    --              walk-in bill. That is why customer_id above allows NULL.
    CONSTRAINT fk_sale_customer FOREIGN KEY (customer_id)
        REFERENCES customer (customer_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE,

    -- INDEX on sale_date: monthly sales reports and "sales in the last 7 days" filter by date.
    INDEX idx_sale_date (sale_date)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;
-- (MySQL also creates an index on customer_id automatically because it is a foreign key.)


-- =====================================================================
-- TABLE 9 : sale_item
-- One line of a bill. It connects a sale to the batch the units came from
-- (this resolves the many-to-many relationship sale <-> batch).
-- =====================================================================
CREATE TABLE sale_item (
    sale_item_id  INT            NOT NULL AUTO_INCREMENT,   -- unique number
    sale_id       INT            NOT NULL,                  -- which bill (FK)
    batch_id      INT            NOT NULL,                  -- which batch the units were taken from (FK)
    quantity      INT            NOT NULL,                  -- how many units were sold
    unit_price    DECIMAL(10,2)  NOT NULL,                  -- price per unit charged on THIS bill (a snapshot)
    gst_percent   DECIMAL(5,2)   NOT NULL,                  -- GST rate applied on THIS bill (a snapshot)

    PRIMARY KEY (sale_item_id),

    -- FOREIGN KEY to sale.
    --   CASCADE on delete : a bill line has no meaning without its bill.
    CONSTRAINT fk_sitem_sale FOREIGN KEY (sale_id)
        REFERENCES sale (sale_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    -- FOREIGN KEY to batch.
    --   RESTRICT : a batch that has been sold cannot be deleted (sales history).
    CONSTRAINT fk_sitem_batch FOREIGN KEY (batch_id)
        REFERENCES batch (batch_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    -- One bill has at most one line per batch.
    -- This index starts with sale_id, so it also speeds up "show all lines of bill X".
    CONSTRAINT uq_sitem_sale_batch UNIQUE (sale_id, batch_id),

    -- You must sell at least 1 unit; price and GST cannot be negative.
    CONSTRAINT chk_sitem_quantity CHECK (quantity > 0),
    CONSTRAINT chk_sitem_price CHECK (unit_price >= 0),
    CONSTRAINT chk_sitem_gst CHECK (gst_percent >= 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;
-- (MySQL also creates an index on batch_id automatically because it is a foreign key.
--  It speeds up "how many units of this batch were sold?" used by the top-selling report.)


-- =====================================================================
-- TABLE 10 : stock_alert
-- Warnings created automatically by triggers and by the daily event.
--   LOW_STOCK   -> about a MEDICINE (all its batches together) -> medicine_id is filled
--   NEAR_EXPIRY -> about a BATCH                                -> batch_id is filled
--   EXPIRED     -> about a BATCH                                -> batch_id is filled
-- =====================================================================
CREATE TABLE stock_alert (
    alert_id     INT                                          NOT NULL AUTO_INCREMENT,       -- unique number
    alert_type   ENUM('LOW_STOCK','NEAR_EXPIRY','EXPIRED')    NOT NULL,                      -- kind of warning
    medicine_id  INT                                          NULL,                          -- filled only for LOW_STOCK
    batch_id     INT                                          NULL,                          -- filled only for NEAR_EXPIRY / EXPIRED
    message      VARCHAR(255)                                 NOT NULL,                      -- readable text, a snapshot of the situation
    status       ENUM('OPEN','RESOLVED')                      NOT NULL DEFAULT 'OPEN',       -- new alerts start as OPEN
    created_at   DATETIME                                     NOT NULL DEFAULT CURRENT_TIMESTAMP, -- when it was raised
    resolved_at  DATETIME                                     NULL,                          -- filled when someone resolves it

    PRIMARY KEY (alert_id),

    -- FOREIGN KEY to medicine. RESTRICT/RESTRICT: alert history must never be
    -- silently deleted or rewritten when a medicine row changes.
    CONSTRAINT fk_alert_medicine FOREIGN KEY (medicine_id)
        REFERENCES medicine (medicine_id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    -- FOREIGN KEY to batch. Same reasoning.
    CONSTRAINT fk_alert_batch FOREIGN KEY (batch_id)
        REFERENCES batch (batch_id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    -- "Exclusive arc" rule: a LOW_STOCK alert points to a medicine ONLY,
    -- an expiry alert points to a batch ONLY. Never both, never neither.
    CONSTRAINT chk_alert_target CHECK (
        (alert_type = 'LOW_STOCK' AND medicine_id IS NOT NULL AND batch_id IS NULL)
        OR
        (alert_type <> 'LOW_STOCK' AND batch_id IS NOT NULL AND medicine_id IS NULL)
    ),

    -- Status and resolved_at must agree: an OPEN alert has no resolved time,
    -- a RESOLVED alert must have one.
    CONSTRAINT chk_alert_status CHECK (
        (status = 'OPEN' AND resolved_at IS NULL)
        OR
        (status = 'RESOLVED' AND resolved_at IS NOT NULL)
    ),

    -- INDEX on (status, alert_type): the dashboard asks "how many OPEN alerts of each type?"
    -- all the time. This index answers that without reading the whole table.
    INDEX idx_alert_status_type (status, alert_type)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;
-- (MySQL also creates indexes on medicine_id and batch_id automatically because they are
--  foreign keys. The triggers/event use them to check "is there already an OPEN alert for this?".)


-- Show the list of tables so you can see all 10 were created.
SHOW TABLES;
