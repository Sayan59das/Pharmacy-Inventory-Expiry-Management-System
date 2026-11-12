// =====================================================================
// FILE        : frontend/src/useLoad.js
// WHAT IT DOES: A custom React "hook" that loads data from the backend when a
//               component appears, and again whenever reload() is called.
//               It hides the repetitive loading / error / data bookkeeping.
// DEPENDS ON  : react, components/Toast.jsx (to show errors).
// USED BY     : most pages.
//
// HOW TO USE IT
//   const suppliers = useLoad(() => api.getSuppliers(), []);
//   suppliers.data     -> the answer ([] until it arrives)
//   suppliers.loading  -> true while the request is running
//   suppliers.reload() -> ask the backend again (e.g. after saving)
//   A third argument "watch" (a list) makes it reload whenever one of those values changes.
// =====================================================================

import { useCallback, useEffect, useRef, useState } from "react";
import { useToast } from "./components/Toast.jsx";

export function useLoad(loader, initialValue, watch = []) {
    // showToast is used to display an error if the request fails.
    const showToast = useToast();
    // The data itself, starting with initialValue (for example [] or null).
    const [data, setData] = useState(initialValue);
    // true while a request is running, so the page can show "Loading...".
    const [loading, setLoading] = useState(true);
    // Increasing this number triggers a new load (see reload below).
    const [reloadCount, setReloadCount] = useState(0);

    // Keep the newest loader function in a ref, so the effect below always calls the current one.
    const loaderRef = useRef(loader);
    loaderRef.current = loader;

    // useEffect runs after the component is drawn, and again when reloadCount or a watched value changes.
    useEffect(() => {
        // If the component disappears or a newer request starts, this becomes true
        // and the old (out-of-date) answer is ignored.
        let cancelled = false;
        setLoading(true);
        loaderRef.current()
            .then((result) => {
                if (!cancelled) setData(result);
            })
            .catch((error) => {
                if (!cancelled) showToast(error.message, "error");
            })
            .finally(() => {
                if (!cancelled) setLoading(false);
            });
        // The "cleanup" function: React calls it before the next run of this effect.
        return () => {
            cancelled = true;
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [reloadCount, showToast, ...watch]);

    // reload(): ask the backend again. useCallback keeps the same function between draws.
    const reload = useCallback(() => setReloadCount((count) => count + 1), []);

    return { data, loading, reload };
}
