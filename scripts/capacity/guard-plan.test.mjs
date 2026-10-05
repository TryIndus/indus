import assert from 'node:assert/strict';
import { test } from 'node:test';
import { evaluatePlan, isCapacityOnlyFailure } from './guard-plan.mjs';

const target = {
  address: 'aws_db_instance.this',
  type: 'aws_db_instance',
  attribute: 'instance_class',
  desired: 'db.t4g.micro',
};

const change = (overrides = {}) => ({
  address: target.address,
  type: target.type,
  mode: 'managed',
  change: {
    actions: ['update'],
    before: { instance_class: 'db.t4g.small', identifier: 'indus-optimized' },
    after: { instance_class: 'db.t4g.micro', identifier: 'indus-optimized' },
    after_unknown: {},
  },
  ...overrides,
});

test('accepts only the approved in-place size change', () => {
  assert.equal(evaluatePlan({ resource_changes: [change()] }, target), 'apply');
  const settled = change({
    change: {
      actions: ['no-op'],
      before: { instance_class: 'db.t4g.micro' },
      after: { instance_class: 'db.t4g.micro' },
    },
  });
  assert.equal(evaluatePlan({ resource_changes: [settled] }, target), 'no-op');
  assert.throws(() => evaluatePlan({ resource_changes: [] }, target));
});

test('rejects replacements, extra resources, and unrelated drift', () => {
  const plan = (resource) => ({ resource_changes: [resource] });
  assert.throws(() => evaluatePlan(plan(change({ change: { ...change().change, actions: ['delete', 'create'] } })), target));
  assert.throws(() => evaluatePlan({ resource_changes: [change(), change({ address: 'aws_instance.host' })] }, target));
  assert.throws(() => evaluatePlan(plan(change({ change: { ...change().change, after: { instance_class: 'db.t4g.micro', identifier: 'other' } } })), target));
  assert.throws(() => evaluatePlan(plan(change({ change: { ...change().change, after: { instance_class: 'db.t4g.small', identifier: 'indus-optimized' } } })), target));
  assert.throws(() => evaluatePlan(plan(change({ change: { ...change().change, after_unknown: { endpoint: true } } })), target));
});

test('treats only a single recognized capacity error as retryable', () => {
  const codes = ['InsufficientDBInstanceCapacity', 'InsufficientInstanceCapacity'];
  assert.equal(isCapacityOnlyFailure('Error: updating RDS: InsufficientDBInstanceCapacity: no capacity', codes), true);
  assert.equal(isCapacityOnlyFailure('Error: AccessDenied', codes), false);
  assert.equal(isCapacityOnlyFailure('Error: InsufficientDBInstanceCapacity\nError: AccessDenied', codes), false);
});
