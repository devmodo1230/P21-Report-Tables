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
    """Create all tables if they don't already exist. Safe to run on existing databases."""
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

            CREATE TABLE IF NOT EXISTS reports (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                report_name TEXT NOT NULL UNIQUE,
                created_at  TEXT DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS report_table_usage (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                report_id   INTEGER NOT NULL,
                table_id    INTEGER NOT NULL,
                created_at  TEXT DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(report_id) REFERENCES reports(id) ON DELETE CASCADE,
                FOREIGN KEY(table_id) REFERENCES p21_tables(id) ON DELETE CASCADE,
                UNIQUE(report_id, table_id)
            );

            CREATE TABLE IF NOT EXISTS report_column_usage (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                report_id   INTEGER NOT NULL,
                column_id   INTEGER NOT NULL,
                created_at  TEXT DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(report_id) REFERENCES reports(id) ON DELETE CASCADE,
                FOREIGN KEY(column_id) REFERENCES p21_columns(id) ON DELETE CASCADE,
                UNIQUE(report_id, column_id)
            );
        """)


# ---------------------------------------------------------------------------
# Report helpers
# ---------------------------------------------------------------------------

def get_or_create_report(conn: sqlite3.Connection, report_name: str) -> dict:
    """Return the report record, creating it if it does not exist."""
    report_name = report_name.strip()
    row = conn.execute(
        "SELECT id, report_name, created_at FROM reports WHERE LOWER(report_name) = LOWER(?)",
        (report_name,),
    ).fetchone()
    if row is None:
        conn.execute(
            "INSERT OR IGNORE INTO reports (report_name) VALUES (?)",
            (report_name,),
        )
        row = conn.execute(
            "SELECT id, report_name, created_at FROM reports WHERE LOWER(report_name) = LOWER(?)",
            (report_name,),
        ).fetchone()
    return {"id": row["id"], "report_name": row["report_name"], "created_at": row["created_at"]}


def get_all_reports(conn: sqlite3.Connection) -> list[dict]:
    """Return all reports ordered by name."""
    rows = conn.execute(
        "SELECT id, report_name, created_at FROM reports ORDER BY report_name"
    ).fetchall()
    return [{"id": r["id"], "report_name": r["report_name"], "created_at": r["created_at"]} for r in rows]


def get_report_by_name(conn: sqlite3.Connection, report_name: str) -> dict | None:
    """Return a report with all its tables and columns, or None if not found."""
    row = conn.execute(
        "SELECT id, report_name, created_at FROM reports WHERE LOWER(report_name) = LOWER(?)",
        (report_name,),
    ).fetchone()
    if row is None:
        return None

    report_id = row["id"]
    table_rows = conn.execute(
        """
        SELECT pt.id, pt.table_name
        FROM report_table_usage rtu
        JOIN p21_tables pt ON pt.id = rtu.table_id
        WHERE rtu.report_id = ?
        ORDER BY pt.table_name
        """,
        (report_id,),
    ).fetchall()

    tables = []
    for tr in table_rows:
        col_rows = conn.execute(
            """
            SELECT pc.column_name
            FROM report_column_usage rcu
            JOIN p21_columns pc ON pc.id = rcu.column_id
            WHERE rcu.report_id = ? AND pc.table_id = ?
            ORDER BY pc.column_name
            """,
            (report_id, tr["id"]),
        ).fetchall()
        tables.append({
            "table_name": tr["table_name"],
            "columns": [c["column_name"] for c in col_rows],
        })

    return {
        "report_name": row["report_name"],
        "created_at": row["created_at"],
        "tables": tables,
    }


# ---------------------------------------------------------------------------
# Usage link helpers
# ---------------------------------------------------------------------------

def link_report_to_table(conn: sqlite3.Connection, report_id: int, table_id: int) -> None:
    """Link a report to a table. INSERT OR IGNORE for idempotency."""
    conn.execute(
        "INSERT OR IGNORE INTO report_table_usage (report_id, table_id) VALUES (?, ?)",
        (report_id, table_id),
    )


def link_report_to_column(conn: sqlite3.Connection, report_id: int, column_id: int) -> None:
    """Link a report to a column. INSERT OR IGNORE for idempotency."""
    conn.execute(
        "INSERT OR IGNORE INTO report_column_usage (report_id, column_id) VALUES (?, ?)",
        (report_id, column_id),
    )


# ---------------------------------------------------------------------------
# Table helpers
# ---------------------------------------------------------------------------

def get_all_tables(conn: sqlite3.Connection) -> list[dict]:
    """Return every table with its column names as plain strings."""
    rows = conn.execute(
        "SELECT id, table_name, created_at FROM p21_tables ORDER BY table_name"
    ).fetchall()
    result = []
    for row in rows:
        columns = _get_column_names_for_table_id(conn, row["id"])
        result.append({
            "id": row["id"],
            "table_name": row["table_name"],
            "created_at": row["created_at"],
            "columns": columns,
        })
    return result


def get_table_by_name(conn: sqlite3.Connection, table_name: str) -> dict | None:
    """
    Return a single table with its columns and report usage, or None if not found.
    Columns are returned as objects: {column_name, reports: [...]}.
    """
    row = conn.execute(
        "SELECT id, table_name, created_at FROM p21_tables WHERE LOWER(table_name) = LOWER(?)",
        (table_name,),
    ).fetchone()
    if row is None:
        return None

    table_id = row["id"]

    report_rows = conn.execute(
        """
        SELECT r.report_name
        FROM report_table_usage rtu
        JOIN reports r ON r.id = rtu.report_id
        WHERE rtu.table_id = ?
        ORDER BY r.report_name
        """,
        (table_id,),
    ).fetchall()
    reports = [r["report_name"] for r in report_rows]

    col_rows = conn.execute(
        "SELECT id, column_name FROM p21_columns WHERE table_id = ? ORDER BY column_name",
        (table_id,),
    ).fetchall()
    columns = []
    for cr in col_rows:
        col_report_rows = conn.execute(
            """
            SELECT r.report_name
            FROM report_column_usage rcu
            JOIN reports r ON r.id = rcu.report_id
            WHERE rcu.column_id = ?
            ORDER BY r.report_name
            """,
            (cr["id"],),
        ).fetchall()
        columns.append({
            "column_name": cr["column_name"],
            "reports": [r["report_name"] for r in col_report_rows],
        })

    return {
        "id": table_id,
        "table_name": row["table_name"],
        "created_at": row["created_at"],
        "columns": columns,
        "reports": reports,
    }


def get_or_create_table(conn: sqlite3.Connection, table_name: str) -> dict:
    """
    Insert the table if it doesn't exist (case-insensitive check),
    then return {id, table_name, created_at}.
    """
    table_name = table_name.strip()
    row = conn.execute(
        "SELECT id, table_name, created_at FROM p21_tables WHERE LOWER(table_name) = LOWER(?)",
        (table_name,),
    ).fetchone()
    if row is None:
        conn.execute(
            "INSERT OR IGNORE INTO p21_tables (table_name) VALUES (?)",
            (table_name,),
        )
        row = conn.execute(
            "SELECT id, table_name, created_at FROM p21_tables WHERE LOWER(table_name) = LOWER(?)",
            (table_name,),
        ).fetchone()
    return {"id": row["id"], "table_name": row["table_name"], "created_at": row["created_at"]}


def upsert_table(conn: sqlite3.Connection, table_name: str) -> dict:
    """Backward-compat alias for get_or_create_table."""
    return get_or_create_table(conn, table_name)


# ---------------------------------------------------------------------------
# Column helpers
# ---------------------------------------------------------------------------

def _get_column_names_for_table_id(conn: sqlite3.Connection, table_id: int) -> list[str]:
    """Return a sorted list of column name strings for a given table_id."""
    rows = conn.execute(
        "SELECT column_name FROM p21_columns WHERE table_id = ? ORDER BY column_name",
        (table_id,),
    ).fetchall()
    return [r["column_name"] for r in rows]


def get_or_create_column(conn: sqlite3.Connection, table_id: int, column_name: str) -> dict:
    """
    Insert a column if it doesn't exist (case-insensitive check),
    then return {id, column_name}.
    """
    column_name = column_name.strip()
    row = conn.execute(
        "SELECT id, column_name FROM p21_columns WHERE table_id = ? AND LOWER(column_name) = LOWER(?)",
        (table_id, column_name),
    ).fetchone()
    if row is None:
        conn.execute(
            "INSERT OR IGNORE INTO p21_columns (table_id, column_name) VALUES (?, ?)",
            (table_id, column_name),
        )
        row = conn.execute(
            "SELECT id, column_name FROM p21_columns WHERE table_id = ? AND LOWER(column_name) = LOWER(?)",
            (table_id, column_name),
        ).fetchone()
    return {"id": row["id"], "column_name": row["column_name"]}


def add_column(conn: sqlite3.Connection, table_id: int, column_name: str) -> None:
    """Insert a column. Silently ignores case-insensitive duplicates."""
    get_or_create_column(conn, table_id, column_name)


def bulk_add_columns(conn: sqlite3.Connection, table_id: int, column_names: list[str]) -> None:
    """Insert multiple columns, skipping any case-insensitive duplicates."""
    for column_name in column_names:
        add_column(conn, table_id, column_name)
