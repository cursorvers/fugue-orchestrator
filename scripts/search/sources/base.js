/**
 * @typedef {Object} SearchContext
 * @property {string} query
 * @property {number} maxResults
 * @property {AbortSignal} signal
 *
 * @typedef {Object} SearchItem
 * @property {string} title
 * @property {string} url
 * @property {string} snippet
 * @property {Record<string, unknown>} [metadata]
 * @property {unknown} [raw]
 *
 * @typedef {Object} SourceError
 * @property {string} sourceId
 * @property {string} code
 * @property {string} message
 *
 * @typedef {Object} SourceResult
 * @property {SearchItem[]} items
 * @property {SourceError | null} [error]
 *
 * @typedef {Object} SearchSource
 * @property {string} id
 * @property {(context: SearchContext) => Promise<SourceResult>} search
 */

/**
 * @param {string} sourceId
 * @param {string} code
 * @param {string} message
 * @returns {SourceError}
 */
export function createSourceError(sourceId, code, message) {
  return {
    sourceId,
    code,
    message,
  };
}
