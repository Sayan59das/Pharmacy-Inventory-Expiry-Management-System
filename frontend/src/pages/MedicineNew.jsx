// =====================================================================
// FILE        : frontend/src/pages/MedicineNew.jsx
// WHAT IT DOES: The "Add medicine" page: an empty MedicineForm. After saving,
//               it opens the new medicine's page.
// DEPENDS ON  : api.js, useLoad.js, components (PageHeader, MedicineForm, Toast)
// USED BY     : App.jsx (address "/medicines/new")
// MYSQL BEHIND IT: INSERT INTO medicine (UNIQUE and CHECK rules reject bad data).
// =====================================================================

import { useNavigate } from "react-router";
import { api } from "../api.js";
import { useLoad } from "../useLoad.js";
import { useToast } from "../components/Toast.jsx";
import PageHeader from "../components/PageHeader.jsx";
import MedicineForm from "../components/MedicineForm.jsx";

export default function MedicineNew() {
    const navigate = useNavigate();
    const showToast = useToast();
    // The categories for the drop-down.
    const categories = useLoad(() => api.getCategories(), []);

    // Called by the form with the filled-in values.
    async function handleSave(medicine) {
        try {
            const result = await api.addMedicine(medicine);          // POST /medicines
            showToast(medicine.medicine_name + " added");
            navigate("/medicines/" + result.medicine_id);             // open the new medicine
        } catch (error) {
            // e.g. "This medicine from this manufacturer already exists."
            showToast(error.message, "error");
        }
    }

    return (
        <div className="page">
            <PageHeader title="Add medicine" back={{ to: "/medicines", label: "Medicines" }}
                subtitle="Stock is added later, on the Purchase page, as batches." />
            <section className="card">
                <div className="card-header"><h2>Details</h2></div>
                {/* key: draw the form only after the categories arrived, so the drop-down is filled */}
                <MedicineForm key={categories.data.length} initial={null} categories={categories.data}
                    onSave={handleSave} submitLabel="Add medicine" />
            </section>
        </div>
    );
}
