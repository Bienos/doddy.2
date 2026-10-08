# Copy/paste when M0 has been reviewed — M1
Only proceed if M0 build and owner-reviewed decisions exist. Read `docs/architecture/MEMORY_AND_DATA.md`, `docs/product/PRODUCT_REQUIREMENTS.md`, `docs/quality/ACCEPTANCE_TESTS.md` and ticket IDs M1-001 through M1-007 from `docs/implementation/TICKETS.csv`.

Implement a real vertical slice: explicit text capture → validated transactional local SQLite/GRDB save → persisted screen and source metadata → restart → source-grounded lexical recall → edit while preserving original → copy/export → confirmed delete. Add failure injection for database locked/disk/migration errors, index invalidation and data-protection testing instructions. Never display "Saved" before write succeeded; never hallucinate recall records. No cloud backend, voice or action integrations.

Run actual unit, integration and available UI tests. Provide file diff/changed list, acceptance matrix evidence and remaining physical-device checks. Stop without beginning M2.
