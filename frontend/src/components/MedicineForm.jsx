// =====================================================================
// FILE        : frontend/src/components/MedicineForm.jsx
// WHAT IT DOES: The form with a medicine's details (name, generic name,
//               manufacturer, category, reorder level, GST, prescription).
//               Used to ADD a new medicine and to EDIT an existing one.
// DEPENDS ON  : react
// USED BY     : pages/MedicineNew.jsx, pages/MedicineDetail.jsx
//
// PROPS
//   initial     : the medicine to edit, or null for a new one
//   categories  : list of { category_id, category_name } for the drop-down
//   onSave      : async function(medicine) called with the filled-in values
//   submitLabel : text of the save button
//
// REACT CONCEPT - CONTROLLED INPUTS: each input shows a value from React state
// (value={form.x}) and every keystroke updates that state (onChange). So the
// state always holds exactly what is on screen.
// =====================================================================

import { useState } from "react";

// Turn a medicine from the backend (or nothing) into the form's starting values.
function startValues(medicine) {
    return {
        medicine_name: medicine ? medicine.medicine_name : "",
        generic_name: medicine ? medicine.generic_name : "",
        manufacturer: medicine ? medicine.manufacturer : "",
        category_id: medicine ? String(medicine.category_id) : "",
        reorder_level: medicine ? String(medicine.reorder_level) : "10",
        gst_percent: medicine ? String(medicine.gst_percent) : "5",
        requires_prescription: medicine ? Boolean(medicine.requires_prescription) : false,
    };
}

export default function MedicineForm({ initial, categories, onSave, submitLabel }) {
    // All field values in one object.
    const [form, setForm] = useState(() => startValues(initial));
    // true while the save request runs (the button is disabled meanwhile).
    const [saving, setSaving] = useState(false);

    // Change one field: copy the object and replace that one value.
    function setField(name, value) {
        setForm((current) => ({ ...current, [name]: value }));
    }

    // Submit: build the object the backend expects (names match MedicineIn in backend/routes/medicines.py).
    async function handleSubmit(event) {
        event.preventDefault();              // stop the browser from reloading the page
        setSaving(true);
        try {
            await onSave({
                medicine_name: form.medicine_name.trim(),
                generic_name: form.generic_name.trim(),
                manufacturer: form.manufacturer.trim(),
                category_id: Number(form.category_id),
                reorder_level: Number(form.reorder_level),
                gst_percent: Number(form.gst_percent),
                requires_prescription: form.requires_prescription,
            });
        } finally {
            setSaving(false);
        }
    }

    return (
        <form onSubmit={handleSubmit}>
            <div className="card-body">
                <div className="form-grid">
                    <div className="field span-2">
                        <label htmlFor="medicineName">Medicine name with strength</label>
                        <input id="medicineName" className="input" required maxLength={100} placeholder="Paracetamol 500mg"
                            value={form.medicine_name} onChange={(e) => setField("medicine_name", e.target.value)} />
                    </div>
                    <div className="field">
                        <label htmlFor="genericName">Generic name</label>
                        <input id="genericName" className="input" required maxLength={100} placeholder="Paracetamol"
                            value={form.generic_name} onChange={(e) => setField("generic_name", e.target.value)} />
                    </div>
                    <div className="field">
                        <label htmlFor="manufacturer">Manufacturer</label>
                        <input id="manufacturer" className="input" required maxLength={100} placeholder="Cipla"
                            value={form.manufacturer} onChange={(e) => setField("manufacturer", e.target.value)} />
                    </div>
                    <div className="field">
                        <label htmlFor="categoryId">Category</label>
                        <select id="categoryId" className="select" required
                            value={form.category_id} onChange={(e) => setField("category_id", e.target.value)}>
                            <option value="" disabled>Choose a category</option>
                            {categories.map((category) => (
                                <option key={category.category_id} value={category.category_id}>{category.category_name}</option>
                            ))}
                        </select>
                    </div>
                    <div className="field">
                        <label htmlFor="reorderLevel">Reorder level</label>
                        <input id="reorderLevel" className="input num" type="number" min="0" required
                            value={form.reorder_level} onChange={(e) => setField("reorder_level", e.target.value)} />
                        <span className="hint">A LOW_STOCK alert is raised below this.</span>
                    </div>
                    <div className="field">
                        <label htmlFor="gstPercent">GST %</label>
                        <input id="gstPercent" className="input num" type="number" min="0" max="28" step="0.01" required
                            value={form.gst_percent} onChange={(e) => setField("gst_percent", e.target.value)} />
                        <span className="hint">Between 0 and 28.</span>
                    </div>
                    <div className="field">
                        <span className="label">Prescription</span>
                        <label className="checkbox">
                            <input type="checkbox" checked={form.requires_prescription}
                                onChange={(e) => setField("requires_prescription", e.target.checked)} />
                            Requires a doctor's prescription (Rx)
                        </label>
                    </div>
                </div>
            </div>
            <div className="card-foot form-actions">
                <button type="submit" className="btn btn-primary" disabled={saving}>
                    {saving ? "Saving..." : submitLabel}
                </button>
            </div>
        </form>
    );
}
