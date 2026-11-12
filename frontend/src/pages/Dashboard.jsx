// =====================================================================
// FILE        : frontend/src/pages/Dashboard.jsx
// WHAT IT DOES: The home page. Four number tiles (low stock, expiring, expired,
//               sales today) that each open their report, the list of open
//               alerts with a Resolve button, recent bills, and two short lists:
//               low stock and batches expiring within 30 days.
// DEPENDS ON  : api.js, useLoad.js, components (PageHeader, StatCard, Badge, Icon, TableMessage, Toast)
// USED BY     : App.jsx (address "/")
// MYSQL BEHIND IT: views v_dashboard_summary, v_open_alerts, v_sale_list, v_low_stock,
//               v_expiring_soon; procedures sp_resolve_alert, sp_generate_expiry_alerts,
//               sp_generate_low_stock_alerts.
// =====================================================================

import { useState } from "react";
import { Link } from "react-router";
import { api } from "../api.js";
import { useLoad } from "../useLoad.js";
import { useToast } from "../components/Toast.jsx";
import PageHeader from "../components/PageHeader.jsx";
import StatCard from "../components/StatCard.jsx";
import { AlertBadge } from "../components/Badge.jsx";
import Badge from "../components/Badge.jsx";
import Icon from "../components/Icon.jsx";
import TableMessage from "../components/TableMessage.jsx";
import { formatDate, formatDateTime, formatMoney, formatShortDateTime, longToday } from "../utils.js";

// How many alerts are shown before "Show all" is pressed.
const ALERTS_SHOWN_FIRST = 6;

export default function Dashboard() {
    const showToast = useToast();

    // Five requests, each loaded when the page opens (see useLoad.js).
    const summary = useLoad(() => api.getDashboard(), null);
    const alerts = useLoad(() => api.getAlerts(), []);
    const sales = useLoad(() => api.getSales(), []);
    const lowStock = useLoad(() => api.getLowStock(), []);
    const expiring = useLoad(() => api.getExpiringSoon(), []);

    // The alert whose Resolve button was just clicked (to disable that button while saving).
    const [busyAlertId, setBusyAlertId] = useState(null);
    // true while "Refresh alerts" is running.
    const [refreshing, setRefreshing] = useState(false);
    // false = show only the first few alerts; true = show all of them.
    const [showAllAlerts, setShowAllAlerts] = useState(false);

    // Click on "Resolve": MySQL procedure sp_resolve_alert marks the alert RESOLVED.
    async function handleResolve(alertId) {
        setBusyAlertId(alertId);
        try {
            await api.resolveAlert(alertId);
            showToast("Alert resolved");
            alerts.reload();
            summary.reload();
        } catch (error) {
            showToast(error.message, "error");
        } finally {
            setBusyAlertId(null);
        }
    }

    // Click on "Refresh alerts": runs the same procedures as the daily MySQL event, right now.
    async function handleRefresh() {
        setRefreshing(true);
        try {
            const result = await api.refreshAlerts();
            // Add up how many new alerts the two procedures created.
            const added = (result.expiry.near_expiry_alerts_added || 0)
                + (result.expiry.expired_alerts_added || 0)
                + (result.low_stock.low_stock_alerts_added || 0);
            showToast(added === 0 ? "Alerts are up to date" : added + " new alert(s) created");
            alerts.reload();
            summary.reload();
        } catch (error) {
            showToast(error.message, "error");
        } finally {
            setRefreshing(false);
        }
    }

    // The summary row (null until it arrives). "–" is shown in the tiles until then.
    const s = summary.data;
    // The alerts on screen: the first few, or all of them after "Show all".
    const visibleAlerts = showAllAlerts ? alerts.data : alerts.data.slice(0, ALERTS_SHOWN_FIRST);

    return (
        <div className="page">
            <PageHeader title="Dashboard" subtitle={longToday()}>
                <button type="button" className="btn btn-secondary" onClick={handleRefresh} disabled={refreshing}>
                    <Icon name="refresh" size={16} />
                    {refreshing ? "Refreshing..." : "Refresh alerts"}
                </button>
                <Link to="/sale" className="btn btn-primary">
                    <Icon name="plus" size={16} />
                    New sale
                </Link>
            </PageHeader>

            {/* ---------- four number tiles, each opens the report behind it ---------- */}
            <section className="stats" aria-label="Stock summary">
                <StatCard label="Low stock" value={s ? s.low_stock_count : "–"} meta="medicines below reorder level"
                    icon="alert" tone="amber" to="/reports?tab=low" />
                <StatCard label="Expiring in 30 days" value={s ? s.near_expiry_count : "–"} meta="batches to sell first"
                    icon="clock" tone="amber" to="/reports?tab=expiring" />
                <StatCard label="Expired in stock" value={s ? s.expired_count : "–"} meta="batches to remove from the shelf"
                    icon="x-circle" tone="red" to="/reports?tab=expired" />
                <StatCard label="Sales today" value={s ? formatMoney(s.todays_sales) : "–"}
                    meta={s ? s.todays_bills + (s.todays_bills === 1 ? " bill" : " bills") + " so far" : ""}
                    icon="rupee" tone="green" to="/reports?tab=monthly" />
            </section>

            <div className="grid-2">
                {/* ---------- open alerts ---------- */}
                <section className="card">
                    <div className="card-header">
                        <h2>Open alerts</h2>
                        <span className="meta">{alerts.data.length} open · raised by MySQL triggers and the daily event</span>

                    </div>
                    <div className="table-wrap">
                        <table className="table">
                            <thead>
                                <tr><th>Alert</th><th>Medicine and details</th><th>Raised</th><th></th></tr>
                            </thead>
                            <tbody>
                                <TableMessage colSpan={4} loading={alerts.loading && alerts.data.length === 0}
                                    isEmpty={alerts.data.length === 0} empty="No open alerts. Stock is healthy." />
                                {visibleAlerts.map((alert) => (
                                    <tr key={alert.alert_id}>
                                        <td><AlertBadge type={alert.alert_type} /></td>
                                        <td>
                                            <span className="strong">{alert.medicine_name}</span>
                                            {alert.batch_no && <span className="note"> · Batch {alert.batch_no}</span>}
                                            {/* the message text was written by MySQL when the alert was raised */}
                                            <span className="sub">{alert.message}</span>
                                        </td>
                                        <td className="nowrap note">{formatShortDateTime(alert.created_at)}</td>
                                        <td className="actions">
                                            <button type="button" className="btn btn-secondary btn-sm"
                                                onClick={() => handleResolve(alert.alert_id)}
                                                disabled={busyAlertId === alert.alert_id}>
                                                Resolve
                                            </button>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                    {/* "Show all" only when there are more alerts than are shown */}
                    {alerts.data.length > ALERTS_SHOWN_FIRST && (
                        <div className="table-more">
                            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setShowAllAlerts(!showAllAlerts)}>
                                {showAllAlerts ? "Show fewer" : "Show all " + alerts.data.length + " alerts"}
                            </button>
                        </div>
                    )}
                </section>

                {/* ---------- recent bills ---------- */}
                <section className="card">
                    <div className="card-header">
                        <h2>Recent bills</h2>
                        <Link to="/sale" className="meta-link">Open sales</Link>
                    </div>
                    <div className="table-wrap">
                        <table className="table">
                            <thead>
                                <tr><th>Bill</th><th>Customer</th><th className="num">Total</th></tr>
                            </thead>
                            <tbody>
                                <TableMessage colSpan={3} loading={sales.loading && sales.data.length === 0}
                                    isEmpty={sales.data.length === 0} empty="No bills yet." />
                                {/* slice(0, 7): only the 7 newest bills */}
                                {sales.data.slice(0, 7).map((sale) => (
                                    <tr key={sale.sale_id}>
                                        <td>
                                            <span className="strong tabular">#{sale.sale_id}</span>
                                            <span className="sub nowrap">{formatDateTime(sale.sale_date)}</span>
                                        </td>
                                        <td>
                                            {sale.customer_name}
                                            <span className="sub">{sale.payment_mode}</span>
                                        </td>
                                        <td className="num strong">{formatMoney(sale.grand_total)}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </section>
            </div>

            <div className="grid-halves">
                {/* ---------- low stock ---------- */}
                <section className="card">
                    <div className="card-header">
                        <h2>Low stock</h2>
                        <Link to="/reports?tab=low" className="meta-link">Full report</Link>
                    </div>
                    <div className="table-wrap">
                        <table className="table">
                            <thead>
                                <tr><th>Medicine</th><th className="num">Sellable</th><th className="num">Reorder at</th><th className="num">Short by</th></tr>
                            </thead>
                            <tbody>
                                <TableMessage colSpan={4} loading={lowStock.loading && lowStock.data.length === 0}
                                    isEmpty={lowStock.data.length === 0} empty="Every medicine is above its reorder level." />
                                {lowStock.data.map((row) => (
                                    <tr key={row.medicine_id}>
                                        <td>
                                            <Link to={"/medicines/" + row.medicine_id} className="cell-link">{row.medicine_name}</Link>
                                            <span className="sub">{row.category_name}</span>
                                        </td>
                                        <td className="num">
                                            {row.sellable_quantity === 0 ? <Badge tone="red">Out · 0</Badge> : row.sellable_quantity}
                                        </td>
                                        <td className="num">{row.reorder_level}</td>
                                        <td className="num strong">{row.shortfall}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </section>

                {/* ---------- expiring within 30 days ---------- */}
                <section className="card">
                    <div className="card-header">
                        <h2>Expiring within 30 days</h2>
                        <Link to="/reports?tab=expiring" className="meta-link">Full report</Link>
                    </div>
                    <div className="table-wrap">
                        <table className="table">
                            <thead>
                                <tr><th>Medicine</th><th>Expires</th><th className="num">Units</th></tr>
                            </thead>
                            <tbody>
                                <TableMessage colSpan={3} loading={expiring.loading && expiring.data.length === 0}
                                    isEmpty={expiring.data.length === 0} empty="Nothing expires in the next 30 days." />
                                {expiring.data.map((row) => (
                                    <tr key={row.batch_id}>
                                        <td>
                                            <Link to={"/medicines/" + row.medicine_id} className="cell-link">{row.medicine_name}</Link>
                                            <span className="sub nowrap">Batch {row.batch_no}</span>
                                        </td>
                                        <td className="nowrap">
                                            {formatDate(row.expiry_date)}
                                            <span className="sub">{row.days_left === 0 ? "today" : "in " + row.days_left + " days"}</span>
                                        </td>
                                        <td className="num">{row.quantity_in_stock}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </section>
            </div>
        </div>
    );
}
