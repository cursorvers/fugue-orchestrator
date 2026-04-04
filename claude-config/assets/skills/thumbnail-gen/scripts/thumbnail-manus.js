/**
 * thumbnail-manus.js — Thumbnail authority wrapper for Manus policy
 */

import {
  MANUS_MIN_SIZE,
  loadManusClient,
  generateImageManus,
  sanitizePromptForSafety,
  shouldUseManusPolicy,
  enhancePromptForManusPolicy,
} from './thumbnail-manus-shared.js';

export { MANUS_MIN_SIZE, loadManusClient, generateImageManus, sanitizePromptForSafety };

export function shouldUseManus(promptText, styleId, library) {
  return shouldUseManusPolicy(promptText, styleId, library, {
    requireAutoFlagForFallback: true,
    enablePersonStylesFallback: false,
  });
}

export function enhancePromptForManus(rawPrompt, styleId, library, pillar, promptContext = null) {
  return enhancePromptForManusPolicy(rawPrompt, styleId, library, pillar, promptContext, {
    includeAdvancedMetadata: true,
    includeTitleRules: true,
    enableTextOnlyGuidance: true,
    includeCompositionRules: true,
    includeStyleProhibitions: true,
  });
}
