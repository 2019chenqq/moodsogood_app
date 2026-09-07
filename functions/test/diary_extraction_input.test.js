const test = require('node:test');
const assert = require('node:assert/strict');
const { prepareDiaryMessages } = require('../diary_extraction_input');

test('preserves early ordinary events and long user messages', () => {
  const messages = [
    { role: 'user', content: '早上和朋友去市場買菜，回家一起做飯。' },
    ...Array.from({length: 30}, (_, i) => ({role: i % 2 ? 'assistant' : 'user', content: `對話${i}`})),
    { role: 'user', content: '完整事件經過'.repeat(500) + '最後我們和好了。' },
  ];
  assert.deepEqual(prepareDiaryMessages(messages), messages);
});

test('filters non-conversation roles without dropping valid events', () => {
  assert.deepEqual(prepareDiaryMessages([
    {role: 'system', content: 'not a diary source'},
    {role: 'user', content: '  去圖書館借了兩本書  '},
    {role: 'assistant', content: ''},
  ]), [{role: 'user', content: '去圖書館借了兩本書'}]);
});

test('oversized input fails explicitly rather than returning a partial diary', () => {
  assert.throws(() => prepareDiaryMessages([{role: 'user', content: '文'.repeat(120001)}]), RangeError);
});
