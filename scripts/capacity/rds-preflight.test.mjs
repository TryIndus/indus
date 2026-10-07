import assert from 'node:assert/strict';
import { test } from 'node:test';
import { assertNoPendingRdsChanges } from './rds-preflight.mjs';

const instance = (pending) => ({
  DBInstances: [{ DBInstanceIdentifier: 'indus-optimized', ...pending }],
});

test('accepts omitted and empty pending RDS modifications', () => {
  assert.doesNotThrow(() => assertNoPendingRdsChanges(instance({}), 'indus-optimized'));
  assert.doesNotThrow(() => assertNoPendingRdsChanges(instance({ PendingModifiedValues: {} }), 'indus-optimized'));
});

test('rejects pending changes and unexpected RDS responses', () => {
  assert.throws(() => assertNoPendingRdsChanges(instance({ PendingModifiedValues: { DBInstanceClass: 'db.t4g.micro' } }), 'indus-optimized'));
  assert.throws(() => assertNoPendingRdsChanges(instance({}), 'another-instance'));
  assert.throws(() => assertNoPendingRdsChanges({ DBInstances: [] }, 'indus-optimized'));
  assert.throws(() => assertNoPendingRdsChanges(instance({ PendingModifiedValues: [] }), 'indus-optimized'));
});
