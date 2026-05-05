/**
 * P21 Schema Tracker – Frontend Logic
 *
 * Talks to the FastAPI backend:
 *   GET  /api/reports
 *   GET  /api/reports/{report_name}
 *   GET  /api/tables
 *   GET  /api/tables/{table_name}
 *   POST /api/tables
 *   POST /api/tables/{table_name}/columns/bulk
 *   POST /api/parse-sql
 */

"use strict";

// ---------------------------------------------------------------------------
// DOM references
// ---------------------------------------------------------------------------
const reportNameInput    = document.getElementById("report-name-input");
const reportSuggestions  = document.getElementById("report-suggestions");
const loadReportBtn      = document.getElementById("load-report-btn");
const reportMessageArea  = document.getElementById("report-message-area");
const reportUsageSection = document.getElementById("report-usage-section");
const reportUsageTitle   = document.getElementById("report-usage-title");
const reportUsageList    = document.getElementById("report-usage-list");

const tableNameInput    = document.getElementById("table-name-input");
const tablePicker       = document.getElementById("table-picker");
const loadBtn           = document.getElementById("load-btn");
const deleteBtn         = document.getElementById("delete-btn");

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

const sqlInput          = document.getElementById("sql-input");
const parseBtn          = document.getElementById("parse-btn");
const clearSqlBtn       = document.getElementById("clear-sql-btn");
const parseMessageArea  = document.getElementById("parse-message-area");
const parseResults      = document.getElementById("parse-results");
const parseResultsList  = document.getElementById("parse-results-list");

let currentTableList  = [];

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
let currentReportName = "";
let currentTableName  = null;

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

/** Show a temporary message in the column-add message area. */
function showMessage(text, type = "success") {
  messageArea.innerHTML = `<div class="msg-${type}">${escapeHtml(text)}</div>`;
  setTimeout(() => { messageArea.innerHTML = ""; }, 5000);
}

/** Show a temporary message in the parse message area. */
function showParseMessage(text, type = "success") {
  parseMessageArea.innerHTML = `<div class="msg-${type}">${escapeHtml(text)}</div>`;
  setTimeout(() => { parseMessageArea.innerHTML = ""; }, 6000);
}

/** Minimal HTML escape to prevent XSS. */
function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Enable/disable write buttons based on whether a report name is set. */
function updateButtonStates() {
  const hasReport = currentReportName.length > 0;
  saveBtn.disabled  = !hasReport;
  parseBtn.disabled = !hasReport;
}

// ---------------------------------------------------------------------------
// Render helpers
// ---------------------------------------------------------------------------

/**
 * Render the column list for the currently selected table.
 * Accepts columns as either plain strings or {column_name, reports: [...]} objects.
 */
function renderColumnList(columns) {
  columnList.innerHTML = "";
  columnCount.textContent = columns.length;

  if (columns.length === 0) {
    noColumnsMsg.style.display = "block";
    return;
  }

  noColumnsMsg.style.display = "none";
  columns.forEach(col => {
    const colName   = typeof col === "string" ? col : col.column_name;
    const colReports = (typeof col === "object" && col.reports) ? col.reports : [];

    const li = document.createElement("li");
    li.textContent = colName;

    if (colReports.length > 0) {
      const tag = document.createElement("span");
      tag.className   = "col-report-tags";
      tag.textContent = colReports.join(", ");
      li.appendChild(tag);
    }

    columnList.appendChild(li);
  });
}

/** Render the "All Tracked Tables" section. */
function renderAllTables(tables) {
  currentTableList = tables || [];
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

    if (!tbl.columns || tbl.columns.length === 0) {
      colsEl.innerHTML = '<span style="color:#888;border:none;background:none;">—</span>';
    } else {
      tbl.columns.forEach(col => {
        const span = document.createElement("span");
        span.textContent = typeof col === "string" ? col : col.column_name;
        colsEl.appendChild(span);
      });
    }
    div.appendChild(colsEl);
    allTablesList.appendChild(div);
  });
}

/** Render the Current Report Usage section. */
function renderReportUsage(report) {
  reportUsageTitle.textContent = `Report: ${report.report_name}`;
  reportUsageList.innerHTML = "";

  if (!report.tables || report.tables.length === 0) {
    reportUsageList.innerHTML = '<p class="no-tables-msg">No tables linked to this report yet.</p>';
    reportUsageSection.style.display = "block";
    return;
  }

  report.tables.forEach(tbl => {
    const div = document.createElement("div");
    div.className = "report-usage-item";

    const nameEl = document.createElement("div");
    nameEl.className = "report-usage-table-name";
    nameEl.textContent = tbl.table_name;
    div.appendChild(nameEl);

    if (tbl.columns && tbl.columns.length > 0) {
      const colsEl = document.createElement("div");
      colsEl.className = "table-item-cols";
      tbl.columns.forEach(col => {
        const span = document.createElement("span");
        span.textContent = col;
        colsEl.appendChild(span);
      });
      div.appendChild(colsEl);
    } else {
      const none = document.createElement("p");
      none.className = "muted";
      none.style.marginTop = "0.3rem";
      none.textContent = "No columns tracked for this report.";
      div.appendChild(none);
    }

    reportUsageList.appendChild(div);
  });

  reportUsageSection.style.display = "block";
}

/** Render the parse results panel. */
function renderParseResults(data) {
  parseResultsList.innerHTML = "";

  if (data.warnings && data.warnings.length > 0) {
    const warnDiv = document.createElement("div");
    warnDiv.className = "parse-warnings";
    warnDiv.innerHTML = `<strong>Warnings (${data.warnings.length})</strong>`;
    const ul = document.createElement("ul");
    data.warnings.forEach(w => {
      const li = document.createElement("li");
      li.textContent = w;
      ul.appendChild(li);
    });
    warnDiv.appendChild(ul);
    parseResultsList.appendChild(warnDiv);
  }

  if (!data.tables || data.tables.length === 0) {
    parseResultsList.innerHTML += '<p class="no-tables-msg">No p21 tables found in the provided SQL.</p>';
    parseResults.style.display = "block";
    return;
  }

  data.tables.forEach(tbl => {
    const div = document.createElement("div");
    div.className = "parse-table-item";

    const header = document.createElement("div");
    header.className = "parse-table-header";

    const nameEl = document.createElement("span");
    nameEl.className = "parse-table-name";
    nameEl.textContent = tbl.table_name;
    header.appendChild(nameEl);

    const aliasEl = document.createElement("span");
    aliasEl.className = "parse-alias-badge";
    aliasEl.textContent = `alias: ${tbl.alias}`;
    header.appendChild(aliasEl);

    const colCountEl = document.createElement("span");
    colCountEl.className = "count-badge";
    colCountEl.textContent = `${tbl.columns.length} col${tbl.columns.length !== 1 ? "s" : ""}`;
    header.appendChild(colCountEl);

    div.appendChild(header);

    if (tbl.columns.length > 0) {
      const colsEl = document.createElement("div");
      colsEl.className = "parse-columns";
      tbl.columns.forEach(col => {
        const span = document.createElement("span");
        span.textContent = col;
        colsEl.appendChild(span);
      });
      div.appendChild(colsEl);
    } else {
      const none = document.createElement("p");
      none.className = "muted";
      none.style.marginTop = "0.3rem";
      none.textContent = "No column references detected.";
      div.appendChild(none);
    }

    parseResultsList.appendChild(div);
  });

  parseResults.style.display = "block";
}

// ---------------------------------------------------------------------------
// API calls
// ---------------------------------------------------------------------------

/** GET /api/reports — returns { reports: [...] } */
async function fetchAllReports() {
  const res = await fetch("/api/reports");
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  const data = await res.json();
  return data.reports || [];
}

/** GET /api/reports/{report_name} — returns report detail or null on 404 */
async function fetchReportByName(reportName) {
  const res = await fetch(`/api/reports/${encodeURIComponent(reportName)}`);
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return res.json();
}

/** GET /api/tables/{table_name} */
async function loadTable(tableName) {
  const res = await fetch(`/api/tables/${encodeURIComponent(tableName)}`);
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  return res.json();
}

async function deleteTable(tableName) {
  const res = await fetch(`/api/tables/delete/${encodeURIComponent(tableName)}`);
  if (!res.ok) throw new Error(err.detail || `Server error: ${res.status}`);
  return res.json();
}

/** POST /api/tables — create or retrieve table, link to current report */
async function ensureTable(tableName) {
  const res = await fetch("/api/tables", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ report_name: currentReportName, table_name: tableName }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.detail || `Server error: ${res.status}`);
  }
  return res.json();
}

/** POST /api/tables/{table_name}/columns/bulk */
async function saveColumns(tableName, columns) {
  const res = await fetch(`/api/tables/${encodeURIComponent(tableName)}/columns/bulk`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ report_name: currentReportName, columns }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.detail || `Server error: ${res.status}`);
  }
  return res.json();
}

/** GET /api/tables */
async function fetchAllTables() {
  const res = await fetch("/api/tables");
  if (!res.ok) throw new Error(`Server error: ${res.status}`);
  const data = await res.json();
  return data.tables || [];
}

/** POST /api/parse-sql — parses and persists in one call */
async function parseSqlApi(reportName, sql) {
  const res = await fetch("/api/parse-sql", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ report_name: reportName, sql }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.detail || `Server error: ${res.status}`);
  }
  return res.json();
}

// ---------------------------------------------------------------------------
// Event handlers
// ---------------------------------------------------------------------------

/** Report name input: update state and button availability on every keystroke. */
reportNameInput.addEventListener("input", () => {
  currentReportName = reportNameInput.value.trim();
  updateButtonStates();
  if (!currentReportName) {
    reportUsageSection.style.display = "none";
  }
});

/** "Load Report" button. */
loadReportBtn.addEventListener("click", async () => {
  const reportName = reportNameInput.value.trim();
  if (!reportName) {
    reportMessageArea.innerHTML = '<div class="msg-error">Please enter a report name.</div>';
    return;
  }

  currentReportName = reportName;
  updateButtonStates();

  loadReportBtn.disabled  = true;
  loadReportBtn.textContent = "Loading…";
  reportMessageArea.innerHTML = "";

  try {
    const report = await fetchReportByName(reportName);
    if (report) {
      renderReportUsage(report);
    } else {
      reportUsageTitle.textContent = `Report: ${reportName}`;
      reportUsageList.innerHTML    = '<p class="no-tables-msg">New report — no data saved yet.</p>';
      reportUsageSection.style.display = "block";
    }
    // Refresh datalist in case this is a new report name
    const reports = await fetchAllReports();
    populateReportSuggestions(reports);
  } catch (err) {
    reportMessageArea.innerHTML = `<div class="msg-error">${escapeHtml(err.message)}</div>`;
  } finally {
    loadReportBtn.disabled    = false;
    loadReportBtn.textContent = "Load Report";
  }
});

reportNameInput.addEventListener("keydown", e => {
  if (e.key === "Enter") loadReportBtn.click();
});

/** "Load Table" button. */
loadBtn.addEventListener("click", async () => {
  const tableName = tableNameInput.value.trim();
  if (!tableName) {
    alert("Please enter a table name.");
    return;
  }

  loadBtn.disabled  = true;
  loadBtn.textContent = "Loading…";

  try {
    const data = await loadTable(tableName);
    tablePicker.hidden = true;
    currentTableName = data.table_name || tableName;

    tableInfoSection.style.display  = "block";
    addColumnsSection.style.display = "block";
    tableTitle.textContent = currentTableName;

    if (data.exists) {
      tableBadge.textContent = "Existing Table";
      tableBadge.className   = "badge badge-existing";
    } else {
      tableBadge.textContent = "New Table";
      tableBadge.className   = "badge badge-new";
    }

    renderColumnList(data.columns || []);
    messageArea.innerHTML = "";
  } catch (err) {
    alert(err.message);
  } finally {
    loadBtn.disabled  = false;
    loadBtn.textContent = "Load Table";
  }
});

deleteBtn.addEventListener("click", async () => {
  const tableName = tableNameInput.value.trim();
  if (!tableName) {
    alert("Please enter a table name before deletion");
    return;
  }

  deleteBtn.disabled = true;
  deleteBtn.textContent = "Loading...";

  try {
    const data = await deleteTable(tableName);
    alert(`Table "${tableName}" deleted successfully.`);
  } catch (err) {
    alert(err.message);
  } finally {
    deleteBtn.disabled = false;
    deleteBtn.textContent = "Delete Table";
  }
});

tableNameInput.addEventListener("keydown", e => {
  if (e.key === "Enter") loadBtn.click();
});

tableNameInput.addEventListener("focus", () => {
  tablePicker.hidden = false;
  positionTablePicker();
  populateTablePicker(currentTableList);
});

tableNameInput.addEventListener("input", () => {
  tablePicker.hidden = false;
  // TODO: filter table picker options based on input value
  positionTablePicker();
});

window.addEventListener("resize", positionTablePicker);
window.addEventListener("scroll", positionTablePicker, true)

tablePicker.addEventListener("mousedown", (e) => {
  const item =  e.target.closest(".item");
  if (!item) return;

  tableNameInput.value = item.textContent;
  tablePicker.hidden = true;
});

/** "Save Columns" button. */
saveBtn.addEventListener("click", async () => {
  if (!currentReportName) {
    showMessage("Report name is required before saving table or column usage.", "error");
    return;
  }

  const columns = parseColumns(columnsInput.value);
  if (columns.length === 0) {
    showMessage("Please enter at least one column name.", "error");
    return;
  }

  if (!currentTableName) {
    showMessage("No table selected. Use 'Load Table' first.", "error");
    return;
  }

  saveBtn.disabled  = true;
  saveBtn.textContent = "Saving…";

  try {
    const data = await saveColumns(currentTableName, columns);

    tableBadge.textContent = "Existing Table";
    tableBadge.className   = "badge badge-existing";
    renderColumnList(data.columns || []);
    columnsInput.value = "";
    showMessage(
      `Saved ${columns.length} column(s) to "${currentTableName}" under "${currentReportName}".`,
      "success"
    );

    // Refresh all-tables and report usage panels
    const [allTables, report] = await Promise.all([
      fetchAllTables(),
      fetchReportByName(currentReportName),
    ]);
    renderAllTables(allTables);
    if (report) renderReportUsage(report);
  } catch (err) {
    showMessage(err.message, "error");
  } finally {
    saveBtn.disabled  = !currentReportName;
    saveBtn.textContent = "Save Columns";
  }
});

/** "Clear" button for the columns textarea. */
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

/** "Parse and Load" button. */
parseBtn.addEventListener("click", async () => {
  if (!currentReportName) {
    showParseMessage("Report name is required before parsing and saving SQL.", "error");
    return;
  }

  const sql = sqlInput.value.trim();
  if (!sql) {
    showParseMessage("Please paste some SQL before parsing.", "error");
    return;
  }

  parseBtn.disabled   = true;
  parseBtn.textContent = "Parsing…";
  parseMessageArea.innerHTML = "";
  parseResults.style.display = "none";

  try {
    const data = await parseSqlApi(currentReportName, sql);
    renderParseResults(data);

    if (!data.tables || data.tables.length === 0) {
      showParseMessage("Parsing complete — no p21 tables found to save.", "error");
    } else {
      showParseMessage(
        `Parsed and saved ${data.tables.length} table(s) under "${currentReportName}".`,
        "success"
      );
      // Refresh all-tables and report usage panels
      const [allTables, report] = await Promise.all([
        fetchAllTables(),
        fetchReportByName(currentReportName),
      ]);
      renderAllTables(allTables);
      if (report) renderReportUsage(report);
    }
  } catch (err) {
    showParseMessage(err.message, "error");
  } finally {
    parseBtn.disabled   = !currentReportName;
    parseBtn.textContent = "Parse and Load";
  }
});

/** "Clear" button for the SQL textarea. */
clearSqlBtn.addEventListener("click", () => {
  sqlInput.value = "";
  parseMessageArea.innerHTML = "";
  parseResults.style.display = "none";
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function populateReportSuggestions(reports) {
  reportSuggestions.innerHTML = "";
  reports.forEach(r => {
    const option = document.createElement("option");
    option.value = r.report_name;
    reportSuggestions.appendChild(option);
  }); 
} 

function populateTablePicker(tables) {
  tablePicker.innerHTML = "";
  tables.forEach(t => {
    const option = document.createElement("option");
    option.value = t.table_name;
    option.classList.add("item");
    option.textContent = t.table_name;
    tablePicker.appendChild(option);
  });
}

function positionTablePicker() {
  const rect = tableNameInput.getBoundingClientRect();

  tablePicker.style.left  = `${rect.left}px`;
  tablePicker.style.top   = `${rect.bottom + 4}px`;
  tablePicker.style.width = `${rect.width}px`;
}

// ---------------------------------------------------------------------------
// Init: load reports + tables on page load
// ---------------------------------------------------------------------------
(async function init() {
  try {
    const reports = await fetchAllReports();
    populateReportSuggestions(reports);
  } catch (err) {
    console.error("Failed to load reports on init:", err);
  }

  try {
    const tables = await fetchAllTables();
    renderAllTables(tables);
    populateTablePicker(tables);
  } catch (err) {
    console.error("Failed to load tables on init:", err);
  }

  updateButtonStates();
})();