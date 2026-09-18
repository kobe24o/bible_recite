import assert from 'node:assert/strict';
import test from 'node:test';

import {
  recordExemptEncryptionUse,
  submitBetaReview,
  waitForProcessedBuild,
} from './assign-testflight-group.mjs';

test('records that the uploaded build uses no non-exempt encryption', async () => {
  const requests = [];

  await recordExemptEncryptionUse(async (path, options) => {
    requests.push({ path, options });
    return null;
  }, 'build-1');

  assert.deepEqual(requests, [{
    path: '/v1/builds/build-1',
    options: {
      method: 'PATCH',
      body: JSON.stringify({
        data: {
          type: 'builds',
          id: 'build-1',
          attributes: { usesNonExemptEncryption: false },
        },
      }),
    },
  }]);
});

test('waits until an uploaded build becomes valid', async () => {
  const states = [null, { attributes: { processingState: 'PROCESSING' } }, {
    id: 'build-1',
    attributes: { processingState: 'VALID' },
  }];
  let sleeps = 0;

  const build = await waitForProcessedBuild(
    async () => states.shift(),
    {
      attemptLimit: 3,
      sleep: async () => { sleeps += 1; },
      logger: { log() {} },
    },
  );

  assert.equal(build.id, 'build-1');
  assert.equal(sleeps, 2);
});

test('stops immediately when Apple marks a build invalid', async () => {
  await assert.rejects(
    () => waitForProcessedBuild(
      async () => ({ attributes: { processingState: 'INVALID' } }),
      { attemptLimit: 3, sleep: async () => {}, logger: { log() {} } },
    ),
    /processing failed \(INVALID\)/,
  );
});

test('leaves an uploaded build ready when another beta review is pending', async () => {
  const pendingReview = new Error('Another build is in review.');
  pendingReview.appStoreErrorCodes = [
    'ENTITY_UNPROCESSABLE.ANOTHER_BUILD_IN_REVIEW',
  ];
  const messages = [];

  const submitted = await submitBetaReview(
    async (path, options) => {
      assert.equal(path, '/v1/betaAppReviewSubmissions');
      assert.equal(options.method, 'POST');
      throw pendingReview;
    },
    { buildId: 'build-1', buildNumber: '20260919073600', logger: { log: (message) => messages.push(message) } },
  );

  assert.equal(submitted, false);
  assert.deepEqual(messages, [
    'Build 20260919073600 is uploaded and assigned; a previous Beta App Review is still pending.',
  ]);
});
