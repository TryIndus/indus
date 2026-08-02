#!/usr/bin/env bash
set -Eeuo pipefail

echo "Running static analysis and production build"
bun run test:static

echo "Running unit tests with coverage thresholds"
bun run test:unit:coverage

echo "Running database migration, RLS, and quota tests"
bun run test:database

echo "Running application integration tests"
bun run test:integration

echo "Running accessibility checks"
bun run test:accessibility

echo "Running authenticated browser and accessibility checks"
bun run test:authenticated

echo "Preparing the production server for browser and performance checks"
bun run build

echo "Running cross-browser product checks"
bun run test:browser:run

echo "Running production-mode performance budgets"
bun run test:performance:run
