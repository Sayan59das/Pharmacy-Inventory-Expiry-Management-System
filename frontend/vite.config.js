// =====================================================================
// FILE        : frontend/vite.config.js
// WHAT IT DOES: Settings for Vite, the tool that runs the React app while we
//               develop (npm run dev) and builds it for production (npm run build).
// DEPENDS ON  : the packages "vite" and "@vitejs/plugin-react" (package.json).
// USED BY     : the npm scripts in package.json.
// READ ORDER  : optional - you rarely need to change it.
// =====================================================================

// defineConfig only gives the editor auto-complete; it returns the object unchanged.
import { defineConfig } from "vite";
// The React plugin lets Vite understand JSX (the HTML-like syntax inside .jsx files).
import react from "@vitejs/plugin-react";

export default defineConfig({
    // Turn on JSX support and instant reload of edited components.
    plugins: [react()],
    server: {
        // The development website runs at http://127.0.0.1:5173
        host: "127.0.0.1",
        port: 5173,
        // Fail loudly instead of silently picking another port if 5173 is busy.
        strictPort: true,
    },
});
