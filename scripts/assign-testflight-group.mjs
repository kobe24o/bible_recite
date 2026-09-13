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

export async function waitForProcessedBuild(
  queryBuild,
  {
    attemptLimit = 25,
    waitMilliseconds = 60_000,
    sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)),
    logger = console,
  } = {},
) {
  for (let attempt = 1; attempt <= attemptLimit; attempt += 1) {
    const build = await queryBuild();
    const processingState = build?.attributes?.processingState;
    if (processingState === 'VALID') {
      return build;
    }
    if (processingState === 'FAILED' || processingState === 'INVALID') {
      throw new Error(`TestFlight build processing failed (${processingState}).`);
    }
    if (attempt === attemptLimit) {
      break;
    }
    logger.log(
      `Waiting for TestFlight build processing: attempt ${attempt}/${attemptLimit}` +
      (processingState ? ` (${processingState})` : ' (not visible yet)') + '.',
    );
    await sleep(waitMilliseconds);
  }
  throw new Error(`TestFlight build did not become valid after ${attemptLimit} checks.`);
}

export async function recordExemptEncryptionUse(api, buildId) {
  await api(`/v1/builds/${buildId}`, {
    method: 'PATCH',
    body: JSON.stringify({
      data: {
        type: 'builds',
        id: buildId,
        attributes: { usesNonExemptEncryption: false },
      },
    }),
  });
}

async function main() {
  const bundleId = required('IOS_BUNDLE_ID');
  const buildNumber = required('TESTFLIGHT_BUILD_NUMBER');
  const groupName = required('TESTFLIGHT_GROUP_NAME');
  const submitBetaReview = process.env.AUTO_SUBMIT_BETA_REVIEW === 'true';
  const credentials = {
    issuerId: required('APPSTORE_ISSUER_ID'),
    keyId: required('APPSTORE_API_KEY_ID'),
    privateKey: required('APPSTORE_API_PRIVATE_KEY'),
  };

  async function api(path, options = {}) {
    const response = await fetch(`${apiBaseUrl}${path}`, {
      ...options,
      headers: {
        Accept: 'application/json',
        // Build processing can take longer than Apple's JWT lifetime. Sign every
        // request so a long wait cannot leave the handoff with an expired token.
        Authorization: `Bearer ${createToken(credentials)}`,
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

  const buildsPath = `/v1/builds?${new URLSearchParams({
    'filter[app]': app.id,
    'filter[version]': buildNumber,
    limit: '1',
  })}`;
  const build = await waitForProcessedBuild(async () => {
    const builds = await api(buildsPath);
    return builds.data[0];
  });
  await recordExemptEncryptionUse(api, build.id);

  const currentBuilds = await api(`/v1/betaGroups/${targetGroup.id}/relationships/builds?limit=200`);
  if (currentBuilds.data.some((candidate) => candidate.id === build.id)) {
    console.log(`Build ${buildNumber} is already assigned to TestFlight group ${groupName}.`);
  } else {
    await api(`/v1/betaGroups/${targetGroup.id}/relationships/builds`, {
      method: 'POST',
      body: JSON.stringify({
        data: [{ id: build.id, type: 'builds' }],
      }),
    });
    console.log(`Assigned build ${buildNumber} to TestFlight group ${groupName}.`);
  }

  if (!submitBetaReview) {
    return;
  }

  const reviewSubmissions = await api(`/v1/betaAppReviewSubmissions?${new URLSearchParams({
    'filter[build]': build.id,
    limit: '1',
  })}`);
  const existingSubmission = reviewSubmissions.data[0];
  if (existingSubmission) {
    console.log(
      `Build ${buildNumber} already has a Beta App Review submission ` +
        `(${existingSubmission.attributes.betaReviewState}).`,
    );
    return;
  }

  await api('/v1/betaAppReviewSubmissions', {
    method: 'POST',
    body: JSON.stringify({
      data: {
        type: 'betaAppReviewSubmissions',
        relationships: {
          build: {
            data: { id: build.id, type: 'builds' },
          },
        },
      },
    }),
  });
  console.log(`Submitted build ${buildNumber} for Beta App Review.`);
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
}
