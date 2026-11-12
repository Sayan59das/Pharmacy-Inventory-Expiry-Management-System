-- =====================================================================
-- FILE        : database/07_events.sql
-- WHAT IT DOES: Creates a scheduled EVENT that runs by itself every day and
--               creates the NEAR_EXPIRY, EXPIRED and LOW_STOCK alerts.
--               An EVENT is MySQL's built-in "cron job" / alarm clock: a
--               piece of SQL that the server runs at the times we choose.
-- DEPENDS ON  : 06_procedures.sql (the event calls sp_generate_expiry_alerts
--               and sp_generate_low_stock_alerts - they contain the
--               no-duplicate logic).
-- USED BY     : the web app (it shows the alerts the event creates),
--               09_test_cases.sql (tests the event).
-- RUN ORDER   : 7th (last file of the database)
--
-- WHY THE EVENT IS NEEDED
--   Triggers react to a data change. But a batch becomes "near expiry" simply
--   because TIME passes - no row is inserted or updated. Only a scheduled job
--   can notice that, so we need an event.
--
-- THE EVENT SCHEDULER MUST BE ON
--   MySQL ships with the scheduler possibly OFF. Turn it on with:
--         SET GLOBAL event_scheduler = ON;
--   (needs an administrator account such as root). This setting is forgotten
--   when the server restarts. To keep it forever either use
--         SET PERSIST event_scheduler = ON;
--   or add  event_scheduler=ON  under [mysqld] in my.ini.
--
-- HOW TO CHECK THAT IT IS RUNNING
--   1) SHOW VARIABLES LIKE 'event_scheduler';          -> Value must be ON
--   2) SHOW EVENTS FROM pharmacy_db;                   -> lists our event and its Status (ENABLED)
--   3) SHOW PROCESSLIST;                               -> contains a row with User = 'event_scheduler'
--   4) SELECT event_name, last_executed, status
--        FROM information_schema.EVENTS
--       WHERE event_schema = 'pharmacy_db';            -> last_executed fills in after the first run
-- =====================================================================

USE pharmacy_db;

-- Step 1: switch the event scheduler ON (the master switch for all events).
SET GLOBAL event_scheduler = ON;

-- Step 2: remove an older copy so this file can be run again.
DROP EVENT IF EXISTS evt_daily_stock_alerts;

-- Step 3: create the event.
DELIMITER $$

CREATE EVENT evt_daily_stock_alerts
    -- Run once every day ...
    ON SCHEDULE EVERY 1 DAY
    -- ... starting tomorrow at 01:00 a.m. (quiet time for a pharmacy).
    -- TIMESTAMP(CURDATE(), '01:00:00') is today 01:00; adding 1 DAY makes it tomorrow.
    STARTS TIMESTAMP(CURDATE(), '01:00:00') + INTERVAL 1 DAY
    -- Keep the event after it has run (otherwise a one-time event would be deleted).
    ON COMPLETION PRESERVE
    -- The event is active.
    ENABLE
    COMMENT 'Daily at 01:00 - create NEAR_EXPIRY, EXPIRED and LOW_STOCK alerts without duplicates'
DO
BEGIN
    -- Create NEAR_EXPIRY and EXPIRED alerts (and close NEAR_EXPIRY alerts that became EXPIRED).
    CALL sp_generate_expiry_alerts();
    -- Create LOW_STOCK alerts for every medicine below its reorder level.
    CALL sp_generate_low_stock_alerts();
END$$

DELIMITER ;

-- Step 4: the first scheduled run is tomorrow, so fill the alerts table NOW
-- by running the same two procedures once by hand.
-- Expected with the sample data: 7 NEAR_EXPIRY, 4 EXPIRED, 5 LOW_STOCK alerts.
CALL sp_generate_expiry_alerts();
CALL sp_generate_low_stock_alerts();

-- Step 5: prove that the scheduler is ON and the event exists.
SHOW VARIABLES LIKE 'event_scheduler';
SELECT event_name, status, interval_value, interval_field, starts, last_executed
  FROM information_schema.EVENTS
 WHERE event_schema = 'pharmacy_db';

-- Step 6: show the alerts that now exist, by type.
SELECT alert_type, status, COUNT(*) AS alerts
  FROM stock_alert
 GROUP BY alert_type, status
 ORDER BY alert_type;
