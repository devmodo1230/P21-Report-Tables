/**
 * P21 Schema Tracker – Frontend Logic
 *
 * Talks to the FastAPI backend:
 *   GET  /api/tables/{table_name}
 *   POST /api/tables
 *   POST /api/tables/{table_name}/columns/bulk
 *   GET  /api/tables
 */

"use strict";

// ---------------------------------------------------------------------------
// DOM references
// ---------------------------------------------------------------------------
const tableNameInput    = document.getElementById("table-name-input");
const loadBtn           = document.getElementById("load-btn");

const tableInfoSection  = document.getElementById("table-info-section");
const tableTitle        = document.getElementById("table-title");
const tableBadge        = document.getElementById("table-badge");
const columnList        = document.getElementById("column-list");
const columnCount       = document.getElementById("column-count");
const noColumnsMsg      = document.getElementById("no-columns-msg");

const addColumnsSection = document.getElementById("add-columns-section");
const columnsInput      = document.getElementById("columns-input");
const saveBtn           = document.getElementById("save-btn");
const clearBtn          = document.getElementById("clear-btn");
const messageArea       = document.getElementById("message-area");

const allTablesList     = document.getElementById("all-tables-list");
const refreshAllBtn     = document.getElementById("refresh-all-btn");

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
let currentTableName = null; // the table currently being viewed/edited

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Parse textarea content (newlines and/or commas) into trimmed column names. */
function parseColumns(raw) {
  return raw
    .split(/[\n,]+/)
    .map(s => s.trim())
    .filter(s => s.length > 0);
}

/** Show a temporary success or error message. */
function showMessage(text, type = "success") {
  messageArea.innerHTML = `<div class="msg-${type}">${escapeHtml(text)}</div>`;
  setTimeout(() => { messageArea.innerHTML = ""; }, 5000);
}

/** Minimal HTML escape to prevent XSS. */
function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// ---------------------------------------------------------------------------
// Render helpers
// ---------------------------------------------------------------------------

/** Render the column list for the currently selected table. */
function renderColumnList(columns) {
  columnList.innerHTML = "";
  columnCount.textContent = columns.length;

  if (columns.length === 0) {
    noColumnsMsg.style.display = "block";
  } else {
    noColumnsMsg.style.display = "none";
    columns.forEach(col => {
      const li = document.createElement("li");
      li.textContent = col;
      columnList.appendChild(li);
    });
  }
}

/** Render the "All Tracked Tables" section. */
function renderAllTables(tables) {
  allTablesList.innerHTML = "";

  if (!tables || tables.length === 0) {
    allTablesList.innerHTML = '<p class="no-tables-msg">No tables tracked yet.</p>';
    return;
  }

  tables.forEach(tbl => {
    const div = document.createElement("div");
    div.className = "table-item";

    const nameEl = document.createElement("div");
    nameEl.className = "table-item-name";
    nameEl.textContent = tbl.table_name;
    div.appendChild(nameEl);

    const colsEl = document.createElement("div");
    colsEl.className = "table-item-cols";
    if (tbl.columns.length === 0) {
      colsEl.innerHTML = '<span style="color:#888;border:none;background:none;">—</span>';
    } else {
      tbl.columns.forEach(col => {
        const span = document.createElement("span");
        span.textContent = col;
        colsEl.appendChild(span);
      });
    }
    div.appendChild(colsEl);

    allTablesList.appendChild(div);
  });
}

// ---------------------------------------------------------------------------
// API calls
// ---------------------------------------------------------------------------

/** Load a table by name (GET /api/tables/{table_name}). */
async function loadTable(tableName) {
  const res = await fetch(`/api/tables/${encodeURIComponent(tableName)}`);
  if (!res.ok) {
    throw new Error(`Server error: ${res.status}`);
  }
  return res.json();
}

/** Create or fetch a table (POST /api/tables). */
async function ensureTable(tableName) {
  const res = await fetch("/api/tables", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ table_name: tableName }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.detail || `Server error: ${res.status}`);
  }
  return res.json();
}

/** Bulk-add columns (POST /api/tables/{table_name}/columns/bulk). */
async function saveColumns(tableName, columns) {
  const res = await fetch(`/api/tables/${encodeURIComponent(tableName)}/columns/bulk`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ columns }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.detail || `Server error: ${res.status}`);
  }
  return res.json();
}

/** Fetch all tables (GET /api/tables). */
async function fetchAllTables() {
  const res = await fetch("/api/tables");
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  const data = await res.json();
  return data.tables || [];
}

// ---------------------------------------------------------------------------
// Event handlers
// ---------------------------------------------------------------------------

/** "Load Table" button. */
loadBtn.addEventListener("click", async () => {
  const tableName = tableNameInput.value.trim();
  if (!tableName) {
    alert("Please enter a table name.");
    return;
  }

  loadBtn.disabled = true;
  loadBtn.textContent = "Loading…";

  try {
    const data = await loadTable(tableName);
    currentTableName = data.table_name || tableName;

    // Show table info section
    tableInfoSection.style.display = "block";
    addColumnsSection.style.display = "block";
    tableTitle.textContent = currentTableName;

    if (data.exists) {
      tableBadge.textContent = "Existing Table";
      tableBadge.className = "badge badge-existing";
    } else {
      tableBadge.textContent = "New Table";
      tableBadge.className = "badge badge-new";
    }

    renderColumnList(data.columns || []);
    messageArea.innerHTML = "";
  } catch (err) {
    showMessage(err.message, "error");
  } finally {
    loadBtn.disabled = false;
    loadBtn.textContent = "Load Table";
  }
});

/** Allow pressing Enter in the table name input to trigger Load. */
tableNameInput.addEventListener("keydown", e => {
  if (e.key === "Enter") loadBtn.click();
});

/** "Save Columns" button. */
saveBtn.addEventListener("click", async () => {
  const columns = parseColumns(columnsInput.value);

  if (columns.length === 0) {
    showMessage("Please enter at least one column name.", "error");
    return;
  }

  if (!currentTableName) {
    showMessage("No table selected. Use "Load Table" first.", "error");
    return;
  }

  saveBtn.disabled = true;
  saveBtn.textContent = "Saving…";

  try {
    // Ensure the table exists before adding columns
    await ensureTable(currentTableName);

    // Bulk-add columns
    const data = await saveColumns(currentTableName, columns);

    // Update the badge to "Existing" after first save
    tableBadge.textContent = "Existing Table";
    tableBadge.className = "badge badge-existing";

    // Refresh column list
    renderColumnList(data.columns || []);
    columnsInput.value = "";
    showMessage(`Saved ${columns.length} column(s) to "${currentTableName}".`, "success");

    // Also refresh the all-tables list
    const allTables = await fetchAllTables();
    renderAllTables(allTables);
  } catch (err) {
    showMessage(err.message, "error");
  } finally {
    saveBtn.disabled = false;
    saveBtn.textContent = "Save Columns";
  }
});

/** "Clear" button for the textarea. */
clearBtn.addEventListener("click", () => {
  columnsInput.value = "";
  messageArea.innerHTML = "";
});

/** "Refresh" button for the all-tables section. */
refreshAllBtn.addEventListener("click", async () => {
  refreshAllBtn.disabled = true;
  try {
    const tables = await fetchAllTables();
    renderAllTables(tables);
  } catch (err) {
    console.error("Failed to refresh tables:", err);
  } finally {
    refreshAllBtn.disabled = false;
  }
});

// ---------------------------------------------------------------------------
// Init: load all tables on page load
// ---------------------------------------------------------------------------
(async function init() {
  try {
    const tables = await fetchAllTables();
    renderAllTables(tables);
  } catch (err) {
    console.error("Failed to load tables on init:", err);
  }
})();
