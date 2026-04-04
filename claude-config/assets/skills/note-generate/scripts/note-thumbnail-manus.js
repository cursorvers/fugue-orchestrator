/**
 * note-thumbnail-manus.js — Note wrapper for shared Manus policy
 *
 * note keeps a more eager Manus-selection profile for compatibility, while
 * delegating runtime and prompt-policy implementation to thumbnail authority.
 */

import {
  MANUS_MIN_SIZE,
  loadManusClient,
  generateImageManus,
  sanitizePromptForSafety,
  shouldUseManusPolicy,
  enhancePromptForManusPolicy,
} from '../../thumbnail-gen/scripts/thumbnail-manus-shared.js';

export { MANUS_MIN_SIZE, loadManusClient, generateImageManus, sanitizePromptForSafety };

export function shouldUseManus(promptText, styleId, library) {
  return shouldUseManusPolicy(promptText, styleId, library, {
    requireAutoFlagForFallback: false,
    enablePersonStylesFallback: true,
  });
}

export function enhancePromptForManus(rawPrompt, styleId, library, pillar, promptContext = null) {
  return enhancePromptForManusPolicy(rawPrompt, styleId, library, pillar, promptContext, {
    includeAdvancedMetadata: false,
    includeTitleRules: false,
    enableTextOnlyGuidance: false,
    includeCompositionRules: false,
    includeStyleProhibitions: false,
  });
}
