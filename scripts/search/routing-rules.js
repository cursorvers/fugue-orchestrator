export const ROUTING_RULES = Object.freeze([
  {
    pattern: /統計|人口|経済|GDP|産業|雇用率|出生率/i,
    sourceId: 'estat',
    confidence: 'primary',
  },
  {
    pattern: /法令|通達|社会保険|労働基準|安全衛生/i,
    sourceId: 'labor-law',
    confidence: 'primary',
  },
  {
    pattern: /note記事|note\.com|原稿/i,
    sourceId: 'note-com',
    confidence: 'secondary-mid',
  },
  {
    pattern: /SNS|X|ツイート|twitter|バズ/i,
    sourceId: 'x-search',
    confidence: 'secondary-low',
  },
]);

export const ROUTING_FALLBACK = Object.freeze({
  sourceId: 'web',
  confidence: 'secondary-high',
});
