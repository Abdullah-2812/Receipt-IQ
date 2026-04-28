import psycopg2
from psycopg2.extras import RealDictCursor

from ._secrets import DB_PASSWORD

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "database": "receipt_iq",
    "user": "postgres",
    "password": DB_PASSWORD,
}

def get_connection():
    return psycopg2.connect(**DB_CONFIG, cursor_factory=RealDictCursor)
