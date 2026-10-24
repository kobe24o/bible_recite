import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { createAppleToken, ensureMacStoreVersion } from './apple-distribution.mjs';

test('API JWT has an Apple audience, short expiry and valid P-256 signature', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const token = createAppleToken({ issuerId: 'issuer', keyId: 'key-id', privateKey, now: 1000 });
  const [header, body, signature] = token.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), { alg: 'ES256', kid: 'key-id', typ: 'JWT' });
  assert.deepEqual(JSON.parse(Buffer.from(body, 'base64url')), { iss: 'issuer', aud: 'appstoreconnect-v1', iat: 1000, exp: 1600 });
  assert.equal(verify('SHA256', Buffer.from(`${header}.${body}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')), true);
});

test('Mac store preparation never reuses or changes an iOS version', async () => {
  const calls = [];
  const api = async (path, options) => {
    calls.push({ path, options });
    if (!options) return { data: [{ id: 'ios', attributes: { platform: 'IOS', versionString: '1.2.50' } }] };
    return { data: { id: 'mac-new', attributes: options.body.data.attributes } };
  };
  const version = await ensureMacStoreVersion(api, 'app-id', '1.2.50');
  assert.equal(version.id, 'mac-new');
  assert.equal(calls[1].options.body.data.attributes.platform, 'MAC_OS');
  assert.equal(calls[1].options.body.data.attributes.releaseType, 'MANUAL');
  assert.equal(calls[1].options.body.data.relationships.app.data.id, 'app-id');
});

test('repeated store preparation reuses the same Mac version', async () => {
  let calls = 0;
  const existing = { id: 'mac-existing', attributes: { platform: 'MAC_OS', versionString: '1.2.50' } };
  const result = await ensureMacStoreVersion(async () => { calls++; return { data: [existing] }; }, 'app-id', '1.2.50');
  assert.equal(result.id, 'mac-existing');
  assert.equal(calls, 1);
});
