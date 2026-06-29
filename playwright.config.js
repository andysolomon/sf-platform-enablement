// Playwright config for the staging-install e2e gate (CI template runs `npx playwright test`).
// testMatch is '**/*.e2e.js' so sfdx-lwc-jest (which globs *.test.js) never sweeps these
// files — avoids the jsdom crash the todo-app hit. CJS (no "type":"module" in package.json).
const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './e2e',
  testMatch: '**/*.e2e.js',
  timeout: 30000,
});
