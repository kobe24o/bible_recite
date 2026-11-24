import { createAppleToken } from './apple-distribution.mjs';
import { fileURLToPath } from 'node:url';

export async function submitStoreBuild(api, { appId, platform, version, buildNumber }) {
  if (!['IOS', 'MAC_OS'].includes(platform)) throw new Error('Unsupported store platform');
  const versions = await api('/v1/apps/' + appId + '/appStoreVersions?limit=200');
  const target = versions.data.find(item => item.attributes.platform === platform && item.attributes.versionString === version);
  if (!target) throw new Error('No ' + platform + ' store version ' + version);
  const state = target.attributes.appStoreState;
  if (['WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_APPLE_RELEASE', 'PENDING_DEVELOPER_RELEASE', 'READY_FOR_SALE'].includes(state)) {
    console.log(platform + ' ' + version + ' already submitted: ' + state);
    return target;
  }
  const builds = await api('/v1/builds?' + new URLSearchParams({
    'filter[app]': appId, 'filter[version]': buildNumber, include: 'preReleaseVersion', limit: '200',
  }));
  const build = builds.data.find(item => {
    const pre = builds.included?.find(p => p.id === item.relationships?.preReleaseVersion?.data?.id && p.type === 'preReleaseVersions');
    return pre?.attributes.platform === platform && pre.attributes.version === version &&
      item.attributes.processingState === 'VALID' && !item.attributes.expired;
  });
  if (!build) throw new Error('No valid ' + platform + ' ' + version + ' build ' + buildNumber + '; refusing to attach a different platform or version');
  if (build.attributes.usesNonExemptEncryption === true) throw new Error('Build declares non-exempt encryption; review its export compliance before submission');
  if (build.attributes.usesNonExemptEncryption !== false) await api('/v1/builds/' + build.id, { method: 'PATCH', body: { data: { type: 'builds', id: build.id, attributes: { usesNonExemptEncryption: false } } } });
  await api('/v1/appStoreVersions/' + target.id, { method: 'PATCH', body: { data: {
    type: 'appStoreVersions', id: target.id, attributes: { releaseType: 'AFTER_APPROVAL' },
    relationships: { build: { data: { type: 'builds', id: build.id } } },
  } } });
  const submissions = await api('/v1/apps/' + appId + '/reviewSubmissions?' + new URLSearchParams({
    'filter[platform]': platform, limit: '200',
  }));
  let submission;
  for (const candidate of submissions.data.filter(s => s.attributes.state === 'READY_FOR_REVIEW')) {
    const items = await api('/v1/reviewSubmissions/' + candidate.id + '/items?limit=200');
    if (items.data.length === 0 || items.data.every(item => item.relationships?.appStoreVersion?.data?.id === target.id)) {
      submission = candidate;
      if (items.data.length) submission.hasVersion = true;
      break;
    }
  }
  if (!submission) submission = (await api('/v1/reviewSubmissions', { method: 'POST', body: { data: {
    type: 'reviewSubmissions', attributes: { platform },
    relationships: { app: { data: { type: 'apps', id: appId } } },
  } } })).data;
  if (!submission.hasVersion) await api('/v1/reviewSubmissionItems', { method: 'POST', body: { data: {
    type: 'reviewSubmissionItems', relationships: {
      reviewSubmission: { data: { type: 'reviewSubmissions', id: submission.id } },
      appStoreVersion: { data: { type: 'appStoreVersions', id: target.id } },
    },
  } } });
  const result = await api('/v1/reviewSubmissions/' + submission.id, { method: 'PATCH', body: { data: {
    type: 'reviewSubmissions', id: submission.id, attributes: { submitted: true },
  } } });
  console.log('Submitted ' + platform + ' ' + version + ' build ' + buildNumber + ' for App Review; release after approval. State: ' + result.data.attributes.state);
  return result.data;
}

async function main() {
  const required = name => { if (!process.env[name]) throw new Error('Missing ' + name); return process.env[name]; };
  const credentials = { issuerId: required('APPSTORE_ISSUER_ID'), keyId: required('APPSTORE_API_KEY_ID'), privateKey: required('APPSTORE_API_PRIVATE_KEY') };
  const api = async (path, options = {}) => {
    const response = await fetch('https://api.appstoreconnect.apple.com' + path, {
      method: options.method ?? 'GET', headers: { Authorization: 'Bearer ' + createAppleToken(credentials), 'Content-Type': 'application/json' },
      body: options.body ? JSON.stringify(options.body) : undefined,
    });
    if (response.status === 204) return null;
    const data = await response.json();
    if (!response.ok) throw new Error('Apple API ' + response.status + ' ' + path + ': ' + JSON.stringify(data.errors));
    return data;
  };
  const apps = await api('/v1/apps?filter[bundleId]=app.biblerecite');
  const app = apps.data[0];
  if (!app) throw new Error('App not found');
  await submitStoreBuild(api, { appId: app.id, platform: required('STORE_PLATFORM'), version: required('STORE_VERSION'), buildNumber: required('STORE_BUILD_NUMBER') });
}
if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch(error => { console.error(error.message); process.exitCode = 1; });
