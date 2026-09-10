import { createSign } from 'node:crypto';

const apiBaseUrl = 'https://api.appstoreconnect.apple.com';

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function base64UrlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function createToken({ issuerId, keyId, privateKey }) {
  const now = Math.floor(Date.now() / 1000);
  const signingInput = [
    base64UrlJson({ alg: 'ES256', kid: keyId, typ: 'JWT' }),
    base64UrlJson({ aud: 'appstoreconnect-v1', exp: now + 19 * 60, iss: issuerId }),
  ].join('.');
  const signer = createSign('SHA256');
  signer.update(signingInput);
  signer.end();
  const signature = signer.sign(
    {
      dsaEncoding: 'ieee-p1363',
      key: privateKey.replace(/\\n/g, '\n'),
    },
    'base64url',
  );
  return `${signingInput}.${signature}`;
}

async function main() {
  const bundleId = required('IOS_BUNDLE_ID');
  const buildNumber = required('TESTFLIGHT_BUILD_NUMBER');
  const groupName = required('TESTFLIGHT_GROUP_NAME');
  const token = createToken({
    issuerId: required('APPSTORE_ISSUER_ID'),
    keyId: required('APPSTORE_API_KEY_ID'),
    privateKey: required('APPSTORE_API_PRIVATE_KEY'),
  });

  async function api(path, options = {}) {
    const response = await fetch(`${apiBaseUrl}${path}`, {
      ...options,
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        ...options.headers,
      },
    });
    if (response.status === 204) {
      return null;
    }
    const body = await response.json();
    if (!response.ok) {
      throw new Error(`App Store Connect API ${response.status}: ${JSON.stringify(body.errors ?? body)}`);
    }
    return body;
  }

  const apps = await api(`/v1/apps?${new URLSearchParams({
    'filter[bundleId]': bundleId,
    limit: '1',
  })}`);
  const app = apps.data[0];
  if (!app) {
    throw new Error(`No App Store Connect app found for bundle ID ${bundleId}`);
  }

  const groups = await api(`/v1/apps/${app.id}/betaGroups?limit=200`);
  const targetGroup = groups.data.find(
    (group) => group.attributes.name.toLocaleLowerCase() === groupName.toLocaleLowerCase(),
  );
  if (!targetGroup) {
    throw new Error(`No TestFlight group named "${groupName}" was found`);
  }

  const builds = await api(`/v1/builds?${new URLSearchParams({
    'filter[app]': app.id,
    'filter[version]': buildNumber,
    limit: '1',
  })}`);
  const build = builds.data[0];
  if (!build) {
    throw new Error(`Processed TestFlight build ${buildNumber} was not found`);
  }

  const currentBuilds = await api(`/v1/betaGroups/${targetGroup.id}/relationships/builds?limit=200`);
  if (currentBuilds.data.some((candidate) => candidate.id === build.id)) {
    console.log(`Build ${buildNumber} is already assigned to TestFlight group ${groupName}.`);
    return;
  }

  await api(`/v1/betaGroups/${targetGroup.id}/relationships/builds`, {
    method: 'POST',
    body: JSON.stringify({
      data: [{ id: build.id, type: 'builds' }],
    }),
  });
  console.log(`Assigned build ${buildNumber} to TestFlight group ${groupName}.`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
