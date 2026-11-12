// =====================================================================
// FILE        : frontend/js/dashboard.js
// WHAT IT DOES: Fills the dashboard (index.html): the six number cards, the open
//               alerts table, the low-stock and expiring-soon tables, and handles
//               the "Resolve" buttons and the "Refresh alerts" button.
// DEPENDS ON  : js/api.js (api.* functions and helpers) and the element ids in index.html.
// USED BY     : index.html
// =====================================================================

// ---------------------------------------------------------------------
// loadDashboard: asks the backend for everything the page shows and draws it.
// ---------------------------------------------------------------------
async function loadDashboard() {
    try {
        // Promise.all starts all four requests at the same time and waits until all have arrived.
        const results = await Promise.all([
            api.getDashboard(),
            api.getAlerts(),
            api.getLowStock(),
            api.getExpiringSoon()
        ]);
        // Give the four answers readable names.
        const summary = results[0];
        const alerts = results[1];
        const lowStock = results[2];
        const expiring = results[3];

        drawCards(summary);
        drawAlerts(alerts);
        drawLowStock(lowStock);
        drawExpiring(expiring);
    } catch (error) {
        // Any failure (server off, database error ...) is shown as a red message.
        showToast(error.message, "error");
    }
}

// drawCards: writes the numbers into the six cards.
function drawCards(summary) {
    document.getElementById("statLowStock").textContent = summary.low_stock_count;
    document.getElementById("statNearExpiry").textContent = summary.near_expiry_count;
    document.getElementById("statExpired").textContent = summary.expired_count;
    document.getElementById("statOpenAlerts").textContent = summary.open_alerts;
    document.getElementById("statMedicines").textContent = summary.total_medicines;
    document.getElementById("statTodaySales").textContent = formatMoney(summary.todays_sales);
}

// drawAlerts: builds the rows of the "Open alerts" table.
function drawAlerts(alerts) {
    const body = document.getElementById("alertsBody");
    // No alerts: show a friendly message instead of an empty table.
    if (alerts.length === 0) {
        body.innerHTML = '<tr><td colspan="6" class="empty">No open alerts. Everything is fine.</td></tr>';
        return;
    }
    // map() turns every alert object into a piece of HTML; join("") glues the pieces together.
    body.innerHTML = alerts.map(function (alert) {
        return "<tr>" +
            "<td>" + badgeForAlert(alert.alert_type) + "</td>" +
            "<td>" + escapeHtml(alert.medicine_name) + "</td>" +
            '<td class="nowrap">' + escapeHtml(alert.batch_no || "-") + "</td>" +
            "<td>" + escapeHtml(alert.message) + "</td>" +
            '<td class="nowrap">' + escapeHtml(formatDateTime(alert.created_at)) + "</td>" +
            // data-alert-id stores the alert number on the button so the click handler can read it.
            '<td><button class="btn btn-secondary btn-small" data-alert-id="' + alert.alert_id + '">Resolve</button></td>' +
            "</tr>";
    }).join("");
}

// drawLowStock: the small low-stock table.
function drawLowStock(rows) {
    const body = document.getElementById("lowStockBody");
    if (rows.length === 0) {
        body.innerHTML = '<tr><td colspan="3" class="empty">No medicine is below its reorder level.</td></tr>';
        return;
    }
    body.innerHTML = rows.map(function (row) {
        return "<tr>" +
            "<td>" + escapeHtml(row.medicine_name) + "</td>" +
            '<td class="num"><span class="badge ' + (row.sellable_quantity === 0 ? "danger" : "warning") + '">' + row.sellable_quantity + "</span></td>" +
            '<td class="num">' + row.reorder_level + "</td>" +
            "</tr>";
    }).join("");
}

// drawExpiring: the small expiring-soon table.
function drawExpiring(rows) {
    const body = document.getElementById("expiringBody");
    if (rows.length === 0) {
        body.innerHTML = '<tr><td colspan="4" class="empty">Nothing expires in the next 30 days.</td></tr>';
        return;
    }
    body.innerHTML = rows.map(function (row) {
        return "<tr>" +
            "<td>" + escapeHtml(row.medicine_name) + "</td>" +
            '<td class="nowrap">' + escapeHtml(row.batch_no) + "</td>" +
            '<td class="num">' + row.days_left + "</td>" +
            '<td class="num">' + row.quantity_in_stock + "</td>" +
            "</tr>";
    }).join("");
}

// ---------------------------------------------------------------------
// Click on a "Resolve" button. One listener on the table body handles all buttons
// ("event delegation"), because the buttons are created later by drawAlerts.
// ---------------------------------------------------------------------
document.getElementById("alertsBody").addEventListener("click", async function (event) {
    // Did the click land on a button that carries an alert number?
    const button = event.target.closest("button[data-alert-id]");
    if (!button) {
        return;                                          // clicked somewhere else
    }
    button.disabled = true;                              // prevent a double click
    try {
        await api.resolveAlert(button.dataset.alertId);  // POST /alerts/{id}/resolve -> MySQL sp_resolve_alert
        showToast("Alert resolved");
        loadDashboard();                                 // redraw everything with the new numbers
    } catch (error) {
        showToast(error.message, "error");
        button.disabled = false;
    }
});

// ---------------------------------------------------------------------
// Click on "Refresh alerts": runs the two alert procedures right now.
// ---------------------------------------------------------------------
document.getElementById("refreshAlertsButton").addEventListener("click", async function () {
    try {
        const result = await api.refreshAlerts();        // POST /alerts/refresh
        const added = (result.expiry.near_expiry_alerts_added || 0) +
                      (result.expiry.expired_alerts_added || 0) +
                      (result.low_stock.low_stock_alerts_added || 0);
        showToast("Alerts refreshed: " + added + " new alert(s)");
        loadDashboard();
    } catch (error) {
        showToast(error.message, "error");
    }
});

// Draw the dashboard as soon as the page has loaded.
loadDashboard();
