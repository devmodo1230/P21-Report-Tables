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

from database import get_connection, init_db, get_all_tables, get_table_by_name, upsert_table, bulk_add_columns, add_column
from schemas import BulkColumnCreate, ColumnCreate, TableCreate


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
    """Return all tables with their columns."""
    with get_connection() as conn:
        tables = get_all_tables(conn)
    return {"tables": tables}


@app.get("/api/tables/{table_name}")
def get_table(table_name: str):
    """
    Return one table and its columns by name.
    If the table does not exist, return exists=false with an empty columns list.
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
        })

    return JSONResponse(content={
        "exists": True,
        **table,
    })


@app.post("/api/tables", status_code=201)
def create_table(payload: TableCreate):
    """
    Create a table if it does not already exist.
    Returns the table with its columns (idempotent).
    """
    with get_connection() as conn:
        table = upsert_table(conn, payload.table_name)

    return JSONResponse(status_code=201, content={"exists": True, **table})


@app.post("/api/tables/{table_name}/columns", status_code=201)
def add_column_to_table(table_name: str, payload: ColumnCreate):
    """
    Add a single column to a table (creating the table first if needed).
    Silently ignores duplicates.
    """
    table_name = table_name.strip()
    if not table_name:
        raise HTTPException(status_code=400, detail="table_name must not be empty")

    with get_connection() as conn:
        table = upsert_table(conn, table_name)
        add_column(conn, table["id"], payload.column_name)
        # Re-fetch to get updated column list
        table = get_table_by_name(conn, table_name)

    return JSONResponse(status_code=201, content={"exists": True, **table})


@app.post("/api/tables/{table_name}/columns/bulk", status_code=201)
def bulk_add_columns_to_table(table_name: str, payload: BulkColumnCreate):
    """
    Add multiple columns to a table (creating the table first if needed).
    Silently ignores duplicates.
    """
    table_name = table_name.strip()
    if not table_name:
        raise HTTPException(status_code=400, detail="table_name must not be empty")

    with get_connection() as conn:
        table = upsert_table(conn, table_name)
        bulk_add_columns(conn, table["id"], payload.columns)
        # Re-fetch to get updated column list
        table = get_table_by_name(conn, table_name)

    return JSONResponse(status_code=201, content={"exists": True, **table})
