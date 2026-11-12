// =====================================================================
// FILE        : frontend/src/api.js
// WHAT IT DOES: The ONE place where the website talks to the backend. Every
//               fetch() call lives here, wrapped in a small named function such
//               as api.getDashboard(). Pages never call fetch() themselves.
// DEPENDS ON  : the running FastAPI backend (default http://127.0.0.1:8000).
// USED BY     : every page in src/pages/ and components/Layout.jsx.
// READ ORDER  : read it right after App.jsx.
//
// THE JOURNEY OF ONE CLICK (viva question):
//   button click -> page component (e.g. pages/Sale.jsx) -> api.js (fetch)
//   -> FastAPI route (backend/routes/sales.py) -> db.py (MySQL connection)
//   -> MySQL procedure / view -> the answer travels back the same way
//   -> React stores it in state and re-draws the page.
// =====================================================================

// The backend address. import.meta.env.VITE_API_URL comes from an optional frontend/.env file;
// when that file does not exist we use the default address.
export const API_BASE = import.meta.env.VITE_API_URL || "http://127.0.0.1:8000";

// ---------------------------------------------------------------------
// apiRequest: sends ONE request and returns the answer as a JavaScript object.
//   method : "GET", "POST" or "PUT"
//   path   : the part after the address, e.g. "/medicines"
//   body   : (optional) an object that is sent as JSON
// If the backend answers with an error, an Error is thrown whose message is the
// backend's own text - for MySQL refusals that is the SIGNAL message, e.g.
// "Insufficient stock for Azithromycin 250mg: requested 31, sellable 30".
// ---------------------------------------------------------------------
async function apiRequest(method, path, body) {
    // Settings for fetch: the method, and that we send JSON.
    const options = { method: method, headers: { "Content-Type": "application/json" } };
    // Only POST/PUT requests carry a body.
    if (body !== undefined) {
        options.body = JSON.stringify(body);
    }

    let response;
    try {
        // fetch contacts the server; await waits for the answer without freezing the page.
        response = await fetch(API_BASE + path, options);
    } catch {
        // fetch itself failed: the backend is not running or not reachable.
        throw new Error("Cannot reach the backend at " + API_BASE + ". Start it with: uvicorn main:app --reload");
    }

    // Read the answer as text and try to turn it into an object.
    const text = await response.text();
    let data = null;
    try {
        data = text ? JSON.parse(text) : null;
    } catch {
        data = null;
    }

    // Status 200-299 means success: hand the data back to the page.
    if (response.ok) {
        return data;
    }

    // Otherwise build a readable message from the backend's {"detail": ...} answer.
    let message = "Request failed (HTTP " + response.status + ")";
    if (data && typeof data.detail === "string") {
        // Our own clear messages (including MySQL SIGNAL texts).
        message = data.detail;
    } else if (data && Array.isArray(data.detail)) {
        // FastAPI form-validation errors (status 422) arrive as a list; join them into one sentence.
        message = data.detail
            .map((item) => (item.loc ? item.loc.slice(1).join(".") + ": " : "") + item.msg)
            .join("; ");
    }
    throw new Error(message);
}

// ---------------------------------------------------------------------
// The api object: one function per backend URL. Pages only use these names.
// ---------------------------------------------------------------------
export const api = {
    // ----- health check (is the backend + MySQL alive?) -----
    getHealth: () => apiRequest("GET", "/health"),

    // ----- dashboard and reports (views + one procedure) -----
    getDashboard: () => apiRequest("GET", "/reports/dashboard"),
    getMonthlySales: (month, year) => apiRequest("GET", "/reports/monthly-sales?month=" + month + "&year=" + year),
    getTopSelling: (limit) => apiRequest("GET", "/reports/top-selling?limit=" + limit),
    getExpiringSoon: () => apiRequest("GET", "/reports/expiring-soon"),
    getExpired: () => apiRequest("GET", "/reports/expired"),
    getLowStock: () => apiRequest("GET", "/reports/low-stock"),
    getSupplierSummary: () => apiRequest("GET", "/reports/supplier-summary"),

    // ----- alerts -----
    getAlerts: () => apiRequest("GET", "/alerts"),
    resolveAlert: (alertId) => apiRequest("POST", "/alerts/" + alertId + "/resolve"),
    refreshAlerts: () => apiRequest("POST", "/alerts/refresh"),

    // ----- medicines -----
    getCategories: () => apiRequest("GET", "/medicines/categories"),
    // encodeURIComponent makes the search text safe inside a URL (spaces, & and so on).
    getMedicines: (search) => apiRequest("GET", "/medicines" + (search ? "?search=" + encodeURIComponent(search) : "")),
    getBatches: (medicineId) => apiRequest("GET", "/medicines/" + medicineId + "/batches"),
    addMedicine: (medicine) => apiRequest("POST", "/medicines", medicine),
    updateMedicine: (medicineId, medicine) => apiRequest("PUT", "/medicines/" + medicineId, medicine),

    // ----- suppliers and purchases -----
    getSuppliers: () => apiRequest("GET", "/suppliers"),
    addSupplier: (supplier) => apiRequest("POST", "/suppliers", supplier),
    getPurchases: () => apiRequest("GET", "/purchases"),
    addPurchase: (purchase) => apiRequest("POST", "/purchases", purchase),

    // ----- sales and billing -----
    getCustomers: () => apiRequest("GET", "/sales/customers"),
    addCustomer: (customer) => apiRequest("POST", "/sales/customers", customer),
    makeSale: (sale) => apiRequest("POST", "/sales", sale),
    getBill: (saleId) => apiRequest("GET", "/sales/" + saleId + "/bill"),
    getSales: () => apiRequest("GET", "/sales"),
};
