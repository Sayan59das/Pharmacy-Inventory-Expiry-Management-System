// =====================================================================
// FILE        : frontend/src/utils.js
// WHAT IT DOES: Small helper functions that FORMAT values for display:
//               money, numbers and dates. They never calculate business rules.
// DEPENDS ON  : nothing.
// USED BY     : the pages and components.
// =====================================================================

// formatMoney: 1234.5 -> "₹1,234.50" with Indian digit grouping (1,00,000).
// "₹" is the rupee sign written as a code, so it survives any file encoding.
export function formatMoney(value) {
    const number = Number(value || 0);
    return "₹" + number.toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// formatNumber: 12345 -> "12,345" (Indian grouping, no decimals).
export function formatNumber(value) {
    return Number(value || 0).toLocaleString("en-IN");
}

// formatDate: "2026-11-30" (or "2026-11-30T10:15:00") -> "30 Nov 2026".
export function formatDate(value) {
    if (!value) {
        return "";
    }
    // Read only the date part and treat it as local midnight, so no time-zone shift happens.
    const date = new Date(String(value).substring(0, 10) + "T00:00:00");
    return date.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

// formatDateTime: "2026-11-12T10:15:00" -> "12 Nov 2026, 10:15 am".
export function formatDateTime(value) {
    if (!value) {
        return "";
    }
    return new Date(value).toLocaleString("en-IN", {
        day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit",
    });
}

// formatShortDateTime: "2026-11-12T14:41:00" -> "12 Nov, 2:41 pm" (no year, for compact tables).
export function formatShortDateTime(value) {
    if (!value) {
        return "";
    }
    return new Date(value).toLocaleString("en-IN", { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" });
}

// longToday: today as "Thursday, 12 November 2026" (for page subtitles).
export function longToday() {
    return new Date().toLocaleDateString("en-IN", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
}

// todayIso: today as "YYYY-MM-DD", the format an <input type="date"> uses.
export function todayIso() {
    const now = new Date();
    // getMonth() starts at 0, so add 1; padStart turns "5" into "05".
    const month = String(now.getMonth() + 1).padStart(2, "0");
    const day = String(now.getDate()).padStart(2, "0");
    return now.getFullYear() + "-" + month + "-" + day;
}
