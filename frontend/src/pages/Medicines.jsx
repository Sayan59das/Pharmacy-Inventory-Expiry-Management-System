// =====================================================================
// FILE        : frontend/src/pages/Medicines.jsx
// WHAT IT DOES: The list of all medicines with their sellable stock, status,
//               next expiry and current price. Search by name / generic name /
//               manufacturer, filter by category, click a row to open it.
// DEPENDS ON  : api.js, useLoad.js, components (PageHeader, Badge, Icon, TableMessage)
// USED BY     : App.jsx (address "/medicines")
// MYSQL BEHIND IT: view v_medicine_catalog (stock numbers + stock_status), table category.
// =====================================================================

import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router";
import { api } from "../api.js";
import { useLoad } from "../useLoad.js";
import PageHeader from "../components/PageHeader.jsx";
import Badge, { StockBadge } from "../components/Badge.jsx";
import Icon from "../components/Icon.jsx";
import TableMessage from "../components/TableMessage.jsx";
import { formatDate, formatMoney } from "../utils.js";

export default function Medicines() {
    // useNavigate gives a function that changes the page (used when a row is clicked).
    const navigate = useNavigate();

    // What the user types in the search box, updated on every key.
    const [search, setSearch] = useState("");
    // The same text, but only updated 250 ms after the user STOPS typing ("debouncing"),
    // so we do not send one request per letter.
    const [searchSent, setSearchSent] = useState("");
    // The chosen category id ("" = all categories). Filtering by category happens on screen.
    const [categoryId, setCategoryId] = useState("");

    // Copy search -> searchSent after a 250 ms pause.
    useEffect(() => {
        const timer = setTimeout(() => setSearchSent(search.trim()), 250);
        // If the user types again within 250 ms, cancel the previous timer.
        return () => clearTimeout(timer);
    }, [search]);

    // Load the medicines again whenever searchSent changes (the 3rd argument "watches" it).
    const medicines = useLoad(() => api.getMedicines(searchSent), [], [searchSent]);
    const categories = useLoad(() => api.getCategories(), []);

    // Keep only the medicines of the chosen category (or all of them).
    const visible = medicines.data.filter((m) => categoryId === "" || m.category_id === Number(categoryId));

    return (
        <div className="page">
            <PageHeader title="Medicines" subtitle="Stock is counted per batch; these numbers add up the sellable (non-expired) batches.">
                <Link to="/medicines/new" className="btn btn-primary">
                    <Icon name="plus" size={16} />
                    Add medicine
                </Link>
            </PageHeader>

            <section className="card">
                {/* search box, category filter and the number of results */}
                <div className="toolbar">
                    <div className="search">
                        <Icon name="search" size={16} />
                        <input type="search" className="input" placeholder="Search name, generic name or manufacturer"
                            aria-label="Search medicines" value={search} onChange={(e) => setSearch(e.target.value)} />
                    </div>
                    <select className="select" aria-label="Filter by category" value={categoryId}
                        onChange={(e) => setCategoryId(e.target.value)}>
                        <option value="">All categories</option>
                        {categories.data.map((c) => (
                            <option key={c.category_id} value={c.category_id}>{c.category_name}</option>
                        ))}
                    </select>
                    <span className="count">{visible.length} of {medicines.data.length} medicines</span>
                </div>

                <div className="table-wrap">
                    <table className="table">
                        <thead>
                            <tr>
                                <th>Medicine</th><th>Category</th><th>Stock</th><th className="num">Sellable</th>
                                <th className="num">Reorder at</th><th>Next expiry</th><th className="num">MRP</th><th></th>
                            </tr>
                        </thead>
                        <tbody>
                            <TableMessage colSpan={8} loading={medicines.loading && medicines.data.length === 0}
                                isEmpty={visible.length === 0} empty="No medicine matches this search." />
                            {visible.map((m) => (
                                // The whole row opens the medicine; the name is also a real link for keyboard users.
                                <tr key={m.medicine_id} className="row-link" onClick={() => navigate("/medicines/" + m.medicine_id)}>
                                    <td>
                                        <Link to={"/medicines/" + m.medicine_id} className="cell-link" onClick={(e) => e.stopPropagation()}>
                                            {m.medicine_name}
                                        </Link>
                                        {m.requires_prescription && <> <Badge tone="blue">Rx</Badge></>}
                                        <span className="sub">{m.generic_name} · {m.manufacturer}</span>
                                    </td>
                                    <td>{m.category_name}</td>
                                    {/* stock_status (OUT / LOW / OK) is decided by MySQL in the view */}
                                    <td><StockBadge status={m.stock_status} /></td>
                                    <td className="num strong">
                                        {m.sellable_quantity}
                                        {m.expired_quantity > 0 && <span className="sub">+{m.expired_quantity} expired</span>}
                                    </td>
                                    <td className="num">{m.reorder_level}</td>
                                    <td className="nowrap">{m.next_expiry_date ? formatDate(m.next_expiry_date) : "–"}</td>
                                    <td className="num">{m.current_price === null ? "–" : formatMoney(m.current_price)}</td>
                                    <td className="num"><Icon name="chevron-right" size={16} className="chev" /></td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </section>
        </div>
    );
}
