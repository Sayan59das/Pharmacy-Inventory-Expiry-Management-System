// =====================================================================
// FILE        : frontend/js/api.js
// WHAT IT DOES: The ONE place where the website talks to the backend.
//               Every fetch() call lives here, wrapped in a small function
//               like api.getDashboard(). It also holds a few tiny helpers
//               used by all pages (money format, escaping text, pop-up messages).
// DEPENDS ON  : the running backend (http://127.0.0.1:8000) - see backend/main.py.
// USED BY     : every page. Each .html file loads api.js FIRST, then its own js file.
//
// THE JOURNEY OF ONE CLICK (viva question):
//   button click -> page js file (e.g. sale.js) -> api.js (fetch) -> FastAPI route (routes/sales.py)
//   -> db.py (opens the MySQL connection) -> MySQL procedure/view -> the answer travels back
//   the same way -> the page js file draws it on the screen.
// =====================================================================

// The address where the backend (FastAPI) is running. Change it if you start uvicorn on another port.
const API_BASE = "http://127.0.0.1:8000";


// ---------------------------------------------------------------------
// apiRequest: sends ONE request to the backend and returns the answer as a JavaScript object.
//   method : "GET", "POST" or "PUT"
//   path   : the URL part after the address, e.g. "/medicines"
//   body   : (optional) a JavaScript object that is sent as JSON
// If the backend answers with an error, an Error is thrown carrying the backend's message
// (for example "Insufficient stock for Azithromycin 250mg: requested 31, sellable 30").
// ---------------------------------------------------------------------
async function apiRequest(method, path, body) {
    // Settings for fetch(): the method and the kind of data we send.
    const options = { method: method, headers: { "Content-Type": "application/json" } };
    // Only requests with a body (POST/PUT) carry JSON text.
    if (body !== undefined) {
        options.body = JSON.stringify(body);
    }

    let response;
    try {
        // fetch() contacts the server; "await" waits for the answer without freezing the page.
        response = await fetch(API_BASE + path, options);
    } catch (networkError) {
        // fetch itself failed: the server is off or unreachable.
        throw new Error("Cannot reach the server at " + API_BASE + ". Is the backend running? (uvicorn main:app --reload)");
    }

    // Read the answer text and try to turn it into an object.
    const text = await response.text();
    let data = null;
    try {
        data = text ? JSON.parse(text) : null;
    } catch (parseError) {
        data = null;
    }

    // HTTP status 200-299 means success.
    if (response.ok) {
        return data;
    }

    // Otherwise build a readable message from the backend's {"detail": ...} answer.
    let message = "Request failed (" + response.status + ")";
    if (data && typeof data.detail === "string") {
        message = data.detail;                                   // our own clear messages
    } else if (data && Array.isArray(data.detail)) {
        // FastAPI's validation errors (status 422) come as a list; show the first problems.
        message = data.detail
            .map(function (item) { return (item.loc ? item.loc.slice(1).join(".") + ": " : "") + item.msg; })
            .join("; ");
    }
    throw new Error(message);
}


// ---------------------------------------------------------------------
// The api object: one function per backend URL. The page files only use these names.
// ---------------------------------------------------------------------
const api = {
    // ----- dashboard and reports -----
    getDashboard:       function () { return apiRequest("GET", "/reports/dashboard"); },
    getMonthlySales:    function (month, year) { return apiRequest("GET", "/reports/monthly-sales?month=" + month + "&year=" + year); },
    getTopSelling:      function (limit) { return apiRequest("GET", "/reports/top-selling?limit=" + limit); },
    getExpiringSoon:    function () { return apiRequest("GET", "/reports/expiring-soon"); },
    getExpired:         function () { return apiRequest("GET", "/reports/expired"); },
    getLowStock:        function () { return apiRequest("GET", "/reports/low-stock"); },
    getSupplierSummary: function () { return apiRequest("GET", "/reports/supplier-summary"); },

    // ----- alerts -----
    getAlerts:          function () { return apiRequest("GET", "/alerts"); },
    resolveAlert:       function (alertId) { return apiRequest("POST", "/alerts/" + alertId + "/resolve"); },
    refreshAlerts:      function () { return apiRequest("POST", "/alerts/refresh"); },

    // ----- medicines -----
    getCategories:      function () { return apiRequest("GET", "/medicines/categories"); },
    getMedicines:       function (search) { return apiRequest("GET", "/medicines" + (search ? "?search=" + encodeURIComponent(search) : "")); },
    getBatches:         function (medicineId) { return apiRequest("GET", "/medicines/" + medicineId + "/batches"); },
    addMedicine:        function (medicine) { return apiRequest("POST", "/medicines", medicine); },
    updateMedicine:     function (medicineId, medicine) { return apiRequest("PUT", "/medicines/" + medicineId, medicine); },

    // ----- suppliers and purchases -----
    getSuppliers:       function () { return apiRequest("GET", "/suppliers"); },
    addSupplier:        function (supplier) { return apiRequest("POST", "/suppliers", supplier); },
    getPurchases:       function () { return apiRequest("GET", "/purchases"); },
    addPurchase:        function (purchase) { return apiRequest("POST", "/purchases", purchase); },

    // ----- sales and billing -----
    getCustomers:       function () { return apiRequest("GET", "/sales/customers"); },
    addCustomer:        function (customer) { return apiRequest("POST", "/sales/customers", customer); },
    makeSale:           function (sale) { return apiRequest("POST", "/sales", sale); },
    getBill:            function (saleId) { return apiRequest("GET", "/sales/" + saleId + "/bill"); },
    getSales:           function () { return apiRequest("GET", "/sales"); }
};


// ---------------------------------------------------------------------
// Small helpers used by all pages
// ---------------------------------------------------------------------

// escapeHtml: makes text safe to put inside HTML. Without it, a medicine named
// "<script>..." would run as code on the page (an XSS attack).
function escapeHtml(value) {
    if (value === null || value === undefined) {
        return "";                                    // show nothing for empty values
    }
    return String(value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

// formatMoney: 1234.5 -> "₹1,234.50" (Indian digit grouping). ₹ is the rupee sign.
function formatMoney(value) {
    const number = Number(value || 0);
    return "₹" + number.toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// formatDate: "2026-11-30" -> "30 Nov 2026". Works for "2026-11-30T10:15:00" too.
function formatDate(value) {
    if (!value) {
        return "";
    }
    const date = new Date(String(value).substring(0, 10) + "T00:00:00");   // read only the date part
    return date.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

// formatDateTime: "2026-11-12T10:15:00" -> "12 Nov 2026, 10:15 am"
function formatDateTime(value) {
    if (!value) {
        return "";
    }
    const date = new Date(value);
    return date.toLocaleString("en-IN", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

// todayAsIso: today's date as "YYYY-MM-DD" (the format of <input type="date">), using the computer's local date.
function todayAsIso() {
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, "0");    // getMonth() starts at 0, padStart makes "5" into "05"
    const day = String(now.getDate()).padStart(2, "0");
    return now.getFullYear() + "-" + month + "-" + day;
}

// showToast: a small message in the top-right corner that disappears after a few seconds.
//   type = "success" (green, default) or "error" (red)
function showToast(message, type) {
    // Find the box that holds the messages, or create it the first time.
    let box = document.getElementById("toastBox");
    if (!box) {
        box = document.createElement("div");
        box.id = "toastBox";
        document.body.appendChild(box);
    }
    const toast = document.createElement("div");
    toast.className = "toast" + (type === "error" ? " error" : "");
    toast.textContent = message;                                  // textContent is safe: it never runs HTML
    box.appendChild(toast);
    // Errors stay a little longer so they can be read.
    setTimeout(function () { toast.remove(); }, type === "error" ? 7000 : 3500);
}

// badgeForExpiry: the coloured label for a batch's expiry status.
function badgeForExpiry(status) {
    if (status === "EXPIRED") {
        return '<span class="badge danger">Expired</span>';
    }
    if (status === "NEAR_EXPIRY") {
        return '<span class="badge warning">Near expiry</span>';
    }
    return '<span class="badge success">OK</span>';
}

// badgeForAlert: the coloured label for an alert type.
function badgeForAlert(type) {
    if (type === "EXPIRED") {
        return '<span class="badge danger">Expired</span>';
    }
    if (type === "NEAR_EXPIRY") {
        return '<span class="badge warning">Near expiry</span>';
    }
    return '<span class="badge info">Low stock</span>';
}
