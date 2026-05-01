"""
P21 Schema Tracker – FastAPI backend.

Run locally:
    pip install fastapi uvicorn
    uvicorn main:app --reload
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from database import (
    get_connection, init_db,
    get_all_tables, get_table_by_name,
    get_or_create_report, get_or_create_table, get_or_create_column,
    link_report_to_table, link_report_to_column,
    get_all_reports, get_report_by_name,
)
from schemas import BulkColumnCreate, ColumnCreate, TableCreate, ParseSqlRequest
from sql_parser import parse_sql


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize the SQLite database on startup."""
    init_db()
    yield


app = FastAPI(title="P21 Schema Tracker", lifespan=lifespan)

# Serve everything under /static (css, js, etc.)
app.mount("/static", StaticFiles(directory="static"), name="static")


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/")
def serve_index():
    """Serve the frontend SPA."""
    return FileResponse("static/index.html")


@app.get("/api/tables")
def list_tables():
    """Return all tables with their column name lists (plain strings)."""
    with get_connection() as conn:
        tables = get_all_tables(conn)
    return {"tables": tables}


@app.get("/api/reports")
def list_reports():
    """Return all reports."""
    with get_connection() as conn:
        reports = get_all_reports(conn)
    return {"reports": reports}


@app.get("/api/reports/{report_name}")
def get_report(report_name: str):
    """Return a report with all its tables and columns."""
    report_name = report_name.strip()
    if not report_name:
        raise HTTPException(status_code=400, detail="report_name must not be empty")
    with get_connection() as conn:
        report = get_report_by_name(conn, report_name)
    if report is None:
        raise HTTPException(status_code=404, detail=f"Report '{report_name}' not found")
    return JSONResponse(content=report)


@app.get("/api/tables/{table_name}")
def get_table(table_name: str):
    """
    Return one table with columns (including per-column report usage) by name.
    If the table does not exist, return exists=false with empty columns list.
    """
    table_name = table_name.strip()
    if not table_name:
        raise HTTPException(status_code=400, detail="table_name must not be empty")

    with get_connection() as conn:
        table = get_table_by_name(conn, table_name)

    if table is None:
        return JSONResponse(content={
            "exists": False,
            "table_name": table_name,
            "columns": [],
            "reports": [],
        })

    return JSONResponse(content={"exists": True, **table})


@app.post("/api/tables", status_code=201)
def create_table(payload: TableCreate):
    """
    Create or retrieve a table and link it to a report.
    Returns the table with its columns and report usage.
    """
    with get_connection() as conn:
        report = get_or_create_report(conn, payload.report_name)
        table = get_or_create_table(conn, payload.table_name)
        link_report_to_table(conn, report["id"], table["id"])
        table_data = get_table_by_name(conn, payload.table_name)
    return JSONResponse(status_code=201, content={"exists": True, **table_data})


@app.post("/api/tables/{table_name}/columns", status_code=201)
def add_column_to_table(table_name: str, payload: ColumnCreate):
    """
    Add a single column to a table and link both to a report.
    Creates the table if needed. Silently ignores duplicates.
    """
    table_name = table_name.strip()
    if not table_name:
        raise HTTPException(status_code=400, detail="table_name must not be empty")

    with get_connection() as conn:
        report = get_or_create_report(conn, payload.report_name)
        table = get_or_create_table(conn, table_name)
        col = get_or_create_column(conn, table["id"], payload.column_name)
        link_report_to_table(conn, report["id"], table["id"])
        link_report_to_column(conn, report["id"], col["id"])
        table_data = get_table_by_name(conn, table_name)

    return JSONResponse(status_code=201, content={"exists": True, **table_data})


@app.post("/api/tables/{table_name}/columns/bulk", status_code=201)
def bulk_add_columns_to_table(table_name: str, payload: BulkColumnCreate):
    """
    Add multiple columns to a table and link all to a report.
    Creates the table if needed. Silently ignores duplicates.
    """
    table_name = table_name.strip()
    if not table_name:
        raise HTTPException(status_code=400, detail="table_name must not be empty")

    with get_connection() as conn:
        report = get_or_create_report(conn, payload.report_name)
        table = get_or_create_table(conn, table_name)
        link_report_to_table(conn, report["id"], table["id"])
        for col_name in payload.columns:
            col = get_or_create_column(conn, table["id"], col_name)
            link_report_to_column(conn, report["id"], col["id"])
        table_data = get_table_by_name(conn, table_name)

    return JSONResponse(status_code=201, content={"exists": True, **table_data})


@app.post("/api/parse-sql")
def parse_sql_endpoint(payload: ParseSqlRequest):
    """
    Parse raw SQL, persist discovered tables/columns under the given report,
    and return parsed results plus report linkage.
    """
    tables, warnings = parse_sql(payload.sql)

    with get_connection() as conn:
        report = get_or_create_report(conn, payload.report_name)
        for tbl in tables:
            table = get_or_create_table(conn, tbl["table_name"])
            link_report_to_table(conn, report["id"], table["id"])
            for col_name in tbl["columns"]:
                col = get_or_create_column(conn, table["id"], col_name)
                link_report_to_column(conn, report["id"], col["id"])

    return {
        "report_name": payload.report_name,
        "tables": tables,
        "warnings": warnings,
    }
