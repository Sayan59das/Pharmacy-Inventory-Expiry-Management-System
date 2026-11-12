// =====================================================================
// FILE        : frontend/src/components/BillView.jsx
// WHAT IT DOES: The printable tax invoice of one sale: shop, bill number, customer,
//               every line (with the batch MySQL chose), and the totals with GST
//               split into CGST + SGST. "Print bill" prints only this card.
// DEPENDS ON  : Icon.jsx, utils.js
// USED BY     : pages/Sale.jsx
//
// PROPS
//   bill     : { lines: [...], totals: {...} } exactly as returned by the
//              backend (MySQL procedure sp_generate_bill)
//   onClose  : called when "New sale" is pressed
// =====================================================================

import Icon from "./Icon.jsx";
import { formatDate, formatDateTime, formatMoney } from "../utils.js";

export default function BillView({ bill, onClose }) {
    // Header facts are repeated on every line; take them from the first line.
    const first = bill.lines[0];
    const totals = bill.totals;

    return (
        // id="billPanel": the print style sheet keeps only this card on paper.
        <section className="card bill" id="billPanel" aria-label={"Bill " + totals.sale_id}>
            {/* key: a new bill restarts the "printing" animation */}
            <div className="bill-paper" key={totals.sale_id}>
                <div className="bill-head">
                    <div>
                        <h2>City Care Pharmacy</h2>
                        <p className="shop">Pune, Maharashtra · Tax invoice</p>
                    </div>
                    <div className="bill-no">
                        <span className="note">Bill no.</span>
                        <strong>#{totals.sale_id}</strong>
                        <span className="note">{formatDateTime(first.sale_date)}</span>
                    </div>
                </div>

                <dl className="bill-meta">
                    <div><dt>Customer</dt><dd>{first.customer_name}</dd></div>
                    <div><dt>Phone</dt><dd>{first.customer_phone || "–"}</dd></div>
                    <div><dt>Payment</dt><dd>{first.payment_mode}</dd></div>
                </dl>

                <div className="table-wrap">
                    <table className="table">
                        <thead>
                            <tr>
                                <th>#</th><th>Medicine</th><th>Batch</th><th>Expiry</th>
                                <th className="num">Qty</th><th className="num">MRP</th><th className="num">GST</th><th className="num">Amount</th>
                            </tr>
                        </thead>
                        <tbody>
                            {bill.lines.map((line, index) => (
                                <tr key={index}>
                                    <td className="tabular">{index + 1}</td>
                                    <td className="strong">{line.medicine_name}</td>
                                    <td className="nowrap">{line.batch_no}</td>
                                    <td className="nowrap">{formatDate(line.expiry_date)}</td>
                                    <td className="num">{line.quantity}</td>
                                    <td className="num">{formatMoney(line.unit_price)}</td>
                                    <td className="num">{line.gst_percent}%</td>
                                    <td className="num strong">{formatMoney(line.line_total)}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>

                {/* totals calculated by MySQL (sp_generate_bill) */}
                <div className="bill-totals">
                    <div className="summary-row"><span>Taxable value</span><strong>{formatMoney(totals.taxable_total)}</strong></div>
                    <div className="summary-row"><span>CGST</span><strong>{formatMoney(totals.cgst)}</strong></div>
                    <div className="summary-row"><span>SGST</span><strong>{formatMoney(totals.sgst)}</strong></div>
                    <div className="summary-total"><span>Grand total</span><strong>{formatMoney(totals.grand_total)}</strong></div>
                </div>

                <p className="bill-foot">MRP includes GST. Please check the expiry date before use. Thank you.</p>
            </div>

            {/* buttons are not printed */}
            <div className="bill-actions no-print">
                <button type="button" className="btn btn-primary" onClick={() => window.print()}>
                    <Icon name="printer" size={16} />
                    Print bill
                </button>
                <button type="button" className="btn btn-secondary" onClick={onClose}>New sale</button>
            </div>
        </section>
    );
}
