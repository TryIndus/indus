import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ensureCompletionIssue } from './notify-completion.mjs';

const options = {
  repository: 'TryIndus/indus', token: 'test-token', targetId: 'optimized-rds-class',
  desired: 'db.t4g.micro', assignee: 'vicdenz', result: 'applied', runUrl: 'https://github.com/TryIndus/indus/actions/runs/1',
};
const response = (value, status = 200) => ({ ok: status >= 200 && status < 300, status, json: async () => value });

test('creates and assigns a completion issue when the target is reached', async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    return url.includes('?') ? response([]) : response({ html_url: 'https://github.com/TryIndus/indus/issues/1' }, 201);
  };
  assert.deepEqual(await ensureCompletionIssue({ ...options, fetchImpl }), {
    status: 'created', url: 'https://github.com/TryIndus/indus/issues/1',
  });
  assert.equal(calls.length, 2);
  assert.deepEqual(JSON.parse(calls[1].init.body).assignees, ['vicdenz']);
});

test('a later no-op run recovers an existing issue without creating another', async () => {
  const fetchImpl = async () => response([{ title: 'Capacity target reached: optimized-rds-class -> db.t4g.micro', html_url: 'https://github.com/TryIndus/indus/issues/1' }]);
  assert.deepEqual(await ensureCompletionIssue({ ...options, result: 'no-op', fetchImpl }), {
    status: 'existing', url: 'https://github.com/TryIndus/indus/issues/1',
  });
});

test('finds an older completion issue beyond the first page', async () => {
  const fetchImpl = async (url) => response(new URL(url).searchParams.get('page') === '1'
    ? Array.from({ length: 100 }, (_, index) => ({ title: `Other issue ${index}` }))
    : [{ title: 'Capacity target reached: optimized-rds-class -> db.t4g.micro', html_url: 'https://github.com/TryIndus/indus/issues/1' }]);
  assert.equal((await ensureCompletionIssue({ ...options, fetchImpl })).status, 'existing');
});

test('recovers when issue creation succeeds but its response is lost', async () => {
  let calls = 0;
  const fetchImpl = async (url) => {
    calls += 1;
    if (url.includes('?')) return response(calls === 1 ? [] : [{ title: 'Capacity target reached: optimized-rds-class -> db.t4g.micro', html_url: 'https://github.com/TryIndus/indus/issues/1' }]);
    throw new Error('network timeout');
  };
  assert.equal((await ensureCompletionIssue({ ...options, fetchImpl })).status, 'existing');
  assert.equal(calls, 3);
});

test('fails when notification cannot be created or verified, allowing the next run to retry', async () => {
  const fetchImpl = async (url) => url.includes('?') ? response([]) : response({}, 500);
  await assert.rejects(ensureCompletionIssue({ ...options, fetchImpl }), /HTTP 500/);
});
