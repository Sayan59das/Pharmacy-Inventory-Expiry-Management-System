// =====================================================================
// FILE        : frontend/src/pages/MedicineDetail.jsx
// WHAT IT DOES: One medicine: its key numbers, every batch in the order MySQL
//               sells them (earliest expiry first = FEFO) with an expiry status,
//               and the form to edit its details.
// DEPENDS ON  : api.js, useLoad.js, components (PageHeader, Badge, MedicineForm, TableMessage, Toast)
// USED BY     : App.jsx (address "/medicines/:medicineId")
// MYSQL BEHIND IT: views v_medicine_catalog and v_batch_details; UPDATE medicine.
// =====================================================================

import { Link, useParams } from "react-router";
import { api } from "../api.js";
import { useLoad } from "../useLoad.js";
import { useToast } from "../components/Toast.jsx";
import PageHeader from "../components/PageHeader.jsx";
import Badge, { ExpiryBadge, StockBadge } from "../components/Badge.jsx";
import MedicineForm from "../components/MedicineForm.jsx";
import TableMessage from "../components/TableMessage.jsx";
import { formatDate, formatMoney } from "../utils.js";

export default function MedicineDetail() {
    // useParams reads the ":medicineId" part of the address, e.g. "7" in /medicines/7.
    const { medicineId } = useParams();
    const showToast = useToast();

    // The catalog (all medicines) - we pick this one out of it below.
    const catalog = useLoad(() => api.getMedicines(""), [], [medicineId]);
    // This medicine's batches, reloaded if the address changes to another medicine.
    const batches = useLoad(() => api.getBatches(medicineId), [], [medicineId]);
    const categories = useLoad(() => api.getCategories(), []);

    // Find the medicine whose id matches the address (undefined while loading or if it does not exist).
    const medicine = catalog.data.find((m) => m.medicine_id === Number(medicineId));

    // Save the edited details (PUT /medicines/{id}), then reload the numbers.
    async function handleSave(values) {
        try {
            await api.updateMedicine(medicineId, values);
            showToast("Changes saved");
            catalog.reload();
        } catch (error) {
            showToast(error.message, "error");
        }
    }

    // Still loading: a simple placeholder.
    if (!medicine && catalog.loading) {
        return <div className="page"><PageHeader title="Loading..." back={{ to: "/medicines", label: "Medicines" }} /></div>;
    }
    // Loaded, but no medicine has this id.
    if (!medicine) {
        return (
            <div className="page">
                <PageHeader title="Medicine not found" back={{ to: "/medicines", label: "Medicines" }} />
                <div className="card empty">
                    <strong>There is no medicine with number {medicineId}.</strong>
                    <Link to="/medicines">Back to all medicines</Link>
                </div>
            </div>
        );
    }

    return (
        <div className="page">
            <PageHeader
                title={medicine.medicine_name}
                badge={medicine.requires_prescription ? <Badge tone="blue">Rx · prescription</Badge> : null}
                subtitle={medicine.generic_name + " · " + medicine.manufacturer + " · " + medicine.category_name}
                back={{ to: "/medicines", label: "Medicines" }}
            />

            {/* ---------- key numbers ---------- */}
            <section className="card">
                <dl className="facts">
                    <div>
                        <dt>Sellable stock</dt>
                        <dd>{medicine.sellable_quantity} <StockBadge status={medicine.stock_status} /></dd>
                    </div>
                    <div><dt>Units in expired batches</dt><dd>{medicine.expired_quantity}</dd></div>
                    <div><dt>Reorder level</dt><dd>{medicine.reorder_level}</dd></div>
                    <div><dt>Price of the next batch (MRP)</dt><dd>{medicine.current_price === null ? "–" : formatMoney(medicine.current_price)}</dd></div>
                    <div><dt>GST</dt><dd>{medicine.gst_percent}%</dd></div>
                </dl>
            </section>

            {/* ---------- batches, in FEFO order ---------- */}
            <section className="card">
                <div className="card-header">
                    <h2>Batches</h2>
                    <span className="meta">Sold in this order: the batch that expires first goes first (FEFO)</span>
                </div>
                <div className="table-wrap">
                    <table className="table">
                        <thead>
                            <tr>
                                <th>Batch</th><th>Supplier</th><th>Manufactured</th><th>Expires</th><th>Status</th>
                                <th className="num">Cost</th><th className="num">MRP</th><th className="num">In stock</th>
                            </tr>
                        </thead>
                        <tbody>
                            <TableMessage colSpan={8} loading={batches.loading && batches.data.length === 0}
                                isEmpty={batches.data.length === 0} empty="No batch yet. Buy stock on the Purchase page." />
                            {batches.data.map((b) => (
                                <tr key={b.batch_id}>
                                    <td className="strong nowrap">{b.batch_no}</td>
                                    <td>{b.supplier_name}</td>
                                    <td className="nowrap">{formatDate(b.manufacture_date)}</td>
                                    <td className="nowrap">
                                        {formatDate(b.expiry_date)}
                                        {/* days_left is negative for an expired batch */}
                                        <span className="sub">{b.days_left < 0 ? -b.days_left + " days ago" : "in " + b.days_left + " days"}</span>
                                    </td>
                                    <td><ExpiryBadge status={b.expiry_status} /></td>
                                    <td className="num">{formatMoney(b.cost_price)}</td>
                                    <td className="num">{formatMoney(b.selling_price)}</td>
                                    <td className="num strong">{b.quantity_in_stock}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </section>

            {/* ---------- edit details ---------- */}
            <section className="card">
                <div className="card-header"><h2>Details</h2><span className="meta">Stock is not changed here</span></div>
                <MedicineForm key={medicine.medicine_id + "-" + categories.data.length} initial={medicine}
                    categories={categories.data} onSave={handleSave} submitLabel="Save changes" />
            </section>
        </div>
    );
}
