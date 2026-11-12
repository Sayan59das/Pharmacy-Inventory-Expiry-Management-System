// =====================================================================
// FILE        : frontend/src/components/Icon.jsx
// WHAT IT DOES: A small set of line icons drawn in SVG (no icon library).
//               Every icon uses the same 24x24 grid and the same 1.75px stroke,
//               so they look like one family. Usage: <Icon name="pill" />
// DEPENDS ON  : nothing.
// USED BY     : Layout.jsx, PageHeader buttons, StatCard, tables and toasts.
// =====================================================================

// Each icon is a list of SVG shapes (paths, circles, rectangles) inside the 24x24 box.
const ICONS = {
    // 4 squares = overview
    dashboard: (<><rect x="3.5" y="3.5" width="7" height="7" rx="1.5" /><rect x="13.5" y="3.5" width="7" height="7" rx="1.5" /><rect x="3.5" y="13.5" width="7" height="7" rx="1.5" /><rect x="13.5" y="13.5" width="7" height="7" rx="1.5" /></>),
    // a capsule, tilted
    pill: (<><path d="M10.5 20.5a5 5 0 0 1-7.07-7.07l9-9a5 5 0 0 1 7.07 7.07z" /><path d="M8 8l8 8" /></>),
    // a delivery truck
    truck: (<><path d="M2.5 6.5h11v10h-11z" /><path d="M13.5 9.5h4l3 3.2v3.8h-7" /><circle cx="6.5" cy="17.5" r="2" /><circle cx="17" cy="17.5" r="2" /></>),
    // a parcel box = stock arriving
    box: (<><path d="M3.5 7.5 12 3.5l8.5 4v9L12 20.5l-8.5-4z" /><path d="M3.5 7.5 12 11.5l8.5-4" /><path d="M12 11.5v9" /></>),
    // a paper receipt = sale / bill
    receipt: (<><path d="M6 3h12v18l-3-2-3 2-3-2-3 2z" /><path d="M9 8h6M9 12h6M9 16h3" /></>),
    // a bar chart = reports
    chart: (<><path d="M3.5 20.5h17" /><path d="M7 16.5v-5M12 16.5V6.5M17 16.5v-3" /></>),
    plus: (<path d="M12 5v14M5 12h14" />),
    search: (<><circle cx="11" cy="11" r="6.5" /><path d="m20 20-4.2-4.2" /></>),
    printer: (<><path d="M7 9V3.5h10V9" /><rect x="3.5" y="9" width="17" height="8" rx="2" /><path d="M7 14h10v6.5H7z" /></>),
    refresh: (<><path d="M20.5 12a8.5 8.5 0 1 1-2.5-6" /><path d="M20.5 3.5V9H15" /></>),
    check: (<path d="m5 12.5 4.5 4.5L19 7.5" />),
    "check-circle": (<><circle cx="12" cy="12" r="9" /><path d="m8 12.5 3 3 5-6" /></>),
    // a triangle with "!" = warning / low stock
    alert: (<><path d="M12 3.5 21.5 20h-19z" /><path d="M12 10v4.5" /><path d="M12 17.3v.2" /></>),
    // a clock = expiring soon
    clock: (<><circle cx="12" cy="12" r="9" /><path d="M12 7v5.2l3.3 2" /></>),
    // a circle with a cross = expired / error
    "x-circle": (<><circle cx="12" cy="12" r="9" /><path d="m9 9 6 6M15 9l-6 6" /></>),
    // a rupee note = money
    rupee: (<><rect x="2.5" y="6" width="19" height="12" rx="2" /><path d="M9.5 9.5h5M9.5 12h5M11.5 9.5c2.5 0 2.5 4.5 0 4.5l2.5 2.5" /></>),
    "arrow-right": (<path d="M5 12h14M13 6l6 6-6 6" />),
    "chevron-right": (<path d="m9 6 6 6-6 6" />),
    "chevron-left": (<path d="m15 6-6 6 6 6" />),
    trash: (<><path d="M4 7h16" /><path d="M9.5 7V4.5h5V7" /><path d="m6 7 1 13h10l1-13" /></>),
    user: (<><circle cx="12" cy="8" r="4" /><path d="M4.5 20.5c1.4-3.6 4.4-5.5 7.5-5.5s6.1 1.9 7.5 5.5" /></>),
    info: (<><circle cx="12" cy="12" r="9" /><path d="M12 11v5.5" /><path d="M12 7.8v.2" /></>),
};

// The component: draws one icon by name, at the given size (default 18px).
// aria-hidden="true": icons are decoration, screen readers read the text next to them instead.
export default function Icon({ name, size = 18, className = "" }) {
    return (
        <svg
            className={className}
            width={size}
            height={size}
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
        >
            {ICONS[name]}
        </svg>
    );
}

// The brand mark: a blue rounded square with a white plus (also used as the tab icon).
export function BrandMark({ size = 30 }) {
    return (
        <svg width={size} height={size} viewBox="0 0 32 32" aria-hidden="true">
            <rect width="32" height="32" rx="8" fill="#2563eb" />
            <path d="M16 9v14M9 16h14" stroke="#fff" strokeWidth="3.2" strokeLinecap="round" />
        </svg>
    );
}
