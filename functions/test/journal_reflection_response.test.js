"use strict";
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { journalReflectionResponseFormat, normalizeReflection } = require('../journal_reflection_response');

// Execute the actual callable with an OpenAI transport stub. This catches the
// regression even if the right schema exists but the endpoint uses the wrong one.
test('journal callable requests and returns reflection fields rather than chat fields', async () => {
  const source = fs.readFileSync(require.resolve('../index'), 'utf8');
  const code = source.slice(source.indexOf('exports.generateAiJournalReflection ='),
    source.indexOf('\nfunction extractExplicitSleepTimes'));
  const payload = {
    summary: '今天完成了工作，也和朋友聊天。', emotionObservation: '你記下了今天的感受。',
    topics: ['工作', '朋友', '聊天'], positiveFeedback: '你願意留下今天的紀錄。',
    gratitudeQuestions: ['今天誰陪伴了你？', '有什麼值得珍惜？', '哪一刻讓你安心？'],
    tomorrowAction: '明天留一點時間休息。', crisisDetected: false,
  };
  let succeeded = false;
  const context = {
    exports: {}, onCall: (_, handler) => handler,
    HttpsError: class extends Error {}, openAiApiKey: { value: () => 'test' },
    revenueCatSecretApiKey: {}, requireAiProAccess: async () => {},
    requireAiCapacity: async () => {}, detectCrisis: () => false,
    normalizeDiaryFields: (data) => data, toNumber: (value, fallback) => value ?? fallback,
    buildEmotionModel: () => ({ emotionEntries: [] }),
    createAiUsageTracker: () => ({ start: async () => {}, succeed: async () => { succeeded = true; }, fail: async () => {} }),
    db: {}, admin: {}, AI_QUOTED_POINTS: { journal_reflection: 1 }, DEFAULT_AI_MODEL: 'test-model',
    journalReflectionResponseFormat, normalizeReflection, stripMarkdownFence: (text) => text,
    OpenAI: class { chat = { completions: { create: async (request) => {
      assert.equal(request.response_format, journalReflectionResponseFormat);
      assert.deepEqual(Object.keys(payload).sort(), request.response_format.json_schema.schema.required.slice().sort());
      assert.equal(request.response_format.json_schema.schema.properties.reply, undefined);
      return { choices: [{ message: { content: JSON.stringify(payload) } }] };
    } } }; },
    console,
  };
  vm.runInNewContext(code, context);
  const result = await context.exports.generateAiJournalReflection({
    auth: { uid: 'test-user' }, data: { aiInput: { diaryText: '今天完成工作，和朋友聊天。' } },
  });
  assert.equal(result.summary, payload.summary);
  assert.equal(result.positiveFeedback, payload.positiveFeedback);
  assert.equal(result.isMock, false);
  assert.equal(succeeded, true);
});

test('reflection normalization retains locally detected crisis', () => {
  assert.equal(normalizeReflection({ crisisDetected: false }, true, 'model').crisisDetected, true);
});
