// =====================================================================
// FILE        : frontend/js/reports.js
// WHAT IT DOES: Powers reports.html: switches between the six report tabs and loads each
//               report from the backend the first time it is opened.
// DEPENDS ON  : js/api.js and the element ids in reports.html.
// USED BY     : reports.html
// =====================================================================

// ---------------------------------------------------------------------
// Small helper: fill a table body with rows, or a message when there are none.
//   bodyId   : id of the <tbody>
//   columns  : number of columns (for the "empty" message)
//   rows     : list of data objects
//   rowMaker : a function that turns ONE data object into the HTML of one row
// ---------------------------------------------------------------------
function fillTable(bodyId, columns, rows, rowMaker) {
    const body = document.getElementById(bodyId);
    if (rows.length === 0) {
        body.innerHTML = '<tr><td colspan="' + columns + '" class="empty">Nothing to show.</td></tr>';
        return;
    }
    body.innerHTML = rows.map(rowMaker).join("");
}

// ---------------------------------------------------------------------
// One loader function per report.
// ---------------------------------------------------------------------

// Counts the monthly requests. If the user asks for another month before the first answer has
// arrived, only the NEWEST answer may be drawn (otherwise a slow old answer could overwrite it).
let monthlyRequestNumber = 0;

// Report 1: monthly sales (MySQL procedure sp_monthly_sales_report returns 3 result sets).
async function loadMonthly() {
    const month = Number(document.getElementById("monthSelect").value);
    const year = Number(document.getElementById("yearInput").value);
    monthlyRequestNumber++;                                   // this is request number N ...
    const myRequestNumber = monthlyRequestNumber;             // ... remember it
    try {
        const report = await api.getMonthlySales(month, year);
        if (myRequestNumber !== monthlyRequestNumber) {
            return;                                           // a newer request exists: drop this old answer
        }
        const summary = report.summary;

        // The summary numbers as four cards.
        document.getElementById("monthlyCards").innerHTML =
            '<div class="stat info"><div class="stat-value">' + summary.total_bills + '</div><div class="stat-label">Bills</div></div>' +
            '<div class="stat info"><div class="stat-value">' + summary.total_units + '</div><div class="stat-label">Units sold</div></div>' +
            '<div class="stat success"><div class="stat-value">' + formatMoney(summary.total_sales) + '</div><div class="stat-label">Total sales (GST incl.)</div></div>' +
            '<div class="stat warning"><div class="stat-value">' + formatMoney(summary.total_gst_collected) + '</div><div class="stat-label">GST collected</div></div>' +
            '<div class="stat info"><div class="stat-value">' + formatMoney(summary.average_bill_value) + '</div><div class="stat-label">Average bill</div></div>';

        fillTable("monthlyPaymentBody", 3, report.by_payment_mode, function (row) {
            return "<tr><td>" + escapeHtml(row.payment_mode) + '</td><td class="num">' + row.bills + '</td><td class="num">' + formatMoney(row.amount) + "</td></tr>";
        });
        fillTable("monthlyTopBody", 3, report.top_medicines, function (row) {
            return "<tr><td>" + escapeHtml(row.medicine_name) + '</td><td class="num">' + row.units_sold + '</td><td class="num">' + formatMoney(row.revenue) + "</td></tr>";
        });
    } catch (error) {
        showToast(error.message, "error");
    }
}

// Report 2: top-selling medicines (view v_top_selling_medicines).
async function loadTop() {
    try {
        const rows = await api.getTopSelling(15);
        fillTable("topBody", 6, rows, function (row, index) {
            return "<tr><td>" + (index + 1) + "</td><td>" + escapeHtml(row.medicine_name) + "</td><td>" + escapeHtml(row.category_name) +
                '</td><td class="num">' + row.units_sold + '</td><td class="num">' + row.number_of_bills +
                '</td><td class="num">' + formatMoney(row.total_revenue) + "</td></tr>";
        });
    } catch (error) {
        showToast(error.message, "error");
    }
}

// Report 3: expiring soon (view v_expiring_soon).
async function loadExpiring() {
    try {
        const rows = await api.getExpiringSoon();
        fillTable("expiringBody", 7, rows, function (row) {
            return "<tr><td>" + escapeHtml(row.medicine_name) + '</td><td class="nowrap">' + escapeHtml(row.batch_no) + "</td><td>" + escapeHtml(row.supplier_name) +
                "</td><td>" + escapeHtml(formatDate(row.expiry_date)) + '</td><td class="num"><span class="badge warning">' + row.days_left +
                '</span></td><td class="num">' + row.quantity_in_stock + '</td><td class="num">' + formatMoney(row.stock_value_at_cost) + "</td></tr>";
        });
    } catch (error) {
        showToast(error.message, "error");
    }
}

// Report 4: expired stock (view v_expired_stock).
async function loadExpired() {
    try {
        const rows = await api.getExpired();
        fillTable("expiredBody", 7, rows, function (row) {
            return "<tr><td>" + escapeHtml(row.medicine_name) + '</td><td class="nowrap">' + escapeHtml(row.batch_no) + "</td><td>" + escapeHtml(row.supplier_name) +
                "</td><td>" + escapeHtml(formatDate(row.expiry_date)) + '</td><td class="num"><span class="badge danger">' + row.days_since_expiry +
                '</span></td><td class="num">' + row.quantity_in_stock + '</td><td class="num">' + formatMoney(row.loss_value) + "</td></tr>";
        });
    } catch (error) {
        showToast(error.message, "error");
    }
}

// Report 5: low stock (view v_low_stock).
async function loadLow() {
    try {
        const rows = await api.getLowStock();
        fillTable("lowBody", 6, rows, function (row) {
            return "<tr><td>" + escapeHtml(row.medicine_name) + "</td><td>" + escapeHtml(row.category_name) +
                '</td><td class="num"><span class="badge ' + (row.sellable_quantity === 0 ? "danger" : "warning") + '">' + row.sellable_quantity +
                '</span></td><td class="num">' + row.expired_quantity + '</td><td class="num">' + row.reorder_level +
                '</td><td class="num">' + row.shortfall + "</td></tr>";
        });
    } catch (error) {
        showToast(error.message, "error");
    }
}

// Report 6: purchases per supplier (view v_supplier_purchase_summary).
async function loadSuppliers() {
    try {
        const rows = await api.getSupplierSummary();
        fillTable("suppliersBody", 5, rows, function (row) {
            return "<tr><td>" + escapeHtml(row.supplier_name) + '</td><td class="num">' + row.number_of_purchases +
                '</td><td class="num">' + row.total_units_bought + '</td><td class="num">' + formatMoney(row.total_amount_spent) +
                "</td><td>" + escapeHtml(formatDate(row.last_purchase_date) || "-") + "</td></tr>";
        });
    } catch (error) {
        showToast(error.message, "error");
    }
}

// ---------------------------------------------------------------------
// Tabs: which loader belongs to which tab.
// ---------------------------------------------------------------------
const loaders = {
    monthly: loadMonthly,
    top: loadTop,
    expiring: loadExpiring,
    expired: loadExpired,
    low: loadLow,
    suppliers: loadSuppliers
};

// showTab: show one section, hide the others, highlight the button, load the data.
function showTab(name) {
    // Go through every tab button and switch "active" on only for the chosen one.
    document.querySelectorAll(".tab").forEach(function (button) {
        button.classList.toggle("active", button.dataset.tab === name);
    });
    // Same for the sections: show the chosen one, hide the rest.
    Object.keys(loaders).forEach(function (key) {
        document.getElementById("tab-" + key).classList.toggle("hidden", key !== name);
    });
    loaders[name]();                                          // load the report's data
}

// One click listener for all six buttons.
document.querySelector(".tabs").addEventListener("click", function (event) {
    const button = event.target.closest(".tab");
    if (button) {
        showTab(button.dataset.tab);
    }
});

// "Show report" button of the monthly tab.
document.getElementById("loadMonthlyButton").addEventListener("click", loadMonthly);

// ---------------------------------------------------------------------
// Start: fill the month drop-down, default to the current month and year, show the first tab.
// ---------------------------------------------------------------------
const monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
document.getElementById("monthSelect").innerHTML = monthNames.map(function (name, index) {
    return '<option value="' + (index + 1) + '">' + name + "</option>";
}).join("");
document.getElementById("monthSelect").value = new Date().getMonth() + 1;
document.getElementById("yearInput").value = new Date().getFullYear();
showTab("monthly");
