// =====================================================================
// FILE        : frontend/js/sale.js
// WHAT IT DOES: Powers sale.html: keeps the shopping cart in memory, sends the cart to the
//               backend as ONE bill, draws the bill that MySQL calculated, prints it, and
//               lists the recent bills.
// DEPENDS ON  : js/api.js and the element ids in sale.html.
// USED BY     : sale.html
//
// IMPORTANT: this file does NOT decide which batch is sold, the price or the GST. It only sends
// "medicine X, quantity Y". MySQL does FEFO, checks expiry and stock, and returns the bill.
// =====================================================================

// The medicines available in the drop-down (with stock and price) - loaded from the backend.
let catalog = [];

// The shopping cart: a list of { medicine_id, name, quantity, price }.
let cart = [];

// ---------------------------------------------------------------------
// loadCustomers: fills the customer drop-down (the first option "Walk-in customer" stays).
// ---------------------------------------------------------------------
async function loadCustomers(selectId) {
    try {
        const customers = await api.getCustomers();
        const select = document.getElementById("customerId");
        select.innerHTML = '<option value="">Walk-in customer</option>' + customers.map(function (customer) {
            const label = customer.customer_name + (customer.phone ? " (" + customer.phone + ")" : "");
            return '<option value="' + customer.customer_id + '">' + escapeHtml(label) + "</option>";
        }).join("");
        if (selectId) {
            select.value = selectId;                              // select the customer that was just added
        }
    } catch (error) {
        showToast(error.message, "error");
    }
}

// ---------------------------------------------------------------------
// loadCatalog: fills the medicine drop-down with name, stock and price.
// ---------------------------------------------------------------------
async function loadCatalog() {
    try {
        catalog = await api.getMedicines("");
        document.getElementById("medicineId").innerHTML = catalog.map(function (medicine) {
            const outOfStock = medicine.sellable_quantity <= 0;
            const label = medicine.medicine_name + (medicine.requires_prescription ? "  [Rx]" : "") +
                (outOfStock ? "  - out of stock" : "  - " + medicine.sellable_quantity + " in stock, " + formatMoney(medicine.current_price));
            // "disabled" makes an out-of-stock medicine impossible to choose.
            return '<option value="' + medicine.medicine_id + '"' + (outOfStock ? " disabled" : "") + ">" + escapeHtml(label) + "</option>";
        }).join("");
        // Make sure the first selectable medicine is selected.
        const firstAvailable = catalog.find(function (medicine) { return medicine.sellable_quantity > 0; });
        if (firstAvailable) {
            document.getElementById("medicineId").value = firstAvailable.medicine_id;
        }
    } catch (error) {
        showToast(error.message, "error");
    }
}

// ---------------------------------------------------------------------
// New customer (small inline form)
// ---------------------------------------------------------------------
document.getElementById("toggleNewCustomerButton").addEventListener("click", function () {
    document.getElementById("newCustomerBox").classList.toggle("hidden");     // toggle = show if hidden, hide if shown
});

document.getElementById("saveCustomerButton").addEventListener("click", async function () {
    const name = document.getElementById("newCustomerName").value.trim();
    const phone = document.getElementById("newCustomerPhone").value.trim();
    if (!name) {
        showToast("Please enter the customer's name", "error");
        return;
    }
    try {
        const result = await api.addCustomer({ customer_name: name, phone: phone || null, address: null });
        showToast("Customer added");
        document.getElementById("newCustomerName").value = "";
        document.getElementById("newCustomerPhone").value = "";
        document.getElementById("newCustomerBox").classList.add("hidden");
        await loadCustomers(result.customer_id);                  // reload and select the new customer
    } catch (error) {
        showToast(error.message, "error");
    }
});

// ---------------------------------------------------------------------
// The cart
// ---------------------------------------------------------------------

// drawCart: shows the cart rows and the estimated total.
function drawCart() {
    const body = document.getElementById("cartBody");
    if (cart.length === 0) {
        body.innerHTML = '<tr><td colspan="5" class="empty">The bill is empty. Add a medicine above.</td></tr>';
        document.getElementById("cartTotal").textContent = "";
        document.getElementById("generateBillButton").disabled = true;      // nothing to bill
        return;
    }
    let total = 0;
    body.innerHTML = cart.map(function (line, index) {
        const amount = line.quantity * line.price;
        total += amount;
        return "<tr>" +
            "<td>" + escapeHtml(line.name) + "</td>" +
            '<td class="num">' + line.quantity + "</td>" +
            '<td class="num">' + formatMoney(line.price) + "</td>" +
            '<td class="num">' + formatMoney(amount) + "</td>" +
            '<td><button type="button" class="btn btn-danger btn-small" data-remove-index="' + index + '">Remove</button></td>' +
            "</tr>";
    }).join("");
    document.getElementById("cartTotal").textContent = "Estimated total: " + formatMoney(total);
    document.getElementById("generateBillButton").disabled = false;
}

// "Add to bill": put the chosen medicine in the cart.
document.getElementById("addToCartButton").addEventListener("click", function () {
    const medicineId = Number(document.getElementById("medicineId").value);
    const quantity = Number(document.getElementById("quantity").value);
    const medicine = catalog.find(function (item) { return item.medicine_id === medicineId; });

    if (!medicine) {
        showToast("Please choose a medicine", "error");
        return;
    }
    if (!Number.isInteger(quantity) || quantity < 1) {
        showToast("Quantity must be a whole number, at least 1", "error");
        return;
    }

    // If the medicine is already in the cart, add to its quantity (a medicine may appear only once per bill).
    const existing = cart.find(function (line) { return line.medicine_id === medicineId; });
    const newQuantity = (existing ? existing.quantity : 0) + quantity;

    // A friendly early warning. MySQL still performs the real, final check.
    if (newQuantity > medicine.sellable_quantity) {
        showToast("Only " + medicine.sellable_quantity + " unit(s) of " + medicine.medicine_name + " can be sold", "error");
        return;
    }

    if (existing) {
        existing.quantity = newQuantity;
    } else {
        cart.push({ medicine_id: medicineId, name: medicine.medicine_name, quantity: quantity, price: medicine.current_price });
    }
    document.getElementById("quantity").value = 1;
    drawCart();
});

// "Remove" button inside the cart.
document.getElementById("cartBody").addEventListener("click", function (event) {
    const button = event.target.closest("button[data-remove-index]");
    if (!button) {
        return;
    }
    cart.splice(Number(button.dataset.removeIndex), 1);       // splice(position, howMany) deletes items from the list
    drawCart();
});

document.getElementById("clearCartButton").addEventListener("click", function () {
    cart = [];
    drawCart();
});

// ---------------------------------------------------------------------
// "Generate bill": send the cart to MySQL.
// ---------------------------------------------------------------------
document.getElementById("generateBillButton").addEventListener("click", async function () {
    const button = this;
    button.disabled = true;                                   // avoid double billing by a double click
    const customerValue = document.getElementById("customerId").value;
    const sale = {
        customer_id: customerValue ? Number(customerValue) : null,        // null = walk-in
        payment_mode: document.getElementById("paymentMode").value,
        // Only medicine and quantity are sent: the batch, price and GST are decided inside MySQL.
        items: cart.map(function (line) { return { medicine_id: line.medicine_id, quantity: line.quantity }; })
    };
    try {
        const result = await api.makeSale(sale);              // POST /sales -> MySQL sp_make_bill
        showToast("Bill #" + result.sale_id + " created");
        const bill = await api.getBill(result.sale_id);       // GET /sales/{id}/bill -> MySQL sp_generate_bill
        drawBill(bill);
        cart = [];
        drawCart();
        loadCatalog();                                        // stock has changed: refresh the drop-down
        loadRecentBills();
    } catch (error) {
        // Not enough stock, expired batch ... : MySQL rolled everything back and tells us why.
        showToast(error.message, "error");
        button.disabled = false;
    }
});

// ---------------------------------------------------------------------
// drawBill: fills the printable bill panel with the data from sp_generate_bill.
// ---------------------------------------------------------------------
function drawBill(bill) {
    const first = bill.lines[0];                              // header data is repeated on every line
    const totals = bill.totals;

    document.getElementById("billMeta").innerHTML =
        "<div><strong>Bill no:</strong> " + first.sale_id + "</div>" +
        "<div><strong>Date:</strong> " + escapeHtml(formatDateTime(first.sale_date)) + "</div>" +
        "<div><strong>Customer:</strong> " + escapeHtml(first.customer_name) + (first.customer_phone ? " (" + escapeHtml(first.customer_phone) + ")" : "") + "</div>" +
        "<div><strong>Payment:</strong> " + escapeHtml(first.payment_mode) + "</div>";

    document.getElementById("billLines").innerHTML = bill.lines.map(function (line, index) {
        return "<tr>" +
            "<td>" + (index + 1) + "</td>" +
            "<td>" + escapeHtml(line.medicine_name) + "</td>" +
            "<td>" + escapeHtml(line.batch_no) + "</td>" +
            "<td>" + escapeHtml(formatDate(line.expiry_date)) + "</td>" +
            '<td class="num">' + line.quantity + "</td>" +
            '<td class="num">' + formatMoney(line.unit_price) + "</td>" +
            '<td class="num">' + line.gst_percent + "</td>" +
            '<td class="num">' + formatMoney(line.line_total) + "</td>" +
            "</tr>";
    }).join("");

    document.getElementById("billTotals").innerHTML =
        "<div><span>Taxable value</span><span>" + formatMoney(totals.taxable_total) + "</span></div>" +
        "<div><span>CGST</span><span>" + formatMoney(totals.cgst) + "</span></div>" +
        "<div><span>SGST</span><span>" + formatMoney(totals.sgst) + "</span></div>" +
        '<div class="grand"><span>Grand total</span><span>' + formatMoney(totals.grand_total) + "</span></div>";

    const panel = document.getElementById("billPanel");
    panel.classList.remove("hidden");
    panel.scrollIntoView({ behavior: "smooth" });
}

// Print: the print style sheet (css/style.css, section 14) hides everything except the bill.
document.getElementById("printBillButton").addEventListener("click", function () {
    window.print();
});

// "New sale": hide the bill and reset the form for the next customer.
document.getElementById("newSaleButton").addEventListener("click", function () {
    document.getElementById("billPanel").classList.add("hidden");
    document.getElementById("customerId").value = "";
    document.getElementById("paymentMode").value = "CASH";
    window.scrollTo({ top: 0, behavior: "smooth" });
});

// ---------------------------------------------------------------------
// Recent bills
// ---------------------------------------------------------------------
async function loadRecentBills() {
    try {
        const sales = await api.getSales();                   // GET /sales
        const body = document.getElementById("recentBillsBody");
        if (sales.length === 0) {
            body.innerHTML = '<tr><td colspan="7" class="empty">No bill yet.</td></tr>';
            return;
        }
        body.innerHTML = sales.map(function (sale) {
            return "<tr>" +
                "<td>#" + sale.sale_id + "</td>" +
                "<td>" + escapeHtml(formatDateTime(sale.sale_date)) + "</td>" +
                "<td>" + escapeHtml(sale.customer_name) + "</td>" +
                "<td>" + escapeHtml(sale.payment_mode) + "</td>" +
                '<td class="num">' + sale.total_units + "</td>" +
                '<td class="num">' + formatMoney(sale.grand_total) + "</td>" +
                '<td><button class="btn btn-secondary btn-small" data-view-bill="' + sale.sale_id + '">View bill</button></td>' +
                "</tr>";
        }).join("");
    } catch (error) {
        showToast(error.message, "error");
    }
}

// "View bill" button in the recent-bills table: load and show that bill again.
document.getElementById("recentBillsBody").addEventListener("click", async function (event) {
    const button = event.target.closest("button[data-view-bill]");
    if (!button) {
        return;
    }
    try {
        drawBill(await api.getBill(button.dataset.viewBill));
    } catch (error) {
        showToast(error.message, "error");
    }
});

// Start.
loadCustomers();
loadCatalog();
loadRecentBills();
drawCart();
