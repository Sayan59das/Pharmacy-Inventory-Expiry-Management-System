// =====================================================================
// FILE        : frontend/js/suppliers.js
// WHAT IT DOES: Powers suppliers.html: loads the supplier list and adds a new supplier.
// DEPENDS ON  : js/api.js and the element ids in suppliers.html.
// USED BY     : suppliers.html
// =====================================================================

// loadSuppliers: asks the backend for the suppliers and draws the table.
async function loadSuppliers() {
    try {
        const suppliers = await api.getSuppliers();               // GET /suppliers
        const body = document.getElementById("suppliersBody");
        if (suppliers.length === 0) {
            body.innerHTML = '<tr><td colspan="7" class="empty">No supplier yet.</td></tr>';
            return;
        }
        body.innerHTML = suppliers.map(function (supplier) {
            return "<tr>" +
                "<td><strong>" + escapeHtml(supplier.supplier_name) + "</strong><br><span class=\"subtitle\">" + escapeHtml(supplier.address || "") + "</span></td>" +
                "<td>" + escapeHtml(supplier.contact_person || "-") + "<br><span class=\"subtitle\">" + escapeHtml(supplier.phone) + "</span></td>" +
                "<td>" + escapeHtml(supplier.gst_no) + "</td>" +
                '<td class="num">' + supplier.number_of_purchases + "</td>" +
                '<td class="num">' + supplier.total_units_bought + "</td>" +
                '<td class="num">' + formatMoney(supplier.total_amount_spent) + "</td>" +
                "<td>" + escapeHtml(formatDate(supplier.last_purchase_date) || "-") + "</td>" +
                "</tr>";
        }).join("");
    } catch (error) {
        showToast(error.message, "error");
    }
}

// Show the form when "Add supplier" is clicked ...
document.getElementById("showFormButton").addEventListener("click", function () {
    document.getElementById("formCard").classList.remove("hidden");
    document.getElementById("supplierName").focus();
});

// ... and hide (and clear) it again on "Cancel".
document.getElementById("cancelFormButton").addEventListener("click", function () {
    document.getElementById("formCard").classList.add("hidden");
    document.getElementById("supplierForm").reset();
});

// Submit: send the new supplier to the backend.
document.getElementById("supplierForm").addEventListener("submit", async function (event) {
    event.preventDefault();                                       // do not reload the page
    // The names on the left must match SupplierIn in routes/suppliers.py.
    const supplier = {
        supplier_name: document.getElementById("supplierName").value.trim(),
        contact_person: document.getElementById("contactPerson").value.trim() || null,   // empty text -> null
        phone: document.getElementById("phone").value.trim(),
        email: document.getElementById("email").value.trim() || null,
        address: document.getElementById("address").value.trim() || null,
        gst_no: document.getElementById("gstNo").value.trim().toUpperCase()
    };
    try {
        await api.addSupplier(supplier);                          // POST /suppliers
        showToast("Supplier added");
        document.getElementById("supplierForm").reset();
        document.getElementById("formCard").classList.add("hidden");
        loadSuppliers();
    } catch (error) {
        showToast(error.message, "error");                        // e.g. "A supplier with this GST number already exists."
    }
});

// Start: load the list.
loadSuppliers();
