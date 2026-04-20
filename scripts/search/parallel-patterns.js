export const PATTERNS = Object.freeze({
  'seo-evidence': {
    triggers: /SEO|記事|コンテンツ/i,
    sources: ['web', 'estat', 'x-search'],
  },
  'market-trend': {
    triggers: /市場|動向|トレンド/i,
    sources: ['web', 'estat', 'x-search'],
  },
  'legal-research': {
    triggers: /法令|法律|通達|判例/i,
    sources: ['labor-law', 'web'],
  },
  'note-research': {
    triggers: /note|原稿|執筆/i,
    sources: ['web', 'estat', 'note-com'],
  },
  'slide-facts': {
    triggers: /スライド|プレゼン|ファクト/i,
    sources: ['estat', 'web'],
  },
});
