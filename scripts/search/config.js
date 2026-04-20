export const DEFAULT_FORMAT = 'summary';
export const DEFAULT_MAX_RESULTS = 5;
export const DEFAULT_PARALLEL = true;
export const DEFAULT_TIMEOUT_MS = 10000;

export const SOURCE_TIMEOUT_MS = {
  estat: 20000,
  'labor-law': 3000,
  'note-com': 3000,
  web: 3000,
  'x-search': 15000,
};

export const KNOWN_SOURCES = Object.freeze([
  'estat',
  'labor-law',
  'note-com',
  'web',
  'x-search',
]);

export const CONFIDENCE_SCORE_MAP = Object.freeze({
  primary: 0.9,
  'secondary-high': 0.7,
  'secondary-mid': 0.5,
  'secondary-low': 0.3,
});
