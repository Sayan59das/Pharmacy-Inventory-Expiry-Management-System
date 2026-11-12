-- =====================================================================
-- FILE        : database/run_all.sql
-- WHAT IT DOES: Builds the WHOLE database in one go by running files
--               01 to 07 in the correct order. Use it to create the project
--               from zero, or to RESET it to the original sample data.
-- DEPENDS ON  : the seven numbered files in this same folder.
-- USED BY     : you (once, during setup), and again whenever you want a clean start.
-- RUN ORDER   : this file replaces running 01..07 one by one.
--
-- HOW TO RUN IT  (SOURCE is a command of the mysql command-line client; MySQL
--                 Workbench's SQL editor does NOT understand it - in Workbench
--                 open and run the seven files one by one instead)
--
--   1. Open a terminal and go INTO the database folder (the paths below are relative):
--          cd pharmacy-inventory-system/database
--   2. Start the client and log in:
--          mysql -u root -p
--   3. At the  mysql>  prompt run:
--          SOURCE run_all.sql;
--      or in one line from the terminal:
--          mysql -u root -p < run_all.sql
--
-- WARNING: 01_create_database.sql deletes any existing pharmacy_db first.
--
-- Files 08_demo_queries.sql and 09_test_cases.sql are NOT part of the build:
-- you run them yourself afterwards, to explore the data and to test the system.
-- =====================================================================

-- IMPORTANT: write NO comment on the same line as a SOURCE command.
-- The mysql client reads everything after "SOURCE" up to the end of the
-- line as the file name, so a trailing comment would become part of the name.

-- 01: creates the empty database
SOURCE 01_create_database.sql;

-- 02: creates the 10 tables
SOURCE 02_tables.sql;

-- 03: fills the tables with sample data
SOURCE 03_sample_data.sql;

-- 04: creates the 13 views
SOURCE 04_views.sql;

-- 05: creates the 5 triggers
SOURCE 05_triggers.sql;

-- 06: creates the 9 stored procedures
SOURCE 06_procedures.sql;

-- 07: creates the daily event and creates the first alerts
SOURCE 07_events.sql;

SELECT 'run_all.sql finished: pharmacy_db is ready' AS result;
