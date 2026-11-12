// =====================================================================
// FILE        : frontend/src/App.jsx
// WHAT IT DOES: The list of pages (routes): which component is shown for which
//               address. Every page is drawn inside <Layout>, which adds the
//               sidebar navigation.
// DEPENDS ON  : components/Layout.jsx and every file in pages/.
// USED BY     : main.jsx
// READ ORDER  : 3rd file of the frontend.
// =====================================================================

// Routes holds a list of Route; each Route connects an address (path) to a component (element).
import { Routes, Route } from "react-router";

import Layout from "./components/Layout.jsx";
import Dashboard from "./pages/Dashboard.jsx";
import Medicines from "./pages/Medicines.jsx";
import MedicineDetail from "./pages/MedicineDetail.jsx";
import MedicineNew from "./pages/MedicineNew.jsx";
import Suppliers from "./pages/Suppliers.jsx";
import Purchase from "./pages/Purchase.jsx";
import Sale from "./pages/Sale.jsx";
import Reports from "./pages/Reports.jsx";
import NotFound from "./pages/NotFound.jsx";

export default function App() {
    return (
        <Routes>
            {/* The Layout route has no address of its own: it wraps all pages below it */}
            <Route element={<Layout />}>
                {/* "index" = the home address "/" */}
                <Route index element={<Dashboard />} />
                <Route path="medicines" element={<Medicines />} />
                {/* "new" must come before ":medicineId", otherwise "new" would be read as an id */}
                <Route path="medicines/new" element={<MedicineNew />} />
                {/* ":medicineId" is a URL parameter, e.g. /medicines/7 */}
                <Route path="medicines/:medicineId" element={<MedicineDetail />} />
                <Route path="suppliers" element={<Suppliers />} />
                <Route path="purchase" element={<Purchase />} />
                <Route path="sale" element={<Sale />} />
                <Route path="reports" element={<Reports />} />
                {/* "*" = any other address: show the "page not found" screen */}
                <Route path="*" element={<NotFound />} />
            </Route>
        </Routes>
    );
}
