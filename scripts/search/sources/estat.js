import { createSourceError } from './base.js';

const ESTAT_ENDPOINT = 'https://api.e-stat.go.jp/rest/3.0/app/json/getStatsList';

function resolveAppId() {
  const configured = process.env.ESTAT_APP_ID?.trim();
  if (configured) {
    return configured;
  }
  return '';
}

function normalizeTextField(field) {
  if (typeof field === 'string') {
    return field;
  }
  if (field && typeof field === 'object' && '$' in field && typeof field.$ === 'string') {
    return field.$;
  }
  return '';
}

function normalizeYear(entry) {
  const candidates = [
    entry?.SURVEY_DATE,
    entry?.OPEN_DATE,
    entry?.TIME,
    entry?.TITLE,
  ];
  for (const candidate of candidates) {
    const value = normalizeTextField(candidate);
    const matched = value.match(/\b(19|20)\d{2}\b/u);
    if (matched) {
      return matched[0];
    }
  }
  return '';
}

function normalizeItems(payload, maxResults) {
  const rawList = payload?.GET_STATS_LIST?.DATALIST_INF?.TABLE_INF ?? [];
  const tables = Array.isArray(rawList) ? rawList : [rawList].filter(Boolean);
  return tables.slice(0, maxResults).map((entry) => {
    const statName = normalizeTextField(entry?.STAT_NAME);
    const title = normalizeTextField(entry?.TITLE);
    const url = normalizeTextField(entry?.LINK);
    const surveyYear = normalizeYear(entry);
    return {
      title: statName || title || 'Untitled statistic',
      url,
      snippet: title,
      metadata: {
        id: entry?.['@id'] ?? null,
        statisticName: statName || null,
        tableTitle: title || null,
        surveyYear: surveyYear || null,
        government: normalizeTextField(entry?.GOV_ORG) || null,
      },
      raw: entry,
    };
  });
}

export function createEstatSource(fetchImpl = globalThis.fetch) {
  return {
    id: 'estat',
    async search({ query, maxResults, signal }) {
      const appId = resolveAppId();
      if (!appId) {
        return {
          items: [],
          error: createSourceError(
            'estat',
            'MISSING_APP_ID',
            'ESTAT_APP_ID is not configured',
          ),
        };
      }

      if (typeof fetchImpl !== 'function') {
        return {
          items: [],
          error: createSourceError('estat', 'FETCH_UNAVAILABLE', 'fetch is not available'),
        };
      }

      const url = new URL(ESTAT_ENDPOINT);
      url.searchParams.set('appId', appId);
      url.searchParams.set('searchWord', query);
      url.searchParams.set('limit', String(maxResults));

      const response = await fetchImpl(url, { signal });
      if (!response.ok) {
        return {
          items: [],
          error: createSourceError(
            'estat',
            'HTTP_ERROR',
            `e-Stat request failed with status ${response.status}`,
          ),
        };
      }

      const payload = await response.json();
      const status = normalizeTextField(payload?.GET_STATS_LIST?.RESULT?.STATUS);
      if (status && status !== '0') {
        const errorMessage =
          normalizeTextField(payload?.GET_STATS_LIST?.RESULT?.ERROR_MSG) ||
          'e-Stat returned an API error';
        return {
          items: [],
          error: createSourceError('estat', 'API_ERROR', errorMessage),
        };
      }

      return {
        items: normalizeItems(payload, maxResults),
      };
    },
  };
}
