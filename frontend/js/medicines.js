// =====================================================================
// FILE        : frontend/js/medicines.js
// WHAT IT DOES: Powers medicines.html: loads and searches the medicine list, adds and
//               edits a medicine, and shows the batches of one medicine.
// DEPENDS ON  : js/api.js and the element ids in medicines.html.
// USED BY     : medicines.html
// =====================================================================

// The medicines currently shown. Kept so that "Edit" can find a medicine without asking the server again.
let currentMedicines = [];

// ---------------------------------------------------------------------
// loadCategories: fills the category drop-down of the form.
// ---------------------------------------------------------------------
async function loadCategories() {
    try {
        const categories = await api.getCategories();
        document.getElementById("categoryId").innerHTML = categories.map(function (category) {
            return '<option value="' + category.category_id + '">' + escapeHtml(category.category_name) + "</option>";
        }).join("");
    } catch (error) {
        showToast(error.message, "error");
    }
}

// ---------------------------------------------------------------------
// loadMedicines: gets the list (optionally filtered) and draws the table.
// ---------------------------------------------------------------------
// Counts the list requests: only the newest answer may be drawn (a slow answer to an older search must not overwrite it).
let listRequestNumber = 0;

async function loadMedicines() {
    const search = document.getElementById("searchBox").value.trim();
    listRequestNumber++;
    const myRequestNumber = listRequestNumber;
    try {
        const medicines = await api.getMedicines(search);
        if (myRequestNumber !== listRequestNumber) {
            return;                                           // a newer search was started: ignore this old answer
        }
        currentMedicines = medicines;
        drawMedicines();
    } catch (error) {
        showToast(error.message, "error");
    }
}

// drawMedicines: builds the table rows from currentMedicines.
function drawMedicines() {
    const body = document.getElementById("medicinesBody");
    document.getElementById("resultCount").textContent = currentMedicines.length + " medicine(s)";
    if (currentMedicines.length === 0) {
        body.innerHTML = '<tr><td colspan="10" class="empty">No medicine found.</td></tr>';
        return;
    }
    body.innerHTML = currentMedicines.map(function (medicine) {
        // Red badge when the sellable stock is below the reorder level, green otherwise.
        const low = medicine.sellable_quantity < medicine.reorder_level;
        const stockBadge = '<span class="badge ' + (low ? "danger" : "success") + '">' + medicine.sellable_quantity + "</span>";
        // If expired units are still on the shelf, remind the user next to the number.
        const expiredNote = medicine.expired_quantity > 0
            ? ' <span class="badge neutral" title="Units in expired batches">+' + medicine.expired_quantity + " expired</span>"
            : "";
        return "<tr>" +
            "<td><strong>" + escapeHtml(medicine.medicine_name) + "</strong><br><span class=\"subtitle\">" + escapeHtml(medicine.generic_name) + "</span></td>" +
            "<td>" + escapeHtml(medicine.category_name) + "</td>" +
            "<td>" + escapeHtml(medicine.manufacturer) + "</td>" +
            "<td>" + (medicine.requires_prescription ? '<span class="badge info">Rx</span>' : "") + "</td>" +
            '<td class="num">' + medicine.gst_percent + "</td>" +
            '<td class="num">' + stockBadge + expiredNote + "</td>" +
            '<td class="num">' + medicine.reorder_level + "</td>" +
            '<td class="num">' + (medicine.current_price === null ? "-" : formatMoney(medicine.current_price)) + "</td>" +
            "<td>" + escapeHtml(formatDate(medicine.next_expiry_date)) + "</td>" +
            // data-... attributes carry the medicine id to the click handler below.
            '<td style="white-space:nowrap">' +
                '<button class="btn btn-secondary btn-small" data-action="batches" data-id="' + medicine.medicine_id + '">Batches</button> ' +
                '<button class="btn btn-secondary btn-small" data-action="edit" data-id="' + medicine.medicine_id + '">Edit</button>' +
            "</td>" +
            "</tr>";
    }).join("");
}

// ---------------------------------------------------------------------
// The add / edit form
// ---------------------------------------------------------------------

// openForm: shows the form. With a medicine object it is an edit; without one it is "add".
function openForm(medicine) {
    document.getElementById("formCard").classList.remove("hidden");           // show the card
    document.getElementById("formTitle").textContent = medicine ? "Edit medicine" : "Add medicine";
    document.getElementById("medicineId").value = medicine ? medicine.medicine_id : "";
    document.getElementById("medicineName").value = medicine ? medicine.medicine_name : "";
    document.getElementById("genericName").value = medicine ? medicine.generic_name : "";
    document.getElementById("manufacturer").value = medicine ? medicine.manufacturer : "";
    document.getElementById("categoryId").value = medicine ? medicine.category_id : document.getElementById("categoryId").options[0].value;
    document.getElementById("reorderLevel").value = medicine ? medicine.reorder_level : 10;
    document.getElementById("gstPercent").value = medicine ? medicine.gst_percent : 5;
    document.getElementById("requiresPrescription").checked = medicine ? medicine.requires_prescription : false;
    document.getElementById("medicineName").focus();                          // put the cursor in the first field
}

// closeForm: hides the form again.
function closeForm() {
    document.getElementById("formCard").classList.add("hidden");
}

// Submit of the form: add or update, depending on whether the hidden id field is filled.
document.getElementById("medicineForm").addEventListener("submit", async function (event) {
    event.preventDefault();                                   // stop the browser from reloading the page
    // Collect the field values into the object the backend expects (names must match MedicineIn in routes/medicines.py).
    const medicine = {
        medicine_name: document.getElementById("medicineName").value.trim(),
        generic_name: document.getElementById("genericName").value.trim(),
        manufacturer: document.getElementById("manufacturer").value.trim(),
        category_id: Number(document.getElementById("categoryId").value),
        reorder_level: Number(document.getElementById("reorderLevel").value),
        requires_prescription: document.getElementById("requiresPrescription").checked,
        gst_percent: Number(document.getElementById("gstPercent").value)
    };
    const medicineId = document.getElementById("medicineId").value;
    try {
        if (medicineId) {
            await api.updateMedicine(medicineId, medicine);   // PUT /medicines/{id}
            showToast("Medicine updated");
        } else {
            await api.addMedicine(medicine);                  // POST /medicines
            showToast("Medicine added");
        }
        closeForm();
        loadMedicines();                                      // refresh the table
    } catch (error) {
        showToast(error.message, "error");                    // e.g. "This medicine from this manufacturer already exists."
    }
});

document.getElementById("showFormButton").addEventListener("click", function () { openForm(null); });
document.getElementById("cancelFormButton").addEventListener("click", closeForm);

// ---------------------------------------------------------------------
// Buttons inside the table ("Edit" and "Batches") - one listener for all rows.
// ---------------------------------------------------------------------
document.getElementById("medicinesBody").addEventListener("click", async function (event) {
    const button = event.target.closest("button[data-action]");
    if (!button) {
        return;
    }
    const medicineId = Number(button.dataset.id);
    // Find the medicine object that belongs to the clicked row.
    const medicine = currentMedicines.find(function (item) { return item.medicine_id === medicineId; });

    if (button.dataset.action === "edit") {
        openForm(medicine);
        window.scrollTo({ top: 0, behavior: "smooth" });      // scroll up to the form
    } else if (button.dataset.action === "batches") {
        showBatches(medicine);
    }
});

// showBatches: loads and draws the batches of one medicine in the lower card.
async function showBatches(medicine) {
    try {
        const batches = await api.getBatches(medicine.medicine_id);
        document.getElementById("batchesTitle").textContent = "Batches of " + medicine.medicine_name;
        const body = document.getElementById("batchesBody");
        if (batches.length === 0) {
            body.innerHTML = '<tr><td colspan="9" class="empty">No batch has been purchased yet.</td></tr>';
        } else {
            body.innerHTML = batches.map(function (batch) {
                return "<tr>" +
                    '<td class="nowrap">' + escapeHtml(batch.batch_no) + "</td>" +
                    "<td>" + escapeHtml(batch.supplier_name) + "</td>" +
                    "<td>" + escapeHtml(formatDate(batch.manufacture_date)) + "</td>" +
                    "<td>" + escapeHtml(formatDate(batch.expiry_date)) + "</td>" +
                    '<td class="num">' + batch.days_left + "</td>" +
                    "<td>" + badgeForExpiry(batch.expiry_status) + "</td>" +
                    '<td class="num">' + formatMoney(batch.cost_price) + "</td>" +
                    '<td class="num">' + formatMoney(batch.selling_price) + "</td>" +
                    '<td class="num">' + batch.quantity_in_stock + "</td>" +
                    "</tr>";
            }).join("");
        }
        document.getElementById("batchesCard").classList.remove("hidden");
        document.getElementById("batchesCard").scrollIntoView({ behavior: "smooth" });
    } catch (error) {
        showToast(error.message, "error");
    }
}

document.getElementById("closeBatchesButton").addEventListener("click", function () {
    document.getElementById("batchesCard").classList.add("hidden");
});

// ---------------------------------------------------------------------
// Search: reload the list while the user types, but wait 300 ms after the last key
// so we do not send a request for every single letter ("debouncing").
// ---------------------------------------------------------------------
let searchTimer = null;
document.getElementById("searchBox").addEventListener("input", function () {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(loadMedicines, 300);
});

// Start: load the categories (for the form) and the medicine list.
loadCategories();
loadMedicines();
