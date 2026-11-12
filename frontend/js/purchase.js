// =====================================================================
// FILE        : frontend/js/purchase.js
// WHAT IT DOES: Powers purchase.html: fills the supplier/medicine drop-downs, lets the user
//               add and remove item rows, sends the purchase to the backend and lists the
//               recent purchases.
// DEPENDS ON  : js/api.js and the element ids in purchase.html.
// USED BY     : purchase.html
// =====================================================================

// The medicine list, kept so that every new item row can build its drop-down.
let medicineOptionsHtml = "";

// ---------------------------------------------------------------------
// loadFormData: fills the supplier drop-down and prepares the medicine options.
// ---------------------------------------------------------------------
async function loadFormData() {
    try {
        const results = await Promise.all([api.getSuppliers(), api.getMedicines("")]);
        const suppliers = results[0];
        const medicines = results[1];

        document.getElementById("supplierId").innerHTML = suppliers.map(function (supplier) {
            return '<option value="' + supplier.supplier_id + '">' + escapeHtml(supplier.supplier_name) + "</option>";
        }).join("");

        // Build the <option> list once; every new row reuses this text.
        medicineOptionsHtml = medicines.map(function (medicine) {
            return '<option value="' + medicine.medicine_id + '">' + escapeHtml(medicine.medicine_name) + "</option>";
        }).join("");

        addItemRow();                                             // start with one empty row
    } catch (error) {
        showToast(error.message, "error");
    }
}

// ---------------------------------------------------------------------
// addItemRow: appends one empty item row to the items table.
// ---------------------------------------------------------------------
function addItemRow() {
    const row = document.createElement("tr");
    // The class names (item-medicine, item-batch ...) let us find each field again when submitting.
    row.innerHTML =
        '<td><select class="item-medicine" required>' + medicineOptionsHtml + "</select></td>" +
        '<td><input type="text" class="item-batch" maxlength="30" required placeholder="PCM-26A"></td>' +
        '<td><input type="date" class="item-mfd"></td>' +
        '<td><input type="date" class="item-expiry"></td>' +
        '<td><input type="number" class="item-quantity" min="1" required style="width:90px"></td>' +
        '<td><input type="number" class="item-cost" min="0" step="0.01" required style="width:100px"></td>' +
        '<td><input type="number" class="item-mrp" min="0" step="0.01" style="width:100px"></td>' +
        '<td><button type="button" class="btn btn-danger btn-small" data-remove="1">Remove</button></td>';
    document.getElementById("itemsBody").appendChild(row);
}

document.getElementById("addItemButton").addEventListener("click", addItemRow);

// Click on a "Remove" button: delete that row (but always keep at least one row).
document.getElementById("itemsBody").addEventListener("click", function (event) {
    const button = event.target.closest("button[data-remove]");
    if (!button) {
        return;
    }
    if (document.querySelectorAll("#itemsBody tr").length > 1) {
        button.closest("tr").remove();
    } else {
        showToast("A purchase needs at least one item", "error");
    }
});

// ---------------------------------------------------------------------
// Submit: collect the header and all rows, send them in ONE request.
// ---------------------------------------------------------------------
document.getElementById("purchaseForm").addEventListener("submit", async function (event) {
    event.preventDefault();

    // Read every item row into an object. Names must match PurchaseItemIn in routes/purchases.py.
    const items = [];
    document.querySelectorAll("#itemsBody tr").forEach(function (row) {
        const item = {
            medicine_id: Number(row.querySelector(".item-medicine").value),
            batch_no: row.querySelector(".item-batch").value.trim(),
            quantity: Number(row.querySelector(".item-quantity").value),
            unit_cost: Number(row.querySelector(".item-cost").value)
        };
        // Optional fields are sent only when the user filled them (empty = top-up of an existing batch).
        const mfd = row.querySelector(".item-mfd").value;
        const expiry = row.querySelector(".item-expiry").value;
        const mrp = row.querySelector(".item-mrp").value;
        if (mfd) { item.manufacture_date = mfd; }
        if (expiry) { item.expiry_date = expiry; }
        if (mrp !== "") { item.selling_price = Number(mrp); }
        items.push(item);
    });

    const purchase = {
        supplier_id: Number(document.getElementById("supplierId").value),
        invoice_no: document.getElementById("invoiceNo").value.trim(),
        purchase_date: document.getElementById("purchaseDate").value || null,
        items: items
    };

    try {
        const result = await api.addPurchase(purchase);           // POST /purchases -> MySQL sp_add_purchase
        showToast("Purchase #" + result.purchase_id + " recorded. Stock updated.");
        // Reset the form: clear the header fields and leave one empty item row.
        document.getElementById("invoiceNo").value = "";
        document.getElementById("itemsBody").innerHTML = "";
        addItemRow();
        loadPurchases();
    } catch (error) {
        // If MySQL rejects ANY item, nothing is saved (rollback) and the reason is shown here.
        showToast(error.message, "error");
    }
});

// ---------------------------------------------------------------------
// loadPurchases: the "Recent purchases" table.
// ---------------------------------------------------------------------
async function loadPurchases() {
    try {
        const purchases = await api.getPurchases();               // GET /purchases
        const body = document.getElementById("purchasesBody");
        if (purchases.length === 0) {
            body.innerHTML = '<tr><td colspan="7" class="empty">No purchase yet.</td></tr>';
            return;
        }
        body.innerHTML = purchases.map(function (purchase) {
            return "<tr>" +
                "<td>" + purchase.purchase_id + "</td>" +
                "<td>" + escapeHtml(purchase.invoice_no) + "</td>" +
                "<td>" + escapeHtml(formatDate(purchase.purchase_date)) + "</td>" +
                "<td>" + escapeHtml(purchase.supplier_name) + "</td>" +
                '<td class="num">' + purchase.item_lines + "</td>" +
                '<td class="num">' + purchase.total_units + "</td>" +
                '<td class="num">' + formatMoney(purchase.total_amount) + "</td>" +
                "</tr>";
        }).join("");
    } catch (error) {
        showToast(error.message, "error");
    }
}

// Start: default date = today, load the drop-downs and the recent purchases.
document.getElementById("purchaseDate").value = todayAsIso();
loadFormData();
loadPurchases();
