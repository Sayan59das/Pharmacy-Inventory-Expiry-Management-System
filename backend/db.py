# =====================================================================
# FILE        : backend/db.py
# WHAT IT DOES: Everything Python needs to talk to MySQL, in 5 small functions:
#                 get_connection()  open a connection (settings come from .env)
#                 fetch_all(sql)    run a SELECT, get ALL rows back
#                 fetch_one(sql)    run a SELECT, get ONE row back (or None)
#                 execute(sql)      run an INSERT / UPDATE
#                 call_procedure()  CALL a stored procedure
#               Each function opens a connection, does its job and ALWAYS closes
#               the connection again, so the route files never deal with that.
# DEPENDS ON  : the .env file (DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME),
#               the packages mysql-connector-python and python-dotenv.
# USED BY     : main.py and every file in backend/routes/.
# READ ORDER  : read this FIRST in the backend.
#
# WHY THERE IS NO BUSINESS LOGIC IN PYTHON
#   All rules (FEFO, stock checks, alerts, GST) live inside MySQL as triggers,
#   procedures and views. Python only sends SQL and hands the answer to the website.
#
# HOW SQL INJECTION IS PREVENTED (viva question)
#   We never glue user text into the SQL string. The SQL contains %s placeholders
#   and the values travel separately in "params":
#       fetch_all("SELECT * FROM medicine WHERE medicine_name = %s", ("Paracetamol",))
#   The driver escapes every value, so it is always treated as data, never as SQL code.
# =====================================================================

import os                          # os.getenv reads environment variables

import mysql.connector             # the official MySQL driver for Python
from dotenv import load_dotenv     # reads the .env file

# Read the .env file once. After this, os.getenv("DB_USER") returns the value written in .env.
load_dotenv()


def get_connection():
    """Open and return a NEW connection to the pharmacy database."""
    connection = mysql.connector.connect(
        host=os.getenv("DB_HOST", "localhost"),            # where MySQL runs
        port=int(os.getenv("DB_PORT", "3306")),            # the port must be a number
        user=os.getenv("DB_USER", "root"),                 # MySQL user name
        password=os.getenv("DB_PASSWORD", ""),             # MySQL password
        database=os.getenv("DB_NAME", "pharmacy_db"),      # which database to use
        charset="utf8mb4",                                 # same character set as the database
        connection_timeout=5,                              # give up after 5 seconds
        autocommit=True,                                   # save every statement immediately; the stored
                                                           # procedures manage their own transactions
    )
    return connection


def fetch_all(sql, params=()):
    """Run a SELECT and return all rows as a list of dictionaries,
    for example [{"medicine_id": 1, "medicine_name": "Paracetamol 500mg"}, ...]."""
    connection = get_connection()
    try:
        # dictionary=True: every row comes back as {"column name": value}
        cursor = connection.cursor(dictionary=True)
        cursor.execute(sql, params)
        rows = cursor.fetchall()
        return rows
    finally:
        # "finally" runs even when an error happened, so the connection is never left open
        connection.close()


def fetch_one(sql, params=()):
    """Run a SELECT and return only the first row (a dictionary), or None if there is no row."""
    rows = fetch_all(sql, params)
    if len(rows) == 0:
        return None
    return rows[0]


def execute(sql, params=()):
    """Run an INSERT or UPDATE. Returns the new AUTO_INCREMENT id (useful after an INSERT)."""
    connection = get_connection()
    try:
        cursor = connection.cursor()
        cursor.execute(sql, params)
        return cursor.lastrowid
    finally:
        connection.close()


def call_procedure(name, args=()):
    """CALL a stored procedure and return two things:

    1. out_values  : the list of arguments AFTER the call. MySQL fills in the OUT parameters,
                     so for sp_make_sale(customer, medicine, qty, payment, OUT sale_id)
                     the new sale id is out_values[4] (the 5th argument).
    2. result_sets : every table the procedure SELECTed, in order. Each table is a list
                     of dictionaries. Example: sp_generate_bill returns 2 tables
                     (the bill lines and the totals) -> result_sets[0] and result_sets[1].
    """
    connection = get_connection()
    try:
        cursor = connection.cursor()
        # callproc sends: CALL name(args...) and returns the arguments with OUT values filled in
        out_values = cursor.callproc(name, args)

        # Collect the result sets. stored_results() gives one cursor per SELECT in the procedure.
        result_sets = []
        for result in cursor.stored_results():
            column_names = result.column_names          # e.g. ("sale_id", "medicine_name", ...)
            table = []
            for row in result.fetchall():               # each row is a tuple of values
                # zip pairs every column name with its value, dict() turns the pairs into {name: value}
                table.append(dict(zip(column_names, row)))
            result_sets.append(table)

        return out_values, result_sets
    finally:
        connection.close()
