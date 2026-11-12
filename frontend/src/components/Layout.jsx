// =====================================================================
// FILE        : frontend/src/components/Layout.jsx
// WHAT IT DOES: The frame around every page: the sidebar (brand, navigation,
//               database status) on the left and the current page on the right.
// DEPENDS ON  : react-router (NavLink, Link, Outlet), api.js, Icon.jsx
// USED BY     : App.jsx (the parent route of all pages).
// =====================================================================

import { useEffect, useState } from "react";
import { Link, NavLink, Outlet } from "react-router";
import { api } from "../api.js";
import Icon, { BrandMark } from "./Icon.jsx";

// The navigation links: address, label and icon. Edit this list to add a page.
const NAV_ITEMS = [
    { to: "/", label: "Dashboard", icon: "dashboard" },
    { to: "/sale", label: "Sale", icon: "receipt" },
    { to: "/purchase", label: "Purchase", icon: "box" },
    { to: "/medicines", label: "Medicines", icon: "pill" },
    { to: "/suppliers", label: "Suppliers", icon: "truck" },
    { to: "/reports", label: "Reports", icon: "chart" },
];

export default function Layout() {
    // "checking" -> "ok" or "down": is the backend (and MySQL behind it) reachable?
    const [health, setHealth] = useState("checking");

    // Ask /health once when the app opens. The result shows at the bottom of the sidebar.
    useEffect(() => {
        api.getHealth()
            .then(() => setHealth("ok"))
            .catch(() => setHealth("down"));
    }, []);

    return (
        <div className="app">
            <aside className="sidebar">
                {/* Brand: links back to the dashboard */}
                <Link to="/" className="brand">
                    <BrandMark />
                    <span>
                        Pharmacy Inventory
                        <small>City Care Pharmacy</small>
                    </span>
                </Link>

                {/* NavLink adds aria-current="page" on the active link; the CSS highlights it */}
                <nav className="nav" aria-label="Main">
                    {NAV_ITEMS.map((item) => (
                        // "end" on "/" so the Dashboard link is only active on exactly "/"
                        <NavLink key={item.to} to={item.to} end={item.to === "/"}>
                            <Icon name={item.icon} />
                            <span>{item.label}</span>
                        </NavLink>
                    ))}
                </nav>

                {/* Database status, useful during the demo */}
                <div className="sidebar-foot">
                    <span className={"health " + health}>
                        <i />
                        {health === "ok" && "MySQL connected"}
                        {health === "down" && "Backend offline"}
                        {health === "checking" && "Checking database..."}
                    </span>
                    <span>Pune, Maharashtra</span>
                </div>
            </aside>

            {/* Outlet = the place where the current page (Dashboard, Sale ...) is drawn */}
            <main className="main">
                <Outlet />
            </main>
        </div>
    );
}
