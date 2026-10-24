import { createPrivateKey, sign } from 'node:crypto';
import { appendFileSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export function createAppleToken({ issuerId, keyId, privateKey, now = Math.floor(Date.now() / 1000) }) {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const input = `${encode({ alg: 'ES256', kid: keyId, typ: 'JWT' })}.${encode({ iss: issuerId, aud: 'appstoreconnect-v1', iat: now, exp: now + 600 })}`;
  const key = typeof privateKey === 'string' ? createPrivateKey(privateKey.replace(/\\n/g, '\n')) : privateKey;
  return `${input}.${sign('SHA256', Buffer.from(input), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
}

export async function ensureMacStoreVersion(api, appId, versionString) {
  const result = await api(`/v1/apps/${appId}/appStoreVersions?limit=200`);
  const existing = result.data.find(item => item.attributes.platform === 'MAC_OS' && item.attributes.versionString === versionString);
  if (existing) return existing;
  return (await api('/v1/appStoreVersions', {
    method: 'POST',
    body: { data: { type: 'appStoreVersions', attributes: { platform: 'MAC_OS', versionString, releaseType: 'MANUAL' }, relationships: { app: { data: { type: 'apps', id: appId } } } } },
  })).data;
}

function required(name) {
  if (!process.env[name]) throw new Error(`Missing ${name}`);
  return process.env[name];
}

async function main() {
  const credentials = {
    issuerId: required('APPSTORE_ISSUER_ID'),
    keyId: required('APPSTORE_API_KEY_ID'),
    privateKey: required('APPSTORE_API_PRIVATE_KEY'),
  };
  const api = async (path, options = {}) => {
    const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
      method: options.method ?? 'GET',
      headers: { Authorization: `Bearer ${createAppleToken(credentials)}`, 'Content-Type': 'application/json' },
      body: options.body ? JSON.stringify(options.body) : undefined,
    });
    const data = await response.json();
    if (!response.ok) throw new Error(`Apple API ${response.status} ${path}: ${data.errors?.map(item => `${item.code}: ${item.detail}`).join('; ')}`);
    return data;
  };
  const bundleId = process.env.MACOS_BUNDLE_ID || 'app.biblerecite';
  const apps = await api(`/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}`);
  const app = apps.data[0];
  if (!app) throw new Error(`App Store Connect has no application for ${bundleId}`);
  const output = { appId: app.id, appName: app.attributes.name, bundleId };
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `app_id=${app.id}\n`);
  if (process.argv[2] === 'prepare-store') {
    const versionString = readFileSync('pubspec.yaml', 'utf8').match(/^version:\s*([^+\s]+)/m)[1];
    const version = await ensureMacStoreVersion(api, app.id, versionString);
    output.macVersion = { id: version.id, ...version.attributes };
  } else {
    const [certificates, bundleIds, versions] = await Promise.all([
      api('/v1/certificates?limit=200'),
      api(`/v1/bundleIds?filter[identifier]=${encodeURIComponent(bundleId)}`),
      api(`/v1/apps/${app.id}/appStoreVersions?limit=200`),
    ]);
    output.certificates = certificates.data.map(item => ({ id: item.id, type: item.attributes.certificateType, name: item.attributes.name, expirationDate: item.attributes.expirationDate }));
    output.bundleIds = bundleIds.data.map(item => ({ id: item.id, identifier: item.attributes.identifier, platform: item.attributes.platform }));
    output.versions = versions.data.map(item => ({ id: item.id, platform: item.attributes.platform, version: item.attributes.versionString, state: item.attributes.appStoreState }));
  }
  console.log(JSON.stringify(output, null, 2));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
