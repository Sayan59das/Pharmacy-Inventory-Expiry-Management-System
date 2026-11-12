// =====================================================================
// FILE        : frontend/src/components/Toast.jsx
// WHAT IT DOES: Short pop-up messages ("toasts") at the bottom of the screen:
//               dark for success, red for errors (for example a refusal from MySQL).
//               ToastProvider keeps the list of messages; useToast() gives any
//               component the function showToast(message, type).
// DEPENDS ON  : react, Icon.jsx
// USED BY     : main.jsx (wraps the app in <ToastProvider>) and every page.
//
// REACT CONCEPT - CONTEXT: a context lets a value (here: showToast) be read by
// any component deep in the tree without passing it through every parent.
// =====================================================================

import { createContext, useCallback, useContext, useState } from "react";
import Icon from "./Icon.jsx";

// The context object. Its value will be the showToast function.
const ToastContext = createContext(() => {});

export function ToastProvider({ children }) {
    // The messages currently on screen: [{ id, message, type }, ...]
    const [toasts, setToasts] = useState([]);

    // showToast adds a message and removes it again after a few seconds.
    // useCallback keeps the same function object between draws (other hooks depend on it).
    const showToast = useCallback((message, type = "success") => {
        // A unique id so React can tell the messages apart.
        const id = Date.now() + Math.random();
        setToasts((current) => [...current, { id, message, type }]);
        // Errors stay longer (8 s) so they can be read; success messages 4 s.
        setTimeout(() => {
            setToasts((current) => current.filter((toast) => toast.id !== id));
        }, type === "error" ? 8000 : 4000);
    }, []);

    return (
        <ToastContext.Provider value={showToast}>
            {children}
            {/* aria-live="polite": screen readers announce new messages */}
            <div className="toasts" aria-live="polite">
                {toasts.map((toast) => (
                    <div key={toast.id} className={"toast" + (toast.type === "error" ? " error" : "")} role="status">
                        <Icon name={toast.type === "error" ? "x-circle" : "check-circle"} />
                        <span>{toast.message}</span>
                    </div>
                ))}
            </div>
        </ToastContext.Provider>
    );
}

// useToast: call it inside a component to get showToast.
export function useToast() {
    return useContext(ToastContext);
}
