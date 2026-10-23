import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const docker = (...args) => execFileSync('docker', args, {
  cwd: root, encoding: 'utf8', timeout: 120_000, stdio: ['ignore', 'pipe', 'pipe'],
}).trim();

function request({ port, host, path = '/', ca, method = 'GET' }) {
  return new Promise((resolve, reject) => {
    const client = ca ? https : http;
    const req = client.request({
      hostname: '127.0.0.1', port, path, method,
      headers: { Host: host, Connection: 'close' },
      ...(ca ? { ca, servername: host } : {}),
      agent: false,
    }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body }));
      res.on('error', reject);
    });
    req.setTimeout(3000, () => req.destroy(new Error('proxy request timed out')));
    req.on('error', reject);
    req.end();
  });
}

test('optimized proxy hostname routing over HTTP and verified HTTPS', { timeout: 180_000 }, async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'indus-web-proxy-'));
  let container;
  t.after(() => {
    try {
      if (container) docker('rm', '--force', '--volumes', container);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  // Exercise the checked-in routing with the production image. Only certificate
  // issuance is changed: a disposable local CA replaces public ACME services.
  const dockerfile = readFileSync(join(root, 'infra/optimized/images/web/Dockerfile'), 'utf8');
  const image = dockerfile.match(/^FROM (caddy:\S+@sha256:[a-f0-9]{64})$/m)?.[1];
  assert.ok(image, 'the production web image must pin Caddy by digest');
  const config = readFileSync(join(root, 'infra/optimized/runtime/Caddyfile'), 'utf8');
  writeFileSync(join(directory, 'Caddyfile'), `{\n  local_certs\n  admin off\n}\n\n${config}`);
  mkdirSync(join(directory, 'site'));
  writeFileSync(join(directory, 'site/index.html'), 'Indus proxy test shell');
  container = docker('run', '--detach', '--rm',
    '--publish', '127.0.0.1::80', '--publish', '127.0.0.1::443',
    '--env', 'INDUS_HOSTNAME=indus.test',
    '--mount', `type=bind,source=${directory},target=/fixtures,readonly`,
    '--mount', `type=bind,source=${join(directory, 'site')},target=/srv,readonly`,
    image, 'caddy', 'run', '--config', '/fixtures/Caddyfile', '--adapter', 'caddyfile');
  const ports = JSON.parse(docker('inspect', '--format', '{{json .NetworkSettings.Ports}}', container));
  const httpPort = Number(ports['80/tcp'][0].HostPort);
  const httpsPort = Number(ports['443/tcp'][0].HostPort);
  let ca;
  const deadline = Date.now() + 30_000;
  for (;;) {
    try {
      ca = docker('exec', container, 'cat', '/data/caddy/pki/authorities/local/root.crt');
      const response = await request({ port: httpsPort, host: 'indus.test', ca });
      assert.equal(response.status, 200);
      break;
    } catch (error) {
      if (Date.now() >= deadline) {
        throw new Error(`Caddy did not become ready:\n${docker('logs', container)}`, { cause: error });
      }
      await delay(200);
    }
  }

  for (const path of [
    '/',
    '/research/AAPL?range=1d&view=chart',
    '/research/BTC%2FUSD?label=hello%20world&next=%2Fportfolio',
    '/api/v1/reports?limit=10',
    '/stream/v1/streams/BTC%2FUSD?cursor=event-1',
    '//other.example/path?next=https%3A%2F%2Fother.example',
  ]) {
    await t.test(`www redirects ${path} to the fixed apex`, async () => {
      const response = await request({ port: httpsPort, host: 'www.indus.test', path, ca });
      assert.equal(response.status, 301);
      assert.equal(response.headers.location, `https://indus.test${path}`);
    });
  }

  await t.test('www mutations redirect before reaching an upstream', async () => {
    const response = await request({
      port: httpsPort, host: 'www.indus.test', path: '/api/v1/reports', method: 'POST', ca,
    });
    assert.equal(response.status, 301);
    assert.equal(response.headers.location, 'https://indus.test/api/v1/reports');
  });

  await t.test('plain HTTP upgrades to HTTPS with its path and query intact', async () => {
    for (const host of ['indus.test', 'www.indus.test']) {
      const response = await request({ port: httpPort, host, path: '/research?symbol=BTC%2FUSD' });
      assert.equal(response.status, 308);
      assert.equal(response.headers.location, `https://${host}/research?symbol=BTC%2FUSD`);
    }
  });

  await t.test('the canonical site still serves the SPA without a redirect loop', async () => {
    for (const path of ['/', '/research/AAPL?range=1d']) {
      const response = await request({ port: httpsPort, host: 'indus.test', path, ca });
      assert.equal(response.status, 200);
      assert.equal(response.headers.location, undefined);
      assert.equal(response.body, 'Indus proxy test shell');
      assert.equal(response.headers['strict-transport-security'], 'max-age=31536000; includeSubDomains');
    }
  });

  await t.test('an unconfigured TLS hostname is rejected', async () => {
    await assert.rejects(request({ port: httpsPort, host: 'unconfigured.test', ca }));
  });
});
