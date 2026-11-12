// =====================================================================
// FILE        : frontend/src/pages/NotFound.jsx
// WHAT IT DOES: Shown when the address matches no page (for example /abc).
// DEPENDS ON  : react-router (Link), PageHeader.jsx
// USED BY     : App.jsx (the "*" route)
// =====================================================================

import { Link } from "react-router";
import PageHeader from "../components/PageHeader.jsx";

export default function NotFound() {
    return (
        <div className="page">
            <PageHeader title="Page not found" />
            <div className="card empty">
                <strong>This address does not exist.</strong>
                <Link to="/">Go to the dashboard</Link>
            </div>
        </div>
    );
}
