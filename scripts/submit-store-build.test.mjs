import test from 'node:test';
import assert from 'node:assert/strict';
import { submitStoreBuild } from './submit-store-build.mjs';
function fixture(platform = 'IOS') {
  const calls = [];
  const api = async (path, options) => {
    calls.push({ path, options });
    if (path.includes('/appStoreVersions?')) return { data: [
      { id: 'ios-version', attributes: { platform: 'IOS', versionString: '1.2.52', appStoreState: 'PREPARE_FOR_SUBMISSION' } },
      { id: 'mac-version', attributes: { platform: 'MAC_OS', versionString: '1.2.52', appStoreState: 'PREPARE_FOR_SUBMISSION' } },
    ] };
    if (path.startsWith('/v1/builds?')) return { data: [{ id: 'build', attributes: { processingState: 'VALID', expired: false }, relationships: { preReleaseVersion: { data: { id: 'pre' } } } }], included: [{ type: 'preReleaseVersions', id: 'pre', attributes: { platform, version: '1.2.52' } }] };
    if (path.includes('/reviewSubmissions?')) return { data: [] };
    if (path === '/v1/reviewSubmissions') return { data: { id: 'submission' } };
    if (path === '/v1/reviewSubmissions/submission') return { data: { attributes: { state: 'WAITING_FOR_REVIEW' } } };
    return { data: {} };
  };
  return { api, calls };
}
for (const platform of ['IOS', 'MAC_OS']) test('submits only the requested ' + platform + ' version and enables release after approval', async () => {
  const { api, calls } = fixture(platform);
  await submitStoreBuild(api, { appId: 'app', platform, version: '1.2.52', buildNumber: '123' });
  const attached = calls.find(c => c.options?.body?.data?.type === 'appStoreVersions');
  assert.equal(attached.options.body.data.id, platform === 'IOS' ? 'ios-version' : 'mac-version');
  assert.equal(attached.options.body.data.attributes.releaseType, 'AFTER_APPROVAL');
  assert.equal(calls.at(-1).options.body.data.attributes.submitted, true);
});
test('rejects the wrong platform before any write', async () => {
  const { api, calls } = fixture('MAC_OS');
  await assert.rejects(submitStoreBuild(api, { appId: 'app', platform: 'IOS', version: '1.2.52', buildNumber: '123' }), /No valid/);
  assert.equal(calls.some(c => c.options?.method), false);
});
test('does not resubmit a version already in review', async () => {
  let calls = 0;
  const api = async () => { calls++; return { data: [{ id: 'version', attributes: { platform: 'IOS', versionString: '1.2.52', appStoreState: 'WAITING_FOR_REVIEW' } }] }; };
  await submitStoreBuild(api, { appId: 'app', platform: 'IOS', version: '1.2.52', buildNumber: '123' });
  assert.equal(calls, 1);
});

test('preserves an existing exempt-encryption declaration', async () => {
  const f = fixture('IOS');
  const api = async (path, options) => {
    const result = await f.api(path, options);
    if (path.startsWith('/v1/builds?')) result.data[0].attributes.usesNonExemptEncryption = false;
    return result;
  };
  await submitStoreBuild(api, { appId: 'app', platform: 'IOS', version: '1.2.52', buildNumber: '123' });
  assert.equal(f.calls.some(c => c.path === '/v1/builds/build' && c.options?.method === 'PATCH'), false);
});
test('does not override a non-exempt-encryption declaration', async () => {
  const f = fixture('IOS');
  const api = async (path, options) => {
    const result = await f.api(path, options);
    if (path.startsWith('/v1/builds?')) result.data[0].attributes.usesNonExemptEncryption = true;
    return result;
  };
  await assert.rejects(submitStoreBuild(api, { appId: 'app', platform: 'IOS', version: '1.2.52', buildNumber: '123' }), /non-exempt encryption/);
  assert.equal(f.calls.some(c => c.options?.method), false);
});

test('reuses an existing prepared submission with its explicitly included version', async () => {
  const f = fixture('IOS');
  const api = async (path, options) => {
    if (path.includes('/reviewSubmissions?')) return { data: [{ id: 'prepared', attributes: { state: 'READY_FOR_REVIEW' } }] };
    if (path.startsWith('/v1/reviewSubmissions/prepared/items')) {
      assert.equal(new URLSearchParams(path.split('?')[1]).get('include'), 'appStoreVersion');
      return { data: [{ id: 'item', relationships: { appStoreVersion: { data: { id: 'ios-version' } } } }] };
    }
    if (path === '/v1/reviewSubmissions/prepared') {
      assert.equal(options.body.data.attributes.submitted, true);
      return { data: { attributes: { state: 'WAITING_FOR_REVIEW' } } };
    }
    return f.api(path, options);
  };
  await submitStoreBuild(api, { appId: 'app', platform: 'IOS', version: '1.2.52', buildNumber: '123' });
  assert.equal(f.calls.some(c => c.path === '/v1/reviewSubmissions' || c.path === '/v1/reviewSubmissionItems'), false);
});
