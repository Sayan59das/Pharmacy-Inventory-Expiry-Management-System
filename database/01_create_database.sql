-- =====================================================================
-- FILE        : database/01_create_database.sql
-- WHAT IT DOES: Creates the empty database called pharmacy_db.
--               Every other SQL file in this project works inside it.
-- DEPENDS ON  : Nothing. This is the FIRST file to run.
-- USED BY     : 02_tables.sql (and every file after it) - they all start
--               with "USE pharmacy_db;" which needs this database to exist.
-- RUN ORDER   : 1st  (01 -> 02 -> 03 -> 04 -> 05 -> 06 -> 07)
-- WARNING     : This file DELETES an existing pharmacy_db before creating
--               it again. That is on purpose: it lets you rebuild the whole
--               project from zero any time. Never run it on a database that
--               contains data you want to keep.
-- =====================================================================

-- Delete the database if it already exists, so we always start clean.
-- (IF EXISTS stops MySQL from showing an error on the very first run.)
DROP DATABASE IF EXISTS pharmacy_db;

-- Create the new, empty database.
-- utf8mb4 is the character set: it can store every language and symbol
-- (for example the rupee sign in names or addresses).
-- utf8mb4_0900_ai_ci is the collation (comparison rule): "ai" = accent
-- insensitive, "ci" = case insensitive, so 'tablet' and 'TABLET' are equal.
CREATE DATABASE pharmacy_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

-- Tell MySQL: "from now on, run every statement inside pharmacy_db".
USE pharmacy_db;

-- Show a small message so you can see the file worked.
SELECT 'pharmacy_db created successfully' AS result;
