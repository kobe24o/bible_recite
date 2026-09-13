import assert from 'node:assert/strict';
import test from 'node:test';

import { waitForProcessedBuild } from './assign-testflight-group.mjs';

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
