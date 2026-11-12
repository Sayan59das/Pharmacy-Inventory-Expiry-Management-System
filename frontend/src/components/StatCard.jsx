// =====================================================================
// FILE        : frontend/src/components/StatCard.jsx
// WHAT IT DOES: One number tile (dashboard, monthly report). When "to" is given
//               the whole tile is a link to the report behind the number.
// DEPENDS ON  : react-router (Link), Icon.jsx
// USED BY     : pages/Dashboard.jsx, pages/Reports.jsx
//
// USAGE: <StatCard label="Low stock" value={5} meta="below reorder level"
//                  icon="alert" tone="amber" to="/reports?tab=low" />
// =====================================================================

import { Link } from "react-router";
import Icon from "./Icon.jsx";

export default function StatCard({ label, value, meta, icon, tone, to }) {
    // The inside of the tile is the same whether or not it is a link.
    const content = (
        <>
            <span className="stat-label">
                {label}
                {/* the coloured icon repeats the meaning of the label (never colour alone) */}
                {icon && <Icon name={icon} className={"tone-" + tone} />}
            </span>
            <span className="stat-value">{value}</span>
            {meta && <span className="stat-meta">{meta}</span>}
        </>
    );

    // A tile with a destination becomes a link; otherwise a plain box.
    if (to) {
        return (
            <Link to={to} className="stat">
                {content}
            </Link>
        );
    }
    return <div className="stat">{content}</div>;
}
