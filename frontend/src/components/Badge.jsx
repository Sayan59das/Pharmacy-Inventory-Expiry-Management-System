// =====================================================================
// FILE        : frontend/src/components/Badge.jsx
// WHAT IT DOES: Small coloured labels. Colour is never used alone: every badge
//               always shows a word too (accessibility rule from PRODUCT.md).
//               Also turns the database's status codes into readable labels.
// DEPENDS ON  : nothing.
// USED BY     : the dashboard, medicines, reports and sale pages.
// =====================================================================

// Badge: <Badge tone="amber">Low stock</Badge>. tone = amber | red | green | blue | gray
export default function Badge({ tone = "gray", children }) {
    return <span className={"badge " + tone}>{children}</span>;
}

// Alert type from MySQL (stock_alert.alert_type) -> label and colour.
const ALERT_LOOK = {
    LOW_STOCK: { tone: "amber", label: "Low stock" },
    NEAR_EXPIRY: { tone: "amber", label: "Near expiry" },
    EXPIRED: { tone: "red", label: "Expired" },
};
export function AlertBadge({ type }) {
    const look = ALERT_LOOK[type] || { tone: "gray", label: type };
    return <Badge tone={look.tone}>{look.label}</Badge>;
}

// Batch expiry status from MySQL (v_batch_details.expiry_status) -> label and colour.
const EXPIRY_LOOK = {
    EXPIRED: { tone: "red", label: "Expired" },
    NEAR_EXPIRY: { tone: "amber", label: "Near expiry" },
    OK: { tone: "green", label: "OK" },
};
export function ExpiryBadge({ status }) {
    const look = EXPIRY_LOOK[status] || { tone: "gray", label: status };
    return <Badge tone={look.tone}>{look.label}</Badge>;
}

// Stock status from MySQL (v_medicine_catalog.stock_status) -> label and colour.
const STOCK_LOOK = {
    OUT: { tone: "red", label: "Out of stock" },
    LOW: { tone: "amber", label: "Low" },
    OK: { tone: "green", label: "In stock" },
};
export function StockBadge({ status }) {
    const look = STOCK_LOOK[status] || { tone: "gray", label: status };
    return <Badge tone={look.tone}>{look.label}</Badge>;
}
