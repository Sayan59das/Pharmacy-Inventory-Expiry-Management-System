# =====================================================================
# FILE        : backend/db.py
# WHAT IT DOES: Contains ONE function, get_connection(), that opens a
#               connection to the MySQL database. Every route file calls it.
# DEPENDS ON  : the .env file (DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME)
#               and the packages mysql-connector-python and python-dotenv.
# USED BY     : backend/main.py and every file in backend/routes/.
# READ ORDER  : read this FIRST in the backend (it is the shortest file).
#
# WHY THERE IS NO BUSINESS LOGIC IN PYTHON
#   All rules of the pharmacy (FEFO, stock checks, alerts, GST) live inside
#   MySQL as triggers, procedures and views. Python only (1) opens a
#   connection, (2) calls a procedure or view, (3) hands the answer to the web page.
# =====================================================================

import os                          # os.getenv reads environment variables

import mysql.connector             # the official MySQL driver for Python
from dotenv import load_dotenv     # reads the .env file


# Read the .env file once, when this file is imported.
# After this line, os.getenv("DB_USER") returns the value written in .env.
# (If a variable is already set in the operating system, that value wins over .env.)
load_dotenv()


def get_connection():
    """Open and return a NEW connection to the pharmacy database.

    The caller must close it (connection.close()) when it is finished.
    """
    # os.getenv(name, default): read an environment variable, or use the default if it is missing.
    connection = mysql.connector.connect(
        host=os.getenv("DB_HOST", "localhost"),            # where MySQL runs
        port=int(os.getenv("DB_PORT", "3306")),            # the port number must be an integer
        user=os.getenv("DB_USER", "root"),                 # MySQL user name
        password=os.getenv("DB_PASSWORD", ""),             # MySQL password
        database=os.getenv("DB_NAME", "pharmacy_db"),      # which database to use
        charset="utf8mb4",                                 # same character set as the database
        connection_timeout=5,                              # give up after 5 seconds if MySQL is not reachable
        autocommit=True,                                   # every statement is saved immediately; the stored
                                                           # procedures start/commit their own transactions
    )
    return connection
