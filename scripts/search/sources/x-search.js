import { createSourceError } from './base.js';

const XAI_RESPONSES_ENDPOINT = 'https://api.x.ai/v1/responses';
const DEFAULT_MODEL = 'grok-4-fast';

function resolveApiKey() {
  return process.env.XAI_API_KEY?.trim() ?? '';
}

function resolveModel() {
  return process.env.XAI_SEARCH_MODEL?.trim() || DEFAULT_MODEL;
}

function buildInstruction(query, maxResults) {
  return [
    `Search X (Twitter) for posts relevant to the query: "${query}".`,
    `Return up to ${maxResults} most relevant and recent posts with URLs and short summaries.`,
    'Prefer posts from verified or authoritative accounts when available.',
  ].join(' ');
}

function pushCitation(items, candidate) {
  if (!candidate || typeof candidate.url !== 'string' || !candidate.url) return;
  items.push(candidate);
}

function extractCitations(payload) {
  const items = [];

  if (Array.isArray(payload?.citations)) {
    for (const cit of payload.citations) {
      pushCitation(items, {
        url: cit?.url,
        title: cit?.title,
        snippet: cit?.snippet || cit?.text || '',
        raw: cit,
      });
    }
  }

  const output = Array.isArray(payload?.output) ? payload.output : [];
  for (const entry of output) {
    const content = Array.isArray(entry?.content) ? entry.content : [];
    for (const block of content) {
      const annotations = Array.isArray(block?.annotations) ? block.annotations : [];
      for (const ann of annotations) {
        if (ann?.url) {
          pushCitation(items, {
            url: ann.url,
            title: ann.title || ann.url,
            snippet: ann.snippet || ann.text || '',
            raw: ann,
          });
        }
      }
      const toolResults = Array.isArray(block?.results) ? block.results : [];
      for (const result of toolResults) {
        pushCitation(items, {
          url: result?.url,
          title:
            result?.title ||
            (typeof result?.text === 'string' ? result.text.slice(0, 80) : result?.url),
          snippet: result?.text || result?.snippet || '',
          author: result?.author || result?.username || null,
          postId: result?.id || null,
          createdAt: result?.created_at || null,
          raw: result,
        });
      }
    }
  }

  const seen = new Set();
  return items.filter((item) => {
    if (seen.has(item.url)) return false;
    seen.add(item.url);
    return true;
  });
}

function normalizeItems(payload, maxResults) {
  return extractCitations(payload)
    .slice(0, maxResults)
    .map((entry) => ({
      title: entry.title || entry.url,
      url: entry.url,
      snippet: entry.snippet || '',
      metadata: {
        author: entry.author ?? null,
        postId: entry.postId ?? null,
        createdAt: entry.createdAt ?? null,
      },
      raw: entry.raw,
    }));
}

export function createXSearchSource(fetchImpl = globalThis.fetch) {
  return {
    id: 'x-search',
    async search({ query, maxResults, signal }) {
      const apiKey = resolveApiKey();
      if (!apiKey) {
        return {
          items: [],
          error: createSourceError(
            'x-search',
            'MISSING_API_KEY',
            'XAI_API_KEY is not configured',
          ),
        };
      }

      if (typeof fetchImpl !== 'function') {
        return {
          items: [],
          error: createSourceError('x-search', 'FETCH_UNAVAILABLE', 'fetch is not available'),
        };
      }

      const requestBody = {
        model: resolveModel(),
        input: buildInstruction(query, maxResults),
        tools: [{ type: 'x_search' }],
      };

      const response = await fetchImpl(XAI_RESPONSES_ENDPOINT, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify(requestBody),
        signal,
      });

      if (!response.ok) {
        const detail = await response.text().catch(() => '');
        const trimmed = detail ? `: ${detail.slice(0, 200)}` : '';
        return {
          items: [],
          error: createSourceError(
            'x-search',
            'HTTP_ERROR',
            `xAI request failed with status ${response.status}${trimmed}`,
          ),
        };
      }

      const payload = await response.json();
      return { items: normalizeItems(payload, maxResults) };
    },
  };
}
