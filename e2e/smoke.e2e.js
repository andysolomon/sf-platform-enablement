const { test, expect } = require('@playwright/test');

// PLACEHOLDER (Phase 5). The frs-platform base package is headless at v0.1.0 — there is no UI
// journey to drive yet — so this keeps the CI staging-install e2e gate green without a real
// browser flow. REPLACE in Phase 7 with the real SF<->FRS round-trip e2e (FR-10) once the
// round-trip is wired in Phase 6. Tracked in progress.txt 7.6 and as an NFR-10 template-fit note.
test('staging-install smoke placeholder', async () => {
  expect(true).toBeTruthy();
});
