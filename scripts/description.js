'use strict';

const { stripHTML } = require('hexo-util');

const MAX_LENGTH = 150;
const MIN_SENTENCE_LENGTH = 40;
const rBlockEnd = /<(br|\/p|\/h[1-6]|\/li|\/div|\/blockquote)[^>]*>/gi;

function summarize(html) {
  const text = stripHTML(html.replace(rBlockEnd, ' ')).replace(/\s+/g, ' ').trim();
  if (text.length <= MAX_LENGTH) return text;

  const head = text.substring(0, MAX_LENGTH + 1);
  let cut = -1;
  const rSentenceEnd = /[.!?…](?=\s)/g;
  let match;
  while ((match = rSentenceEnd.exec(head)) !== null) cut = match.index + 1;
  if (cut >= MIN_SENTENCE_LENGTH) return text.substring(0, cut);

  const space = head.lastIndexOf(' ');
  return text.substring(0, space > 0 ? space : MAX_LENGTH) + '…';
}

// Hexo's open_graph cuts a missing description at 200 chars mid-word. Wrap the helper instead of setting
// page.description, because NexT renders page.description under the title and on the index.
const openGraph = hexo.extend.helper.get('open_graph');

hexo.extend.helper.register('open_graph', function(options = {}) {
  const { page } = this;
  if (options.description || page.description) return openGraph.call(this, options);
  const summary = page.summary || summarize(page.excerpt || '') || summarize(page.content || '');
  return openGraph.call(this, summary ? { ...options, description: summary } : options);
});
