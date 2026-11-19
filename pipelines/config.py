import os
import urllib
from dotenv import load_dotenv
from sqlalchemy import create_engine

load_dotenv()

SERVER = os.getenv("DB_SERVER", r"localhost\SQLEXPRESS")
DATABASE = os.getenv("DB_NAME", "EpochAI_DW")
DRIVER = os.getenv("DB_DRIVER", "ODBC Driver 18 for SQL Server")

def get_sql_engine():
    params = urllib.parse.quote_plus(
        f"DRIVER={{{DRIVER}}};SERVER={SERVER};DATABASE={DATABASE};Trusted_Connection=yes;TrustServerCertificate=yes;"
    )
    return create_engine(f"mssql+pyodbc:///?odbc_connect={params}")
