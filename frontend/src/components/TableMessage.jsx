// =====================================================================
// FILE        : frontend/src/components/TableMessage.jsx
// WHAT IT DOES: One full-width table row that shows a message instead of data:
//               "Loading..." while waiting, or an "empty" text when there are no rows.
// DEPENDS ON  : nothing.
// USED BY     : every table in the pages.
//
// USAGE: <TableMessage colSpan={5} loading={x.loading} empty="No alerts." />
//        It returns nothing when there is data to show (loading=false and isEmpty=false).
// =====================================================================

export default function TableMessage({ colSpan, loading, isEmpty, empty }) {
    // Still waiting for the backend.
    if (loading) {
        return (
            <tr className="table-message">
                <td colSpan={colSpan}>Loading...</td>
            </tr>
        );
    }
    // The answer arrived but has no rows.
    if (isEmpty) {
        return (
            <tr className="table-message">
                <td colSpan={colSpan}>{empty}</td>
            </tr>
        );
    }
    // There is data: show nothing.
    return null;
}
