// =====================================================================
// FILE        : frontend/src/pages/Purchase.jsx
// WHAT IT DOES: Records a PURCHASE invoice from a supplier: the invoice details,
//               one row per medicine/batch received, the totals and the save
//               button right under the rows. MySQL saves everything in one
//               transaction and a trigger adds the stock. Below: recent purchases.
// DEPENDS ON  : api.js, useLoad.js, components (PageHeader, Icon, TableMessage, Toast)
// USED BY     : App.jsx (address "/purchase")
// MYSQL BEHIND IT: procedure sp_add_purchase (+ triggers trg_purchase_item_before_insert
//               and trg_purchase_item_after_insert); view v_purchase_list.
// =====================================================================

import { useRef, useState } from "react";
import { api } from "../api.js";
import { useLoad } from "../useLoad.js";
import { useToast } from "../components/Toast.jsx";
import PageHeader from "../components/PageHeader.jsx";
import Icon from "../components/Icon.jsx";
import TableMessage from "../components/TableMessage.jsx";
import { formatDate, formatMoney, todayIso } from "../utils.js";

export default function Purchase() {
    const showToast = useToast();

    // Drop-down data and the recent-purchases table.
    const suppliers = useLoad(() => api.getSuppliers(), []);
    const medicines = useLoad(() => api.getMedicines(""), []);
    const purchases = useLoad(() => api.getPurchases(), []);

    // Invoice header fields.
    const [supplierId, setSupplierId] = useState("");
    const [invoiceNo, setInvoiceNo] = useState("");
    const [purchaseDate, setPurchaseDate] = useState(todayIso());

    // Each item row needs a stable "key" for React; a counter kept in a ref gives 1, 2, 3 ...
    const nextKey = useRef(1);
    function newItem() {
        return { key: nextKey.current++, medicine_id: "", batch_no: "", manufacture_date: "", expiry_date: "", quantity: "", unit_cost: "", selling_price: "" };
    }
    // The item rows (start with one empty row).
    const [items, setItems] = useState(() => [newItem()]);
    const [saving, setSaving] = useState(false);

    // Change one field of one row: copy the list, replace the matching row.
    function updateItem(key, field, value) {
        setItems((current) => current.map((item) => (item.key === key ? { ...item, [field]: value } : item)));
    }
    // Remove one row (but always keep at least one).
    function removeItem(key) {
        setItems((current) => (current.length > 1 ? current.filter((item) => item.key !== key) : current));
    }

    // Totals for display only - MySQL stores and checks the real values.
    const totalUnits = items.reduce((sum, item) => sum + (Number(item.quantity) || 0), 0);
    const totalCost = items.reduce((sum, item) => sum + (Number(item.quantity) || 0) * (Number(item.unit_cost) || 0), 0);

    // Send the whole invoice in ONE request -> MySQL procedure sp_add_purchase.
    async function handleSubmit(event) {
        event.preventDefault();
        setSaving(true);
        try {
            const result = await api.addPurchase({
                supplier_id: Number(supplierId),
                invoice_no: invoiceNo.trim(),
                purchase_date: purchaseDate || null,
                // Names must match PurchaseItemIn in backend/routes/purchases.py.
                // Empty optional fields are left out (= top-up of an existing batch).
                items: items.map((item) => {
                    const line = {
                        medicine_id: Number(item.medicine_id),
                        batch_no: item.batch_no.trim(),
                        quantity: Number(item.quantity),
                        unit_cost: Number(item.unit_cost),
                    };
                    if (item.manufacture_date) line.manufacture_date = item.manufacture_date;
                    if (item.expiry_date) line.expiry_date = item.expiry_date;
                    if (item.selling_price !== "") line.selling_price = Number(item.selling_price);
                    return line;
                }),
            });
            showToast("Purchase #" + result.purchase_id + " recorded. Stock updated.");
            // Clear the form for the next invoice.
            setInvoiceNo("");
            setItems([newItem()]);
            purchases.reload();
            medicines.reload();
        } catch (error) {
            // If ANY row is wrong, MySQL rolls back the whole invoice and tells us why.
            showToast(error.message, "error");
        } finally {
            setSaving(false);
        }
    }

    return (
        <div className="page">
            <PageHeader title="New purchase" subtitle="Stock arriving from a supplier. Each row becomes a new batch or tops up an existing one." />

            <form onSubmit={handleSubmit} className="stack">
                {/* ---------- invoice details ---------- */}
                <section className="card">
                    <div className="card-header"><h2>Invoice</h2></div>
                    <div className="card-body form-grid">
                        <div className="field">
                            <label htmlFor="supplierId">Supplier</label>
                            <select id="supplierId" className="select" required value={supplierId} onChange={(e) => setSupplierId(e.target.value)}>
                                <option value="" disabled>Choose a supplier</option>
                                {suppliers.data.map((s) => (
                                    <option key={s.supplier_id} value={s.supplier_id}>{s.supplier_name}</option>
                                ))}
                            </select>
                        </div>
                        <div className="field">
                            <label htmlFor="invoiceNo">Supplier's invoice number</label>
                            <input id="invoiceNo" className="input" required maxLength={30} placeholder="INV-MP-2401"
                                value={invoiceNo} onChange={(e) => setInvoiceNo(e.target.value)} />
                        </div>
                        <div className="field">
                            <label htmlFor="purchaseDate">Invoice date</label>
                            <input id="purchaseDate" className="input" type="date" required
                                value={purchaseDate} onChange={(e) => setPurchaseDate(e.target.value)} />
                        </div>
                    </div>
                </section>

                {/* ---------- item rows + totals + save ---------- */}
                <section className="card">
                    <div className="card-header">
                        <h2>Items</h2>
                        <button type="button" className="btn btn-secondary btn-sm" onClick={() => setItems((current) => [...current, newItem()])}>
                            <Icon name="plus" size={14} />
                            Add row
                        </button>
                    </div>
                    <div className="card-body" style={{ paddingBottom: 12 }}>
                        <p className="notice">
                            <Icon name="info" size={16} />
                            <span>For a <strong>new batch</strong> fill in every field. To top up a batch this supplier already delivered,
                                type its batch number and leave the two dates and the MRP empty.</span>
                        </p>
                    </div>
                    <div className="table-wrap">
                        <table className="table">
                            <thead>
                                <tr>
                                    <th>Medicine</th><th>Batch no</th><th>Manufactured</th><th>Expiry</th>
                                    <th className="num">Qty</th><th className="num">Cost / unit</th><th className="num">MRP / unit</th>
                                    <th className="num">Line total</th><th></th>
                                </tr>
                            </thead>
                            <tbody>
                                {items.map((item) => (
                                    <tr key={item.key}>
                                        <td className="cell-input" style={{ minWidth: 210 }}>
                                            <select className="select compact" required aria-label="Medicine" value={item.medicine_id}
                                                onChange={(e) => updateItem(item.key, "medicine_id", e.target.value)}>
                                                <option value="" disabled>Choose a medicine</option>
                                                {medicines.data.map((m) => (
                                                    <option key={m.medicine_id} value={m.medicine_id}>{m.medicine_name}</option>
                                                ))}
                                            </select>
                                        </td>
                                        <td className="cell-input" style={{ minWidth: 120 }}>
                                            <input className="input compact" required maxLength={30} aria-label="Batch number" placeholder="PCM-26A"
                                                value={item.batch_no} onChange={(e) => updateItem(item.key, "batch_no", e.target.value)} />
                                        </td>
                                        <td className="cell-input"><input className="input compact" type="date" aria-label="Manufacture date"
                                            value={item.manufacture_date} onChange={(e) => updateItem(item.key, "manufacture_date", e.target.value)} /></td>
                                        <td className="cell-input"><input className="input compact" type="date" aria-label="Expiry date"
                                            value={item.expiry_date} onChange={(e) => updateItem(item.key, "expiry_date", e.target.value)} /></td>
                                        <td className="cell-input" style={{ width: 84 }}><input className="input compact num" type="number" min="1" required aria-label="Quantity"
                                            value={item.quantity} onChange={(e) => updateItem(item.key, "quantity", e.target.value)} /></td>
                                        <td className="cell-input" style={{ width: 104 }}><input className="input compact num" type="number" min="0" step="0.01" required aria-label="Cost per unit"
                                            value={item.unit_cost} onChange={(e) => updateItem(item.key, "unit_cost", e.target.value)} /></td>
                                        <td className="cell-input" style={{ width: 104 }}><input className="input compact num" type="number" min="0" step="0.01" aria-label="MRP per unit"
                                            value={item.selling_price} onChange={(e) => updateItem(item.key, "selling_price", e.target.value)} /></td>
                                        <td className="num">{formatMoney((Number(item.quantity) || 0) * (Number(item.unit_cost) || 0))}</td>
                                        <td className="actions">
                                            <button type="button" className="btn btn-danger-ghost btn-icon btn-sm" aria-label="Remove row"
                                                onClick={() => removeItem(item.key)} disabled={items.length === 1}>
                                                <Icon name="trash" size={16} />
                                            </button>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                    {/* totals and the save button, right under the rows */}
                    <div className="items-foot">
                        <div className="items-totals">
                            <div><span>Rows</span><strong>{items.length}</strong></div>
                            <div><span>Units</span><strong>{totalUnits}</strong></div>
                            <div className="grand"><span>Invoice total</span><strong>{formatMoney(totalCost)}</strong></div>
                        </div>
                        <div className="form-actions" style={{ alignItems: "center" }}>
                            <span className="note">All rows are saved together; if one is wrong, nothing is saved.</span>
                            <button type="submit" className="btn btn-primary" disabled={saving}>
                                {saving ? "Recording..." : "Record purchase"}
                            </button>
                        </div>
                    </div>
                </section>
            </form>

            {/* ---------- recent purchases ---------- */}
            <section className="card">
                <div className="card-header"><h2>Recent purchases</h2></div>
                <div className="table-wrap">
                    <table className="table">
                        <thead>
                            <tr><th>Purchase</th><th>Invoice</th><th>Date</th><th>Supplier</th><th className="num">Rows</th><th className="num">Units</th><th className="num">Amount</th></tr>
                        </thead>
                        <tbody>
                            <TableMessage colSpan={7} loading={purchases.loading && purchases.data.length === 0}
                                isEmpty={purchases.data.length === 0} empty="No purchases yet." />
                            {purchases.data.map((p) => (
                                <tr key={p.purchase_id}>
                                    <td className="strong tabular">#{p.purchase_id}</td>
                                    <td className="nowrap">{p.invoice_no}</td>
                                    <td className="nowrap">{formatDate(p.purchase_date)}</td>
                                    <td>{p.supplier_name}</td>
                                    <td className="num">{p.item_lines}</td>
                                    <td className="num">{p.total_units}</td>
                                    <td className="num strong">{formatMoney(p.total_amount)}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </section>
        </div>
    );
}
