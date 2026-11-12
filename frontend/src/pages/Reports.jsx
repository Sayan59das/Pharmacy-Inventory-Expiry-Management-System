// =====================================================================
// FILE        : frontend/src/pages/Reports.jsx
// WHAT IT DOES: Six reports in tabs: Monthly sales, Top selling, Expiring soon,
//               Expired stock, Low stock and Suppliers. The open tab is kept in
//               the address (/reports?tab=low), so the dashboard tiles can link
//               straight to a report.
// DEPENDS ON  : api.js, useLoad.js, components (PageHeader, StatCard, Badge, TableMessage)
// USED BY     : App.jsx (address "/reports")
// MYSQL BEHIND IT: procedure sp_monthly_sales_report; views v_top_selling_medicines,
//               v_expiring_soon, v_expired_stock, v_low_stock, v_supplier_purchase_summary.
// =====================================================================

import { useState } from "react";
import { Link, useSearchParams } from "react-router";
import { api } from "../api.js";
import { useLoad } from "../useLoad.js";
import PageHeader from "../components/PageHeader.jsx";
import StatCard from "../components/StatCard.jsx";
import Badge from "../components/Badge.jsx";
import TableMessage from "../components/TableMessage.jsx";
import { formatDate, formatMoney, formatNumber } from "../utils.js";

// The tabs: the value in the address and the label on screen.
const TABS = [
    { id: "monthly", label: "Monthly sales" },
    { id: "top", label: "Top selling" },
    { id: "expiring", label: "Expiring soon" },
    { id: "expired", label: "Expired stock" },
    { id: "low", label: "Low stock" },
    { id: "suppliers", label: "Suppliers" },
];

export default function Reports() {
    // useSearchParams reads/writes the "?tab=..." part of the address.
    const [searchParams, setSearchParams] = useSearchParams();
    // The open tab; "monthly" when the address has none (or an unknown one).
    const requested = searchParams.get("tab");
    const tab = TABS.some((t) => t.id === requested) ? requested : "monthly";

    return (
        <div className="page">
            <PageHeader title="Reports" subtitle="Every number comes straight from a MySQL view or stored procedure." />

            {/* Tab buttons. role="tablist"/"tab" and aria-selected help screen readers. */}
            <div className="tabs" role="tablist">
                {TABS.map((t) => (
                    <button key={t.id} type="button" role="tab" className="tab" aria-selected={tab === t.id}
                        onClick={() => setSearchParams({ tab: t.id })}>
                        {t.label}
                    </button>
                ))}
            </div>

            {/* Only the open tab is drawn, so only its data is loaded. */}
            {tab === "monthly" && <MonthlyReport />}
            {tab === "top" && <TopSelling />}
            {tab === "expiring" && <ExpiringSoon />}
            {tab === "expired" && <ExpiredStock />}
            {tab === "low" && <LowStock />}
            {tab === "suppliers" && <SupplierSummary />}
        </div>
    );
}

// ---------------------------------------------------------------------
// 1. Monthly sales: procedure sp_monthly_sales_report returns 3 result sets.
// ---------------------------------------------------------------------
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

function MonthlyReport() {
    const today = new Date();
    // What is chosen in the controls ...
    const [month, setMonth] = useState(today.getMonth() + 1);
    const [year, setYear] = useState(today.getFullYear());
    // ... and what was last asked for (changed only by "Show report").
    const [asked, setAsked] = useState({ month: today.getMonth() + 1, year: today.getFullYear() });

    // Reloads whenever "asked" changes.
    const report = useLoad(() => api.getMonthlySales(asked.month, asked.year), null, [asked.month, asked.year]);
    const s = report.data ? report.data.summary : null;

    return (
        <>
            <form className="card toolbar" style={{ borderBottom: 0 }} onSubmit={(e) => { e.preventDefault(); setAsked({ month, year }); }}>
                <select className="select" aria-label="Month" value={month} onChange={(e) => setMonth(Number(e.target.value))}>
                    {MONTHS.map((name, index) => <option key={name} value={index + 1}>{name}</option>)}
                </select>
                <input className="input num" type="number" min="2000" max="2100" aria-label="Year" style={{ width: 110 }}
                    value={year} onChange={(e) => setYear(Number(e.target.value))} />
                <button type="submit" className="btn btn-primary">Show report</button>
                <span className="count">{MONTHS[asked.month - 1]} {asked.year}</span>
            </form>

            <section className="stats five">
                <StatCard label="Bills" value={s ? s.total_bills : "–"} />
                <StatCard label="Units sold" value={s ? formatNumber(s.total_units) : "–"} />
                <StatCard label="Total sales" value={s ? formatMoney(s.total_sales) : "–"} meta="GST included" />
                <StatCard label="GST collected" value={s ? formatMoney(s.total_gst_collected) : "–"} meta="CGST + SGST" />
                <StatCard label="Average bill" value={s ? formatMoney(s.average_bill_value) : "–"} />
            </section>

            <div className="grid-halves">
                <section className="card">
                    <div className="card-header"><h2>By payment mode</h2></div>
                    <table className="table">
                        <thead><tr><th>Payment</th><th className="num">Bills</th><th className="num">Amount</th></tr></thead>
                        <tbody>
                            <TableMessage colSpan={3} loading={report.loading} isEmpty={!report.data || report.data.by_payment_mode.length === 0} empty="No sales in this month." />
                            {!report.loading && report.data && report.data.by_payment_mode.map((row) => (
                                <tr key={row.payment_mode}>
                                    <td className="strong">{row.payment_mode}</td>
                                    <td className="num">{row.bills}</td>
                                    <td className="num strong">{formatMoney(row.amount)}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </section>
                <section className="card">
                    <div className="card-header"><h2>Top medicines of the month</h2></div>
                    <table className="table">
                        <thead><tr><th>Medicine</th><th className="num">Units</th><th className="num">Revenue</th></tr></thead>
                        <tbody>
                            <TableMessage colSpan={3} loading={report.loading} isEmpty={!report.data || report.data.top_medicines.length === 0} empty="No sales in this month." />
                            {!report.loading && report.data && report.data.top_medicines.map((row) => (
                                <tr key={row.medicine_name}>
                                    <td className="strong">{row.medicine_name}</td>
                                    <td className="num">{row.units_sold}</td>
                                    <td className="num">{formatMoney(row.revenue)}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </section>
            </div>
        </>
    );
}

// ---------------------------------------------------------------------
// 2. Top selling medicines (all time): view v_top_selling_medicines.
// ---------------------------------------------------------------------
function TopSelling() {
    const rows = useLoad(() => api.getTopSelling(15), []);
    return (
        <section className="card">
            <div className="card-header"><h2>Top-selling medicines</h2><span className="meta">All time, by units sold</span></div>
            <div className="table-wrap">
                <table className="table">
                    <thead><tr><th>Rank</th><th>Medicine</th><th>Category</th><th className="num">Units sold</th><th className="num">Bills</th><th className="num">Revenue</th></tr></thead>
                    <tbody>
                        <TableMessage colSpan={6} loading={rows.loading && rows.data.length === 0} isEmpty={rows.data.length === 0} empty="No sales yet." />
                        {rows.data.map((row, index) => (
                            <tr key={row.medicine_id}>
                                <td className="tabular">{index + 1}</td>
                                <td><Link to={"/medicines/" + row.medicine_id} className="cell-link">{row.medicine_name}</Link></td>
                                <td>{row.category_name}</td>
                                <td className="num strong">{row.units_sold}</td>
                                <td className="num">{row.number_of_bills}</td>
                                <td className="num">{formatMoney(row.total_revenue)}</td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </section>
    );
}

// ---------------------------------------------------------------------
// 3. Expiring within 30 days: view v_expiring_soon.
// ---------------------------------------------------------------------
function ExpiringSoon() {
    const rows = useLoad(() => api.getExpiringSoon(), []);
    return (
        <section className="card">
            <div className="card-header"><h2>Batches expiring within 30 days</h2><span className="meta">Sell these first</span></div>
            <div className="table-wrap">
                <table className="table">
                    <thead><tr><th>Medicine</th><th>Batch</th><th>Supplier</th><th>Expires</th><th className="num">Days left</th><th className="num">Units</th><th className="num">Value at cost</th></tr></thead>
                    <tbody>
                        <TableMessage colSpan={7} loading={rows.loading && rows.data.length === 0} isEmpty={rows.data.length === 0} empty="Nothing expires in the next 30 days." />
                        {rows.data.map((row) => (
                            <tr key={row.batch_id}>
                                <td><Link to={"/medicines/" + row.medicine_id} className="cell-link">{row.medicine_name}</Link></td>
                                <td className="nowrap">{row.batch_no}</td>
                                <td>{row.supplier_name}</td>
                                <td className="nowrap">{formatDate(row.expiry_date)}</td>
                                <td className="num"><Badge tone="amber">{row.days_left} days</Badge></td>
                                <td className="num">{row.quantity_in_stock}</td>
                                <td className="num">{formatMoney(row.stock_value_at_cost)}</td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </section>
    );
}

// ---------------------------------------------------------------------
// 4. Expired batches still on the shelf: view v_expired_stock.
// ---------------------------------------------------------------------
function ExpiredStock() {
    const rows = useLoad(() => api.getExpired(), []);
    // Add up the money lost (display only).
    const totalLoss = rows.data.reduce((sum, row) => sum + Number(row.loss_value), 0);
    return (
        <section className="card">
            <div className="card-header"><h2>Expired stock</h2><span className="meta">Remove from the shelf · {formatMoney(totalLoss)} at cost</span></div>
            <div className="table-wrap">
                <table className="table">
                    <thead><tr><th>Medicine</th><th>Batch</th><th>Supplier</th><th>Expired on</th><th className="num">Days ago</th><th className="num">Units</th><th className="num">Loss at cost</th></tr></thead>
                    <tbody>
                        <TableMessage colSpan={7} loading={rows.loading && rows.data.length === 0} isEmpty={rows.data.length === 0} empty="No expired stock on the shelf." />
                        {rows.data.map((row) => (
                            <tr key={row.batch_id}>
                                <td><Link to={"/medicines/" + row.medicine_id} className="cell-link">{row.medicine_name}</Link></td>
                                <td className="nowrap">{row.batch_no}</td>
                                <td>{row.supplier_name}</td>
                                <td className="nowrap">{formatDate(row.expiry_date)}</td>
                                <td className="num"><Badge tone="red">{row.days_since_expiry} days</Badge></td>
                                <td className="num">{row.quantity_in_stock}</td>
                                <td className="num strong">{formatMoney(row.loss_value)}</td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </section>
    );
}

// ---------------------------------------------------------------------
// 5. Low stock: view v_low_stock (expired units are NOT counted as sellable).
// ---------------------------------------------------------------------
function LowStock() {
    const rows = useLoad(() => api.getLowStock(), []);
    return (
        <section className="card">
            <div className="card-header"><h2>Below reorder level</h2><span className="meta">Expired units do not count as sellable</span></div>
            <div className="table-wrap">
                <table className="table">
                    <thead><tr><th>Medicine</th><th>Category</th><th className="num">Sellable</th><th className="num">Expired</th><th className="num">Reorder level</th><th className="num">Short by</th></tr></thead>
                    <tbody>
                        <TableMessage colSpan={6} loading={rows.loading && rows.data.length === 0} isEmpty={rows.data.length === 0} empty="Every medicine is above its reorder level." />
                        {rows.data.map((row) => (
                            <tr key={row.medicine_id}>
                                <td><Link to={"/medicines/" + row.medicine_id} className="cell-link">{row.medicine_name}</Link></td>
                                <td>{row.category_name}</td>
                                <td className="num">{row.sellable_quantity === 0 ? <Badge tone="red">Out · 0</Badge> : <Badge tone="amber">{row.sellable_quantity}</Badge>}</td>
                                <td className="num">{row.expired_quantity}</td>
                                <td className="num">{row.reorder_level}</td>
                                <td className="num strong">{row.shortfall}</td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </section>
    );
}

// ---------------------------------------------------------------------
// 6. Purchases per supplier: view v_supplier_purchase_summary.
// ---------------------------------------------------------------------
function SupplierSummary() {
    const rows = useLoad(() => api.getSupplierSummary(), []);
    return (
        <section className="card">
            <div className="card-header"><h2>Purchases per supplier</h2></div>
            <div className="table-wrap">
                <table className="table">
                    <thead><tr><th>Supplier</th><th className="num">Invoices</th><th className="num">Units bought</th><th className="num">Amount spent</th><th>Last purchase</th></tr></thead>
                    <tbody>
                        <TableMessage colSpan={5} loading={rows.loading && rows.data.length === 0} isEmpty={rows.data.length === 0} empty="No purchases yet." />
                        {rows.data.map((row) => (
                            <tr key={row.supplier_id}>
                                <td className="strong">{row.supplier_name}</td>
                                <td className="num">{row.number_of_purchases}</td>
                                <td className="num">{formatNumber(row.total_units_bought)}</td>
                                <td className="num strong">{formatMoney(row.total_amount_spent)}</td>
                                <td className="nowrap">{row.last_purchase_date ? formatDate(row.last_purchase_date) : "Never"}</td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </section>
    );
}
