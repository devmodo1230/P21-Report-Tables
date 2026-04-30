# P21 Schema Tracker

A small full-stack application for tracking **Prophet 21** table names and their columns.

## Stack

| Layer    | Technology                           |
|----------|--------------------------------------|
| Backend  | Python FastAPI                        |
| Database | SQLite (Python built-in `sqlite3`)   |
| Frontend | Plain HTML, CSS, Vanilla JavaScript  |

## Project structure

```
.
├── main.py        # FastAPI application & routes
├── database.py    # SQLite helpers (init, queries)
├── schemas.py     # Pydantic request/response models
└── static/
    ├── index.html # Single-page frontend
    ├── app.js     # Frontend logic
    └── styles.css # Styles
```

## Quick start

```bash
pip install fastapi uvicorn
uvicorn main:app --reload
```

Then open **http://127.0.0.1:8000** in your browser.

The SQLite database (`p21_schema_tracker.db`) is created automatically on first run.

## API endpoints

| Method | Path                                      | Description                              |
|--------|-------------------------------------------|------------------------------------------|
| GET    | `/`                                       | Serve the frontend                       |
| GET    | `/api/tables`                             | List all tables with columns             |
| GET    | `/api/tables/{table_name}`                | Get one table (returns `exists: false` if missing) |
| POST   | `/api/tables`                             | Create table (idempotent)                |
| POST   | `/api/tables/{table_name}/columns`        | Add a single column                      |
| POST   | `/api/tables/{table_name}/columns/bulk`   | Add multiple columns at once             |

## Notes

- Column names are de-duplicated **case-insensitively** per table.
- The same column name may exist across different tables.
- All SQL uses parameterised queries; no raw string interpolation.
