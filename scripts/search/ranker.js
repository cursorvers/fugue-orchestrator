import { CONFIDENCE_SCORE_MAP } from './config.js';

export function assignConfidence(items) {
  return items.map((item) => ({
    ...item,
    confidence: CONFIDENCE_SCORE_MAP[item.confidenceLabel] ?? 0.3,
  }));
}
