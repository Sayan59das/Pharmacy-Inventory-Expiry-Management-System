// =====================================================================
// FILE        : frontend/src/pages/Sale.jsx
// WHAT IT DOES: The billing counter. Choose the customer (or walk-in) and the
//               payment mode, add medicines to a cart, press "Generate bill".
//               MySQL picks the batches (earliest expiry first = FEFO), checks
//               stock and expiry, reduces the stock and returns the bill, which
//               is shown here and can be printed. Below: the recent bills.
// DEPENDS ON  : api.js, useLoad.js, components (PageHeader, BillView, Badge, Icon, TableMessage, Toast)
// USED BY     : App.jsx (address "/sale")
// MYSQL BEHIND IT: procedures sp_make_bill (+ sp_add_medicine_to_sale and the sale
//               triggers) and sp_generate_bill; views v_medicine_catalog, v_sale_list.
//
// IMPORTANT: this page never decides the batch, the price or the GST. It only
// sends "medicine X, quantity Y". The cart shows an ESTIMATE; the bill shows
// what MySQL actually charged.
// =====================================================================

import { useState } from "react";
import { api } from "../api.js";
import { useLoad } from "../useLoad.js";
import { useToast } from "../components/Toast.jsx";
import PageHeader from "../components/PageHeader.jsx";
import BillView from "../components/BillView.jsx";
import Icon from "../components/Icon.jsx";
import TableMessage from "../components/TableMessage.jsx";
import { formatDateTime, formatMoney } from "../utils.js";

export default function Sale() {
    const showToast = useToast();

    // Data from the backend.
    const customers = useLoad(() => api.getCustomers(), []);
    const catalog = useLoad(() => api.getMedicines(""), []);
    const recentBills = useLoad(() => api.getSales(), []);

    // Customer and payment ("" = walk-in customer).
    const [customerId, setCustomerId] = useState("");
    const [paymentMode, setPaymentMode] = useState("CASH");

    // The small "new customer" form.
    const [newCustomerOpen, setNewCustomerOpen] = useState(false);
    const [newName, setNewName] = useState("");
    const [newPhone, setNewPhone] = useState("");

    // The "add a medicine" line and the cart: [{ medicine_id, name, quantity, price }, ...]
    const [medicineId, setMedicineId] = useState("");
    const [quantity, setQuantity] = useState("1");
    const [cart, setCart] = useState([]);

    // The bill on screen (null = none) and whether "Generate bill" is running.
    const [bill, setBill] = useState(null);
    const [generating, setGenerating] = useState(false);

    // ---------------- new customer ----------------
    async function handleAddCustomer() {
        if (!newName.trim()) {
            showToast("Type the customer's name first", "error");
            return;
        }
        try {
            const result = await api.addCustomer({ customer_name: newName.trim(), phone: newPhone.trim() || null, address: null });
            showToast(newName.trim() + " added");
            setCustomerId(String(result.customer_id));     // select the new customer
            setNewName("");
            setNewPhone("");
            setNewCustomerOpen(false);
            customers.reload();
        } catch (error) {
            // e.g. "A customer with this phone number already exists."
            showToast(error.message, "error");
        }
    }

    // ---------------- cart ----------------
    function handleAddToCart(event) {
        event.preventDefault();
        const medicine = catalog.data.find((m) => m.medicine_id === Number(medicineId));
        const qty = Number(quantity);
        if (!medicine) {
            showToast("Choose a medicine first", "error");
            return;
        }
        if (!Number.isInteger(qty) || qty < 1) {
            showToast("Quantity must be a whole number, at least 1", "error");
            return;
        }
        // A medicine may appear only once per bill: if it is already in the cart, add to its quantity.
        const existing = cart.find((line) => line.medicine_id === medicine.medicine_id);
        const newQty = (existing ? existing.quantity : 0) + qty;
        // A friendly early warning. MySQL still does the real, final check when the bill is generated.
        if (newQty > medicine.sellable_quantity) {
            showToast("Only " + medicine.sellable_quantity + " unit(s) of " + medicine.medicine_name + " can be sold", "error");
            return;
        }
        if (existing) {
            setCart(cart.map((line) => (line.medicine_id === medicine.medicine_id ? { ...line, quantity: newQty } : line)));
        } else {
            setCart([...cart, { medicine_id: medicine.medicine_id, name: medicine.medicine_name, quantity: qty, price: Number(medicine.current_price) }]);
        }
        setQuantity("1");
    }

    function handleRemove(id) {
        setCart(cart.filter((line) => line.medicine_id !== id));
    }

    // Estimated total (the real total is calculated by MySQL).
    const estimatedTotal = cart.reduce((sum, line) => sum + line.quantity * line.price, 0);
    const units = cart.reduce((sum, line) => sum + line.quantity, 0);
    const customer = customers.data.find((c) => c.customer_id === Number(customerId));

    // ---------------- generate the bill ----------------
    async function handleGenerate() {
        setGenerating(true);
        try {
            const result = await api.makeSale({
                customer_id: customerId ? Number(customerId) : null,            // null = walk-in
                payment_mode: paymentMode,
                // only medicine + quantity: the batch, price and GST are decided inside MySQL
                items: cart.map((line) => ({ medicine_id: line.medicine_id, quantity: line.quantity })),
            });
            const fullBill = await api.getBill(result.sale_id);                 // MySQL sp_generate_bill
            setBill(fullBill);
            setCart([]);
            showToast("Bill #" + result.sale_id + " created");
            catalog.reload();                                                   // stock has changed
            recentBills.reload();
            window.scrollTo({ top: 0, behavior: "smooth" });                    // the bill is at the top
        } catch (error) {
            // Not enough stock, expired batch ...: MySQL rolled EVERYTHING back and says why.
            showToast(error.message, "error");
        } finally {
            setGenerating(false);
        }
    }

    // Show an older bill from the recent-bills table.
    async function handleViewBill(saleId) {
        try {
            setBill(await api.getBill(saleId));
            window.scrollTo({ top: 0, behavior: "smooth" });
        } catch (error) {
            showToast(error.message, "error");
        }
    }

    return (
        <div className="page">
            <PageHeader title="New sale" subtitle="MySQL chooses the batches: the batch that expires first is sold first (FEFO)." />

            {/* ---------- the bill, after it is generated ---------- */}
            {bill && <BillView bill={bill} onClose={() => { setBill(null); setCustomerId(""); setPaymentMode("CASH"); }} />}

            <div className="with-aside no-print">
                <div className="stack">
                    {/* ---------- 1. customer and payment ---------- */}
                    <section className="card">
                        <div className="card-header">
                            <h2>Customer and payment</h2>
                            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setNewCustomerOpen(!newCustomerOpen)}>
                                <Icon name={newCustomerOpen ? "chevron-left" : "user"} size={16} />
                                {newCustomerOpen ? "Close" : "New customer"}
                            </button>
                        </div>
                        <div className="card-body form-grid">
                            <div className="field">
                                <label htmlFor="customerId">Customer</label>
                                <select id="customerId" className="select" value={customerId} onChange={(e) => setCustomerId(e.target.value)}>
                                    <option value="">Walk-in customer</option>
                                    {customers.data.map((c) => (
                                        <option key={c.customer_id} value={c.customer_id}>
                                            {c.customer_name}{c.phone ? " · " + c.phone : ""}
                                        </option>
                                    ))}
                                </select>
                            </div>
                            <div className="field">
                                <span className="label" id="paymentLabel">Payment</span>
                                {/* three radio buttons drawn as one segmented control */}
                                <div className="segmented" role="radiogroup" aria-labelledby="paymentLabel">
                                    {["CASH", "UPI", "CARD"].map((mode) => (
                                        <label key={mode}>
                                            <input type="radio" name="payment" value={mode} checked={paymentMode === mode}
                                                onChange={() => setPaymentMode(mode)} />
                                            <span>{mode === "CASH" ? "Cash" : mode === "UPI" ? "UPI" : "Card"}</span>
                                        </label>
                                    ))}
                                </div>
                            </div>
                        </div>
                        {newCustomerOpen && (
                            <div className="card-foot form-grid">
                                <div className="field">
                                    <label htmlFor="newName">New customer's name</label>
                                    <input id="newName" className="input" maxLength={100} value={newName} onChange={(e) => setNewName(e.target.value)} />
                                </div>
                                <div className="field">
                                    <label htmlFor="newPhone">Phone (optional)</label>
                                    <input id="newPhone" className="input" maxLength={15} value={newPhone} onChange={(e) => setNewPhone(e.target.value)} />
                                </div>
                                <div className="field" style={{ justifyContent: "flex-end" }}>
                                    <button type="button" className="btn btn-primary" onClick={handleAddCustomer}>Save customer</button>
                                </div>
                            </div>
                        )}
                    </section>

                    {/* ---------- 2. medicines ---------- */}
                    <section className="card">
                        <div className="card-header"><h2>Medicines</h2><span className="meta">Out-of-stock medicines cannot be chosen</span></div>
                        <form className="card-body add-line" onSubmit={handleAddToCart}>
                            <div className="field">
                                <label htmlFor="medicineId">Medicine</label>
                                <select id="medicineId" className="select" required value={medicineId} onChange={(e) => setMedicineId(e.target.value)}>
                                    <option value="" disabled>Choose a medicine</option>
                                    {catalog.data.map((m) => (
                                        // "disabled": a medicine with nothing sellable cannot be chosen
                                        <option key={m.medicine_id} value={m.medicine_id} disabled={m.sellable_quantity <= 0}>
                                            {m.medicine_name}{m.requires_prescription ? " (Rx)" : ""}
                                            {m.sellable_quantity <= 0 ? " · out of stock" : " · " + m.sellable_quantity + " in stock · " + formatMoney(m.current_price)}
                                        </option>
                                    ))}
                                </select>
                            </div>
                            <div className="field">
                                <label htmlFor="quantity">Quantity</label>
                                <input id="quantity" className="input num" type="number" min="1" required value={quantity}
                                    onChange={(e) => setQuantity(e.target.value)} />
                            </div>
                            <button type="submit" className="btn btn-secondary" style={{ height: 38 }}>
                                <Icon name="plus" size={16} />
                                Add to bill
                            </button>
                        </form>
                        <div className="table-wrap">
                            <table className="table">
                                <thead>
                                    <tr><th>Medicine</th><th className="num">Qty</th><th className="num">Price / unit</th><th className="num">Estimate</th><th></th></tr>
                                </thead>
                                <tbody>
                                    <TableMessage colSpan={5} loading={false} isEmpty={cart.length === 0} empty="The bill is empty. Add a medicine above." />
                                    {cart.map((line) => (
                                        <tr key={line.medicine_id}>
                                            <td className="strong">{line.name}</td>
                                            <td className="num">{line.quantity}</td>
                                            <td className="num">{formatMoney(line.price)}</td>
                                            <td className="num">{formatMoney(line.quantity * line.price)}</td>
                                            <td className="actions">
                                                <button type="button" className="btn btn-danger-ghost btn-icon btn-sm" aria-label={"Remove " + line.name}
                                                    onClick={() => handleRemove(line.medicine_id)}>
                                                    <Icon name="trash" size={16} />
                                                </button>
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    </section>
                </div>

                {/* ---------- bill summary (stays visible while scrolling) ---------- */}
                <aside className="aside-sticky">
                    <section className="card">
                        <div className="card-header"><h2>Bill summary</h2></div>
                        <div className="card-body">
                            <div className="summary-row"><span>Customer</span><strong>{customer ? customer.customer_name : "Walk-in"}</strong></div>
                            <div className="summary-row"><span>Payment</span><strong>{paymentMode}</strong></div>
                            <div className="summary-row"><span>Medicines</span><strong>{cart.length}</strong></div>
                            <div className="summary-row"><span>Units</span><strong>{units}</strong></div>
                            <div className="summary-total"><span>Estimated total</span><strong>{formatMoney(estimatedTotal)}</strong></div>
                        </div>
                        <div className="card-foot">
                            <button type="button" className="btn btn-primary btn-block" onClick={handleGenerate}
                                disabled={cart.length === 0 || generating}>
                                {generating ? "Generating..." : "Generate bill"}
                            </button>
                            {cart.length > 0 && (
                                <button type="button" className="btn btn-ghost btn-block" style={{ marginTop: 6 }} onClick={() => setCart([])}>
                                    Clear cart
                                </button>
                            )}
                            <p className="note" style={{ marginTop: 10 }}>The final amount comes from MySQL: one quantity may be split across two batches with different prices.</p>
                        </div>
                    </section>
                </aside>
            </div>

            {/* ---------- recent bills ---------- */}
            <section className="card no-print">
                <div className="card-header"><h2>Recent bills</h2></div>
                <div className="table-wrap">
                    <table className="table">
                        <thead>
                            <tr><th>Bill</th><th>Date</th><th>Customer</th><th>Payment</th><th className="num">Units</th><th className="num">Total</th><th></th></tr>
                        </thead>
                        <tbody>
                            <TableMessage colSpan={7} loading={recentBills.loading && recentBills.data.length === 0}
                                isEmpty={recentBills.data.length === 0} empty="No bills yet." />
                            {recentBills.data.map((s) => (
                                <tr key={s.sale_id}>
                                    <td className="strong tabular">#{s.sale_id}</td>
                                    <td className="nowrap">{formatDateTime(s.sale_date)}</td>
                                    <td>{s.customer_name}</td>
                                    <td>{s.payment_mode}</td>
                                    <td className="num">{s.total_units}</td>
                                    <td className="num strong">{formatMoney(s.grand_total)}</td>
                                    <td className="actions">
                                        <button type="button" className="btn btn-secondary btn-sm" onClick={() => handleViewBill(s.sale_id)}>View bill</button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </section>
        </div>
    );
}
