"""
SQL Parser for P21 Schema Tracker.

Extracts table names and column aliases from raw SQL text using a
heuristic regex-based approach.

Assumptions:
- Tables of interest start with p21_view_ or p21s_
- Table aliases follow directly after the table name in FROM/JOIN clauses
  (optionally preceded by the AS keyword)
- Column references are in the form alias.column_name
- No full SQL parsing — complex cases (CTEs, subqueries) are ignored or warned

Entry point: parse_sql(sql) -> (tables, warnings)
"""

import re

# ---------------------------------------------------------------------------
# Patterns
# ---------------------------------------------------------------------------

# Matches: FROM/JOIN <p21_table> [AS] [alias]
# Group 1: keyword (FROM or JOIN)
# Group 2: table name
# Group 3: alias (optional; may be a reserved word — handled below)
TABLE_PATTERN = re.compile(
    r'\b(FROM|JOIN)\s+(p21_view_\w+|p21s_\w+|is_\w+)(?:\s+(?:AS\s+)?(\w+))?',
    re.IGNORECASE,
)

# Matches: alias.column_name
# Group 1: alias (or schema prefix)
# Group 2: column name
COLUMN_PATTERN = re.compile(r'\b(\w+)\.(\w+)', re.IGNORECASE)

# Words that look like aliases but are SQL keywords.
# When captured as an alias candidate, they mean "no alias was provided."
RESERVED_WORDS = frozenset({
    'as', 'on', 'where', 'set', 'inner', 'outer', 'left', 'right', 'full',
    'cross', 'natural', 'join', 'from', 'select', 'with', 'having',
    'group', 'order', 'by', 'union', 'all', 'distinct', 'into', 'values',
    'update', 'insert', 'delete', 'create', 'drop', 'alter', 'table',
    'view', 'index', 'and', 'or', 'not', 'in', 'exists', 'between',
    'like', 'is', 'null', 'case', 'when', 'then', 'else', 'end', 'cast',
    'convert', 'top', 'limit', 'offset',
})


# ---------------------------------------------------------------------------
# Step 1 — Extract tables and aliases
# ---------------------------------------------------------------------------

def extract_tables_and_aliases(sql: str) -> tuple[dict[str, str], list[str]]:
    """
    Scan SQL for FROM/JOIN references to p21_view_* or p21s_* tables.

    Returns:
        alias_map  - {alias_or_table_name: table_name}
        warnings   - human-readable issues found during parsing
    """
    warnings: list[str] = []
    alias_map: dict[str, str] = {}

    for match in TABLE_PATTERN.finditer(sql):
        table_name = match.group(2).lower()
        raw_alias = match.group(3)

        if raw_alias is None or raw_alias.lower() in RESERVED_WORDS:
            # No alias present — key by table name itself
            alias = table_name
            warnings.append(
                f"Table '{table_name}' referenced without an alias; "
                "using table name as key."
            )
        else:
            alias = raw_alias.lower()

        if alias in alias_map and alias_map[alias] != table_name:
            warnings.append(
                f"Duplicate alias '{alias}': previously mapped to "
                f"'{alias_map[alias]}', now overwritten with '{table_name}'."
            )

        alias_map[alias] = table_name

    return alias_map, warnings


# ---------------------------------------------------------------------------
# Step 2 — Extract column references
# ---------------------------------------------------------------------------

def extract_columns(
    sql: str,
    alias_map: dict[str, str],
) -> tuple[dict[str, set[str]], list[str]]:
    """
    Scan SQL for alias.column_name patterns and map them to tables.

    Returns:
        column_map - {table_name: set of column names}
        warnings   - human-readable issues found during parsing
    """
    warnings: list[str] = []
    column_map: dict[str, set[str]] = {tbl: set() for tbl in alias_map.values()}

    for match in COLUMN_PATTERN.finditer(sql):
        alias = match.group(1).lower()
        column = match.group(2).lower()

        if alias not in alias_map:
            # Only warn for short identifiers (≤4 chars) that look like aliases;
            # longer ones are more likely schema/object prefixes.
            if len(alias) <= 4 and alias not in RESERVED_WORDS:
                warnings.append(
                    f"Column reference '{alias}.{column}' uses unknown "
                    f"alias '{alias}'; skipped."
                )
            continue

        table_name = alias_map[alias]
        column_map[table_name].add(column)

    return column_map, warnings


# ---------------------------------------------------------------------------
# Step 3 & 4 — Deduplicate and build structured result
# ---------------------------------------------------------------------------

def build_result(
    alias_map: dict[str, str],
    column_map: dict[str, set[str]],
) -> list[dict]:
    """
    Group by table name and return a sorted, deduplicated list of records.

    Each record: {table_name, alias, columns: [...sorted...]}
    """
    # Invert alias_map: table_name -> first alias encountered
    table_to_alias: dict[str, str] = {}
    for alias, table_name in alias_map.items():
        if table_name not in table_to_alias:
            table_to_alias[table_name] = alias

    result = []
    for table_name in sorted(table_to_alias):
        primary_alias = table_to_alias[table_name]
        columns = sorted(column_map.get(table_name, set()))
        result.append({
            "table_name": table_name,
            "alias": primary_alias,
            "columns": columns,
        })

    return result


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def parse_sql(sql: str) -> tuple[list[dict], list[str]]:
    """
    Parse raw SQL and return extracted table/column data plus warnings.

    Returns:
        tables   - list of {table_name, alias, columns} dicts
        warnings - list of warning strings
    """
    all_warnings: list[str] = []

    alias_map, w1 = extract_tables_and_aliases(sql)
    all_warnings.extend(w1)

    if not alias_map:
        all_warnings.append(
            "No p21_view_* or p21s_* tables found in the provided SQL."
        )
        return [], all_warnings

    column_map, w2 = extract_columns(sql, alias_map)
    all_warnings.extend(w2)

    tables = build_result(alias_map, column_map)
    return tables, all_warnings
