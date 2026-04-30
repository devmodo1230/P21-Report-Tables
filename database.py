"""
Database module for P21 Schema Tracker.
Uses Python's built-in sqlite3 module only.
"""

import sqlite3
from contextlib import contextmanager

DB_NAME = "p21_schema_tracker.db"


@contextmanager
def get_connection():
    """Context manager for database connections with foreign key support."""
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db():
    """Create tables if they don't already exist."""
    with get_connection() as conn:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS p21_tables (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                table_name  TEXT NOT NULL UNIQUE,
                created_at  TEXT DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS p21_columns (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                table_id    INTEGER NOT NULL,
                column_name TEXT NOT NULL,
                created_at  TEXT DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(table_id) REFERENCES p21_tables(id) ON DELETE CASCADE,
                UNIQUE(table_id, column_name)
            );
        """)


# ---------------------------------------------------------------------------
# Table helpers
# ---------------------------------------------------------------------------

def get_all_tables(conn: sqlite3.Connection) -> list[dict]:
    """Return every table with its columns."""
    rows = conn.execute(
        "SELECT id, table_name, created_at FROM p21_tables ORDER BY table_name"
    ).fetchall()
    result = []
    for row in rows:
        columns = _get_columns_for_table_id(conn, row["id"])
        result.append({
            "id": row["id"],
            "table_name": row["table_name"],
            "created_at": row["created_at"],
            "columns": columns,
        })
    return result


def get_table_by_name(conn: sqlite3.Connection, table_name: str) -> dict | None:
    """Return a single table with its columns, or None if not found."""
    row = conn.execute(
        "SELECT id, table_name, created_at FROM p21_tables WHERE LOWER(table_name) = LOWER(?)",
        (table_name,),
    ).fetchone()
    if row is None:
        return None
    columns = _get_columns_for_table_id(conn, row["id"])
    return {
        "id": row["id"],
        "table_name": row["table_name"],
        "created_at": row["created_at"],
        "columns": columns,
    }


def upsert_table(conn: sqlite3.Connection, table_name: str) -> dict:
    """
    Insert the table if it doesn't exist (case-insensitive check),
    then return the table record with columns.
    """
    # Check if the table already exists (case-insensitive)
    existing = conn.execute(
        "SELECT id, table_name, created_at FROM p21_tables WHERE LOWER(table_name) = LOWER(?)",
        (table_name,),
    ).fetchone()

    if existing is None:
        conn.execute(
            "INSERT OR IGNORE INTO p21_tables (table_name) VALUES (?)",
            (table_name,),
        )
        existing = conn.execute(
            "SELECT id, table_name, created_at FROM p21_tables WHERE LOWER(table_name) = LOWER(?)",
            (table_name,),
        ).fetchone()

    columns = _get_columns_for_table_id(conn, existing["id"])
    return {
        "id": existing["id"],
        "table_name": existing["table_name"],
        "created_at": existing["created_at"],
        "columns": columns,
    }


# ---------------------------------------------------------------------------
# Column helpers
# ---------------------------------------------------------------------------

def _get_columns_for_table_id(conn: sqlite3.Connection, table_id: int) -> list[str]:
    """Return a sorted list of column names for a given table_id."""
    rows = conn.execute(
        "SELECT column_name FROM p21_columns WHERE table_id = ? ORDER BY column_name",
        (table_id,),
    ).fetchall()
    return [r["column_name"] for r in rows]


def add_column(conn: sqlite3.Connection, table_id: int, column_name: str) -> None:
    """
    Insert a column for a table. Silently ignores duplicates.
    Duplicate check is case-insensitive: if a column with the same name
    (case-insensitive) already exists, it is skipped.
    """
    existing = conn.execute(
        "SELECT id FROM p21_columns WHERE table_id = ? AND LOWER(column_name) = LOWER(?)",
        (table_id, column_name),
    ).fetchone()
    if existing is None:
        conn.execute(
            "INSERT INTO p21_columns (table_id, column_name) VALUES (?, ?)",
            (table_id, column_name),
        )


def bulk_add_columns(conn: sqlite3.Connection, table_id: int, column_names: list[str]) -> None:
    """Insert multiple columns, skipping any case-insensitive duplicates."""
    for column_name in column_names:
        add_column(conn, table_id, column_name)
