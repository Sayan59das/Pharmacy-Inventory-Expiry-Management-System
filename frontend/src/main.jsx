// =====================================================================
// FILE        : frontend/src/main.jsx
// WHAT IT DOES: The starting point of the React app. It finds <div id="root">
//               in index.html and draws the <App /> component inside it,
//               wrapped in the router (page addresses) and the toast provider
//               (pop-up messages).
// DEPENDS ON  : App.jsx, components/Toast.jsx, styles.css, react, react-dom, react-router.
// USED BY     : index.html (<script type="module" src="/src/main.jsx">).
// READ ORDER  : 2nd file of the frontend (after index.html).
// =====================================================================

// StrictMode is a development helper that warns about unsafe code (it adds no visible UI).
import { StrictMode } from "react";
// createRoot connects React to a real element of the page.
import { createRoot } from "react-dom/client";
// BrowserRouter lets the app show a different page for each address (/, /sale, /reports ...).
import { BrowserRouter } from "react-router";

// Our own files.
import App from "./App.jsx";
import { ToastProvider } from "./components/Toast.jsx";
// One stylesheet for the whole app (colours, layout, tables, forms, buttons, the printed bill).
import "./styles.css";

// Find the empty <div id="root"> and let React draw everything inside it.
createRoot(document.getElementById("root")).render(
    <StrictMode>
        <BrowserRouter>
            {/* ToastProvider makes showToast() available to every page */}
            <ToastProvider>
                <App />
            </ToastProvider>
        </BrowserRouter>
    </StrictMode>
);
