// =====================================================================
// FILE        : frontend/src/pages/Suppliers.jsx
// WHAT IT DOES: The list of suppliers with how much we bought from each, and a
//               form (opened with "Add supplier") to register a new one.
// DEPENDS ON  : api.js, useLoad.js, components (PageHeader, Icon, TableMessage, Toast)
// USED BY     : App.jsx (address "/suppliers")
// MYSQL BEHIND IT: table supplier + view v_supplier_purchase_summary;
//               UNIQUE(gst_no) and CHECK(15-character GSTIN) reject bad data.
// =====================================================================

import { useState } from "react";
import { api } from "../api.js";
import { useLoad } from "../useLoad.js";
import { useToast } from "../components/Toast.jsx";
import PageHeader from "../components/PageHeader.jsx";
import Icon from "../components/Icon.jsx";
import TableMessage from "../components/TableMessage.jsx";
import { formatDate, formatMoney, formatNumber } from "../utils.js";

// An empty form.
const EMPTY_FORM = { supplier_name: "", contact_person: "", phone: "", email: "", address: "", gst_no: "" };

export default function Suppliers() {
    const showToast = useToast();
    const suppliers = useLoad(() => api.getSuppliers(), []);

    // Is the add form open? And its field values.
    const [formOpen, setFormOpen] = useState(false);
    const [form, setForm] = useState(EMPTY_FORM);
    const [saving, setSaving] = useState(false);

    // Change one field of the form.
    function setField(name, value) {
        setForm((current) => ({ ...current, [name]: value }));
    }

    // Save the new supplier (POST /suppliers).
    async function handleSubmit(event) {
        event.preventDefault();
        setSaving(true);
        try {
            await api.addSupplier({
                supplier_name: form.supplier_name.trim(),
                contact_person: form.contact_person.trim() || null,     // empty text is stored as NULL
                phone: form.phone.trim(),
                email: form.email.trim() || null,
                address: form.address.trim() || null,
                gst_no: form.gst_no.trim().toUpperCase(),
            });
            showToast(form.supplier_name + " added");
            setForm(EMPTY_FORM);
            setFormOpen(false);
            suppliers.reload();
        } catch (error) {
            // e.g. "A supplier with this GST number already exists."
            showToast(error.message, "error");
        } finally {
            setSaving(false);
        }
    }

    return (
        <div className="page">
            <PageHeader title="Suppliers" subtitle="Companies we buy medicines from, with what we spent on each.">
                {!formOpen && (
                    <button type="button" className="btn btn-primary" onClick={() => setFormOpen(true)}>
                        <Icon name="plus" size={16} />
                        Add supplier
                    </button>
                )}
            </PageHeader>

            {/* ---------- add form (only when open) ---------- */}
            {formOpen && (
                <form className="card" onSubmit={handleSubmit}>
                    <div className="card-header"><h2>New supplier</h2></div>
                    <div className="card-body">
                        <div className="form-grid">
                            <div className="field">
                                <label htmlFor="supplierName">Supplier name</label>
                                <input id="supplierName" className="input" required maxLength={100} autoFocus
                                    value={form.supplier_name} onChange={(e) => setField("supplier_name", e.target.value)} />
                            </div>
                            <div className="field">
                                <label htmlFor="gstNo">GST number</label>
                                <input id="gstNo" className="input" required minLength={15} maxLength={15} placeholder="27AABCM1234A1Z5"
                                    value={form.gst_no} onChange={(e) => setField("gst_no", e.target.value)} />
                                <span className="hint">Exactly 15 characters.</span>
                            </div>
                            <div className="field">
                                <label htmlFor="phone">Phone</label>
                                <input id="phone" className="input" required maxLength={15}
                                    value={form.phone} onChange={(e) => setField("phone", e.target.value)} />
                            </div>
                            <div className="field">
                                <label htmlFor="contactPerson">Contact person</label>
                                <input id="contactPerson" className="input" maxLength={100}
                                    value={form.contact_person} onChange={(e) => setField("contact_person", e.target.value)} />
                            </div>
                            <div className="field">
                                <label htmlFor="email">Email</label>
                                <input id="email" className="input" type="email" maxLength={100}
                                    value={form.email} onChange={(e) => setField("email", e.target.value)} />
                            </div>
                            <div className="field">
                                <label htmlFor="address">Address</label>
                                <input id="address" className="input" maxLength={255}
                                    value={form.address} onChange={(e) => setField("address", e.target.value)} />
                            </div>
                        </div>
                    </div>
                    <div className="card-foot form-actions">
                        <button type="button" className="btn btn-secondary" onClick={() => { setFormOpen(false); setForm(EMPTY_FORM); }}>
                            Cancel
                        </button>
                        <button type="submit" className="btn btn-primary" disabled={saving}>{saving ? "Saving..." : "Add supplier"}</button>
                    </div>
                </form>
            )}

            {/* ---------- supplier list ---------- */}
            <section className="card">
                <div className="table-wrap">
                    <table className="table">
                        <thead>
                            <tr>
                                <th>Supplier</th><th>Contact</th><th>GST number</th><th className="num">Invoices</th>
                                <th className="num">Units bought</th><th className="num">Amount spent</th><th>Last purchase</th>
                            </tr>
                        </thead>
                        <tbody>
                            <TableMessage colSpan={7} loading={suppliers.loading && suppliers.data.length === 0}
                                isEmpty={suppliers.data.length === 0} empty="No suppliers yet." />
                            {suppliers.data.map((s) => (
                                <tr key={s.supplier_id}>
                                    <td><span className="strong">{s.supplier_name}</span><span className="sub">{s.address}</span></td>
                                    <td>{s.contact_person || "–"}<span className="sub tabular">{s.phone}</span></td>
                                    <td className="tabular nowrap">{s.gst_no}</td>
                                    <td className="num">{s.number_of_purchases}</td>
                                    <td className="num">{formatNumber(s.total_units_bought)}</td>
                                    <td className="num strong">{formatMoney(s.total_amount_spent)}</td>
                                    <td className="nowrap">{s.last_purchase_date ? formatDate(s.last_purchase_date) : "Never"}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </section>
        </div>
    );
}
