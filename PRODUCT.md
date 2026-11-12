# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **Pharmacy counter staff** (pharmacist / billing assistant) at a retail chemist in India, working on a desktop or laptop at the counter: billing customers, receiving supplier stock, and checking what is low or about to expire.
- **Evaluators of a college DBMS project**: the 4-member student team demos the site live on a laptop and on a projector during the viva; examiners watch and ask how each screen maps to the database.

## Product Purpose

A pharmacy inventory and expiry management system. It tracks medicines, suppliers, batches (each with its own expiry date), purchases, sales and alerts, so that expired stock is never sold, the earliest-expiring batch is sold first (FEFO), low stock is noticed in time, and every bill is correct with GST. Success: a counter worker can bill, receive stock and see problems at a glance; the team can show that every rule runs inside MySQL.

## Positioning

All business logic lives in MySQL 8 (tables, CHECK constraints, triggers, stored procedures, views, a daily event). The web app is a thin client: it only calls procedures and views through a FastAPI JSON API. Stock is tracked per batch, sales are allocated FEFO by the database, and alerts are raised automatically by triggers and a scheduled event.

## Operating Context

- Daily counter workflow: create a bill (customer or walk-in, payment mode CASH/UPI/CARD, a cart of medicines), print the GST tax invoice, record purchases from suppliers (new batch or top-up of an existing batch), resolve stock alerts.
- Viva workflow: a laptop/projector demo walking through dashboard -> sale (FEFO split across batches) -> a refused sale (insufficient or expired stock) -> purchase -> alerts -> reports.
- Internet is available on the demo machine.

## Capabilities and Constraints

- Pages: Dashboard, Medicines (search, add/edit, batches with expiry status), Suppliers (list, add), Purchase (invoice with item rows), Sale (cart, printable bill, recent bills), Reports (monthly sales, top selling, expiring soon, expired stock, low stock, supplier summary).
- Backend: FastAPI JSON API at `http://127.0.0.1:8000` (endpoints in `backend/routes/`); it must not change for frontend work. Error messages from MySQL (SIGNAL) arrive as `{"detail": "..."}` and must be shown to the user verbatim.
- Frontend stack: React (JSX) with Vite and react-router, as requested by the user; plain CSS, no UI component libraries, so every line can be explained in the viva. Every file starts with a header comment and is commented block by block in plain English.
- Terminology: medicine, batch, batch number, expiry date, MRP (GST-inclusive selling price), FEFO, reorder level, sellable stock (non-expired), walk-in customer, Rx (prescription required), LOW_STOCK / NEAR_EXPIRY / EXPIRED alerts, CGST/SGST.
- Primary screens: laptop/desktop and projector. Phones must work but are not the focus.
- Bills must print cleanly (only the bill is printed).

## Brand Commitments

- Product name shown in the app header: **Pharmacy Inventory**. Full project title: **Pharmacy Inventory & Expiry Management System**.
- Shop name printed on the bill: **City Care Pharmacy** (a sample shop, Pune, Maharashtra).
- Currency: Indian rupee (Rs / the rupee sign), Indian digit grouping.
- Visual direction (chosen by the user on the decision page, Nov 2026): **the category standard**, a clean conventional admin dashboard, executed at the craft level of **Stripe Dashboard** and **Shopify Admin**. Convention is the commitment: no novelty worlds or themed costumes.

## Evidence on Hand

- Sample data in `database/03_sample_data.sql`: 8 suppliers, 6 categories, 25 medicines, 40 batches, 15 purchases, 30 sales, dates relative to today. All data is synthetic demo data.
- Previous plain-HTML screenshots in `docs/screenshots/` (to be replaced after the redesign).
- No real customers, testimonials, logos or metrics exist; none may be invented.

## Product Principles

1. The database is the authority: the screen never decides batches, prices or stock; it shows what MySQL decided, including its refusals.
2. Problems first: low, near-expiry and expired stock must be visible without searching.
3. Counter speed: billing and receiving stock take few steps and read clearly at a glance.
4. Explainable by students: simple components and plain CSS that a second-year student can walk through line by line.

## Accessibility & Inclusion

Projector use demands strong contrast and large, legible numbers; status must never rely on colour alone (always paired with a word).
