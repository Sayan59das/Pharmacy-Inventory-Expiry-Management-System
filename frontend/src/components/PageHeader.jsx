// =====================================================================
// FILE        : frontend/src/components/PageHeader.jsx
// WHAT IT DOES: The top of every page: an optional "back" link, the title,
//               a subtitle, and buttons on the right.
// DEPENDS ON  : react-router (Link), Icon.jsx
// USED BY     : every page.
//
// USAGE: <PageHeader title="Medicines" subtitle="25 medicines" back={{ to: "/", label: "Dashboard" }}>
//            <button>...</button>      <- children = the buttons on the right
//        </PageHeader>
// =====================================================================

import { Link } from "react-router";
import Icon from "./Icon.jsx";

export default function PageHeader({ title, subtitle, back, badge, children }) {
    return (
        <header className="page-header no-print">
            <div className="titles">
                {/* Optional link to the previous page */}
                {back && (
                    <Link to={back.to} className="back-link">
                        <Icon name="chevron-left" size={16} />
                        {back.label}
                    </Link>
                )}
                {/* Title with an optional badge beside it (for example "Rx") */}
                <div className="title-row">
                    <h1>{title}</h1>
                    {badge}
                </div>
                {subtitle && <p className="subtitle">{subtitle}</p>}
            </div>
            {/* Buttons, only when the page passes some */}
            {children && <div className="actions">{children}</div>}
        </header>
    );
}
