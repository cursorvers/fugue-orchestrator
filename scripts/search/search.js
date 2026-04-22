#!/usr/bin/env node

/**
 * search.js
 *
 * Local planner/aggregator for the unified search command.
 * This replaces the stale external dependency on agent-orchestration.
 *
 * Supported modes:
 *   - plan-only: build a source execution plan from a natural-language query
 *   - run-local: render a local execution brief without requiring host auth
 *   - aggregate: summarize per-source execution results into markdown/json
 */

const fs = require("node:fs");

const args = process.argv.slice(2);
const FIXTURE_FILE = process.env.SEARCH_LOCAL_FIXTURE_FILE;
const DEFAULT_TIMEOUT_MS = 15_000;
const DEFAULT_HEADERS = {
  "user-agent": "fugue-search-skill/1.0 (+local-executor)",
  accept: "text/html,application/json;q=0.9,*/*;q=0.8",
};

const SOURCE_CATALOG = {
  "e-stat": {
    trust: "primary",
    label: "e-Stat",
    kind: "government-statistics",
    executionMode: "direct",
  },
  "mhlw-bed-function-report": {
    trust: "primary",
    label: "厚労省 病床機能報告",
    kind: "government-open-data",
    executionMode: "claude-session",
  },
  "mhlw-hospital-report": {
    trust: "primary",
    label: "厚労省 病院報告",
    kind: "government-statistics",
    executionMode: "claude-session",
  },
  "medical-info-net": {
    trust: "primary",
    label: "医療情報ネット",
    kind: "government-service",
    executionMode: "claude-session",
  },
  dashboard: {
    trust: "secondary-high",
    label: "bed-function-dashboard",
    kind: "derived-dashboard",
    executionMode: "claude-session",
  },
  web: {
    trust: "secondary-high",
    label: "WebSearch",
    kind: "web-search",
    executionMode: "claude-session",
  },
  "x-search": {
    trust: "secondary-mid",
    label: "xAI Search",
    kind: "ai-search",
    executionMode: "claude-session",
  },
  "manus-wide-research": {
    trust: "secondary-mid",
    label: "Manus Wide Research",
    kind: "delegated-research",
    executionMode: "claude-session",
  },
};

const TRUST_RANK = {
  primary: 0,
  "secondary-high": 1,
  "secondary-mid": 2,
  "secondary-low": 3,
};

const FIXED_SOURCE_URLS = {
  "mhlw-bed-function-report": "https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000055891.html",
  "mhlw-hospital-report": "https://www.mhlw.go.jp/toukei/list/80-1.html",
  "medical-info-net": "https://www.iryou.teikyouseido.mhlw.go.jp/",
  dashboard: "https://bed-function-dashboard.vercel.app/",
};

function parseCli(argv) {
  if (argv.includes("--execute-local")) {
    const queryParts = argv.filter((part, idx) => {
      if (part.startsWith("--")) return false;
      if (idx > 0 && argv[idx - 1].startsWith("--")) return false;
      return true;
    });
    return {
      mode: "execute-local",
      query: queryParts.join(" ").trim(),
      format: getFlagValue(argv, "--format") || "markdown",
    };
  }

  if (argv.includes("--run-local")) {
    const queryParts = argv.filter((part, idx) => {
      if (part.startsWith("--")) return false;
      if (idx > 0 && argv[idx - 1].startsWith("--")) return false;
      return true;
    });
    return {
      mode: "run-local",
      query: queryParts.join(" ").trim(),
    };
  }

  const aggregateIdx = argv.indexOf("--aggregate");
  if (aggregateIdx !== -1) {
    return {
      mode: "aggregate",
      inputPath: argv[aggregateIdx + 1],
      format: getFlagValue(argv, "--format") || "markdown",
    };
  }

  const planOnly = argv.includes("--plan-only");
  const queryParts = argv.filter((part, idx) => {
    if (part.startsWith("--")) return false;
    if (idx > 0 && argv[idx - 1].startsWith("--")) return false;
    return true;
  });

  return {
    mode: planOnly ? "plan-only" : "plan-only",
    query: queryParts.join(" ").trim(),
  };
}

function getFlagValue(argv, flag) {
  const idx = argv.indexOf(flag);
  return idx === -1 ? undefined : argv[idx + 1];
}

function normalizeText(input) {
  return String(input || "").trim().toLowerCase();
}

function hasAny(text, patterns) {
  return patterns.some((pattern) => pattern.test(text));
}

function buildPlan(query) {
  if (!query) {
    throw new Error("query is required for --plan-only");
  }

  const text = normalizeText(query);
  const sources = [];
  const reasoning = [];

  const needsMedical = hasAny(text, [
    /病床機能報告/,
    /病院報告/,
    /医療情報ネット/,
    /地域医療構想/,
    /病床/,
    /病院/,
    /医療/,
    /dpc/,
    /mcdb/,
    /高齢化率/,
  ]);
  const needsStats = hasAny(text, [/e-stat/, /政府統計/, /統計/, /国勢調査/, /人口/]);
  const needsOverview = hasAny(text, [
    /俯瞰/,
    /比較/,
    /ランキング/,
    /トレンド/,
    /可視化/,
    /マップ/,
    /ダッシュボード/,
    /ざっくり/,
    /概観/,
  ]);

  if (needsMedical) {
    addSource(sources, reasoning, "mhlw-bed-function-report", "病床・医療系の一次情報を優先");
    addSource(sources, reasoning, "mhlw-hospital-report", "病院報告で病床利用率・平均在院日数を補完");
    addSource(sources, reasoning, "medical-info-net", "施設単位の補完情報を確認");
  }

  if (needsStats || (needsMedical && hasAny(text, [/人口/, /高齢化/, /地域/])) ) {
    addSource(sources, reasoning, "e-stat", "人口・国勢調査・政府統計は e-Stat を優先");
  }

  if (needsOverview && needsMedical) {
    addSource(
      sources,
      reasoning,
      "dashboard",
      "俯瞰・比較・候補探索では二次ダッシュボードを補助利用",
    );
  }

  addSource(sources, reasoning, "web", "不足ソースの発見と一般公開情報の補完");
  addSource(sources, reasoning, "x-search", "xAI API 検索を既定の補助ソースとして常時併走");
  addSource(
    sources,
    reasoning,
    "manus-wide-research",
    "Manus wide research を既定の深掘りソースとして常時併走",
  );

  const canonicalSourceIds = sources
    .filter((source) => source.trust === "primary")
    .map((source) => source.sourceId);
  const referenceSourceIds = sources
    .filter((source) => source.trust !== "primary")
    .map((source) => source.sourceId);

  return {
    query,
    generatedAt: new Date().toISOString(),
    policyVersion: "2026-04-23-search-defaults-v2",
    canonicalSourceIds,
    referenceSourceIds,
    notes: [
      "Return answers from canonical sources when factual grounding matters.",
      "Use dashboard results for overview and candidate discovery only.",
      "Do not cite SNS or derived dashboards as sole evidence for critical facts.",
      "Treat xAI and Manus outputs as reference sources that must be corroborated by canonical evidence.",
    ],
    reasoning,
    sources,
  };
}

function addSource(sources, reasoning, sourceId, reason) {
  if (sources.some((source) => source.sourceId === sourceId)) {
    return;
  }
  const def = SOURCE_CATALOG[sourceId];
  sources.push({
    sourceId,
    label: def.label,
    trust: def.trust,
    kind: def.kind,
    executionMode: def.executionMode,
    canonical: def.trust === "primary",
  });
  reasoning.push({ sourceId, reason });
}

function stripHtml(input) {
  return String(input || "")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, " ")
    .trim();
}

function takeSnippet(input, maxLength = 220) {
  const text = String(input || "").replace(/\s+/g, " ").trim();
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 1).trim()}…`;
}

function extractMetaContent(html, name) {
  const pattern = new RegExp(
    `<meta[^>]+(?:name|property)=["']${name}["'][^>]+content=["']([^"']+)["'][^>]*>`,
    "i",
  );
  return html.match(pattern)?.[1]?.trim() || "";
}

function extractTitle(html) {
  const title = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1];
  return stripHtml(title || "");
}

function buildHtmlItem(url, html, fallbackTitle) {
  const title = extractTitle(html) || fallbackTitle || url;
  const metaDescription = extractMetaContent(html, "description")
    || extractMetaContent(html, "og:description");
  const bodySnippet = stripHtml(html);
  return {
    title,
    url,
    snippet: takeSnippet(metaDescription || bodySnippet),
    metadata: {},
  };
}

function buildResult(sourceId, fields) {
  return {
    sourceId,
    trust: SOURCE_CATALOG[sourceId]?.trust || "secondary-mid",
    status: fields.status,
    items: Array.isArray(fields.items) ? fields.items : [],
    durationMs: fields.durationMs,
    error: fields.error,
    metadata: fields.metadata || {},
  };
}

async function fetchText(url, opts = {}) {
  const controller = new AbortController();
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: { ...DEFAULT_HEADERS, ...(opts.headers || {}) },
      signal: controller.signal,
      redirect: "follow",
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status} for ${url}`);
    }
    const arrayBuffer = await response.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);
    const contentType = response.headers.get("content-type") || "";
    const headerCharset = contentType.match(/charset=([^\s;]+)/i)?.[1] || "";
    const sniffedHead = buffer.subarray(0, 2048).toString("latin1");
    const metaCharset = sniffedHead.match(/charset=["']?\s*([a-zA-Z0-9_-]+)/i)?.[1] || "";
    const charset = (headerCharset || metaCharset || "utf-8").toLowerCase().replace(/_/g, "-");
    return new TextDecoder(charset).decode(buffer);
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchJson(url, opts = {}) {
  const controller = new AbortController();
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: {
        ...DEFAULT_HEADERS,
        accept: "application/json,text/plain;q=0.9,*/*;q=0.8",
        ...(opts.headers || {}),
      },
      signal: controller.signal,
      redirect: "follow",
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status} for ${url}`);
    }
    return response.json();
  } finally {
    clearTimeout(timeout);
  }
}

function decodeDuckDuckGoHref(href) {
  try {
    const parsed = new URL(href, "https://duckduckgo.com");
    const redirected = parsed.searchParams.get("uddg");
    return redirected ? decodeURIComponent(redirected) : parsed.toString();
  } catch {
    return href;
  }
}

function parseDuckDuckGoResults(html) {
  const items = [];
  const anchorRegex = /<a[^>]+class="[^"]*result__a[^"]*"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = anchorRegex.exec(html)) && items.length < 5) {
    const href = decodeDuckDuckGoHref(match[1]);
    const title = stripHtml(match[2]);
    if (!href || !title) continue;
    items.push({
      title,
      url: href,
      snippet: "",
      metadata: {},
    });
  }
  return items;
}

async function executeFixedHtmlSource(sourceId) {
  const startedAt = Date.now();
  const url = FIXED_SOURCE_URLS[sourceId];
  try {
    const html = await fetchText(url);
    return buildResult(sourceId, {
      status: "ok",
      items: [buildHtmlItem(url, html, SOURCE_CATALOG[sourceId]?.label)],
      durationMs: Date.now() - startedAt,
    });
  } catch (error) {
    return buildResult(sourceId, {
      status: "error",
      items: [],
      durationMs: Date.now() - startedAt,
      error: { code: "fetch_failed", message: error.message },
    });
  }
}

function getEstatApiId() {
  return process.env.ESTAT_API_ID || process.env.ESTAT_APP_ID || "";
}

async function executeEstatSource(query) {
  const startedAt = Date.now();
  const appId = getEstatApiId();
  if (!appId) {
    try {
      const url = `https://www.e-stat.go.jp/stat-search?query=${encodeURIComponent(query)}`;
      const html = await fetchText(url);
      return buildResult("e-stat", {
        status: "ok",
        items: [buildHtmlItem(url, html, "e-Stat 検索結果")],
        durationMs: Date.now() - startedAt,
        metadata: { method: "web-fallback" },
      });
    } catch (error) {
      return buildResult("e-stat", {
        status: "error",
        items: [],
        durationMs: Date.now() - startedAt,
        error: { code: "missing_env", message: `ESTAT_API_ID is not set and web fallback failed: ${error.message}` },
      });
    }
  }

  const encodedTask = encodeURIComponent(query);
  const url = `https://api.e-stat.go.jp/rest/3.0/app/json/getStatsList?appId=${encodeURIComponent(appId)}&searchWord=${encodedTask}&lang=J&limit=5`;
  try {
    const payload = await fetchJson(url);
    const list = payload?.GET_STATS_LIST?.DATALIST_INF?.TABLE_INF;
    const tables = Array.isArray(list) ? list : list ? [list] : [];
    const items = tables.slice(0, 5).map((table) => ({
      title: table.STAT_NAME?.$ || table.TITLE?.$ || table.TABLE_NAME?.$ || "e-Stat result",
      url: table["@id"]
        ? `https://www.e-stat.go.jp/dbview?sid=${table["@id"]}`
        : "https://www.e-stat.go.jp/",
      snippet: takeSnippet([
        table.GOV_ORG?.$,
        table.SURVEY_DATE?.$,
        table.TITLE?.$,
      ].filter(Boolean).join(" / ")),
      metadata: {
        statId: table["@id"] || null,
      },
    }));
    return buildResult("e-stat", {
      status: "ok",
      items,
      durationMs: Date.now() - startedAt,
    });
  } catch (error) {
    return buildResult("e-stat", {
      status: "error",
      items: [],
      durationMs: Date.now() - startedAt,
      error: { code: "fetch_failed", message: error.message },
    });
  }
}

async function executeSearchEngineSource(sourceId, query) {
  const startedAt = Date.now();
  const searchUrl = `https://duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
  try {
    const html = await fetchText(searchUrl, {
      headers: {
        referer: "https://duckduckgo.com/",
      },
    });
    const items = parseDuckDuckGoResults(html);
    return buildResult(sourceId, {
      status: "ok",
      items,
      durationMs: Date.now() - startedAt,
      metadata: { query },
    });
  } catch (error) {
    return buildResult(sourceId, {
      status: "error",
      items: [],
      durationMs: Date.now() - startedAt,
      error: { code: "search_failed", message: error.message },
      metadata: { query },
    });
  }
}

async function executeSource(source, query) {
  switch (source.sourceId) {
    case "e-stat":
      return executeEstatSource(query);
    case "mhlw-bed-function-report":
    case "mhlw-hospital-report":
    case "medical-info-net":
    case "dashboard":
      return executeFixedHtmlSource(source.sourceId);
    case "web":
      return executeSearchEngineSource("web", query);
    case "x-search":
    case "manus-wide-research":
      return buildResult(source.sourceId, {
        status: "pending",
        items: [
          {
            title: "Host execution required",
            url: "",
            snippet: `Run the delegated source for "${query}" from the host session.`,
            metadata: { executionMode: "claude-session" },
          },
        ],
        durationMs: 0,
        metadata: { executionMode: "claude-session" },
      });
    default:
      return buildResult(source.sourceId, {
        status: "error",
        items: [],
        durationMs: 0,
        error: { code: "unsupported_source", message: `Unsupported source: ${source.sourceId}` },
      });
  }
}

function loadFixtureResults() {
  if (!FIXTURE_FILE) return null;
  return JSON.parse(fs.readFileSync(FIXTURE_FILE, "utf-8"));
}

function materializeFixtureResults(plan, fixturePayload) {
  const fixtureMap = new Map(
    (fixturePayload?.sources || []).map((source) => [source.sourceId, source]),
  );
  return plan.sources.map((source) => {
    const fixture = fixtureMap.get(source.sourceId);
    if (fixture) {
      return buildResult(source.sourceId, {
        status: fixture.status || "ok",
        items: fixture.items || [],
        durationMs: fixture.durationMs ?? 0,
        error: fixture.error,
        metadata: fixture.metadata || {},
      });
    }
    return buildResult(source.sourceId, {
      status: "error",
      items: [],
      durationMs: 0,
      error: { code: "missing_fixture", message: `No fixture for ${source.sourceId}` },
    });
  });
}

async function executeLocalSearch(query) {
  const plan = buildPlan(query);
  const fixturePayload = loadFixtureResults();
  const sources = fixturePayload
    ? materializeFixtureResults(plan, fixturePayload)
    : await Promise.all(plan.sources.map((source) => executeSource(source, query)));

  const aggregatedMarkdown = aggregatePayload({
    generatedAt: new Date().toISOString(),
    sources,
  }, "markdown");

  const executedSources = sources
    .filter((source) => source.status === "ok")
    .map((source) => source.sourceId);
  const failedSources = sources
    .filter((source) => source.status !== "ok")
    .map((source) => source.sourceId);
  const environmentGaps = [];
  if (plan.canonicalSourceIds.includes("e-stat") && !getEstatApiId()) {
    environmentGaps.push("ESTAT_API_ID is not set, so e-Stat used the website fallback instead of the API.");
  }
  if (plan.referenceSourceIds.includes("x-search") && !process.env.XAI_API_KEY) {
    environmentGaps.push("XAI_API_KEY is not set, so xAI Search still needs host-side credentials.");
  }
  if (
    plan.referenceSourceIds.includes("manus-wide-research")
    && !process.env.MANUS_API_KEY
    && !process.env.MANUS_MCP_API_KEY
  ) {
    environmentGaps.push("MANUS_API_KEY is not set, so Manus Wide Research still needs host-side credentials.");
  }

  return {
    mode: "execute-local",
    plan,
    execution: {
      sources,
      executedSources,
      failedSources,
      environmentGaps,
    },
    output: [
      "# Search Execution Report",
      "",
      `- Query: ${plan.query}`,
      `- Policy: ${plan.policyVersion}`,
      `- Executed sources: ${executedSources.length}`,
      `- Failed sources: ${failedSources.length}`,
      "",
      aggregatedMarkdown,
    ].join("\n"),
  };
}

function aggregateResults(inputPath, format) {
  if (!inputPath) {
    throw new Error("--aggregate requires an input path");
  }
  const payload = JSON.parse(fs.readFileSync(inputPath, "utf-8"));
  return aggregatePayload(payload, format);
}

function aggregatePayload(payload, format) {
  const sources = Array.isArray(payload.sources) ? payload.sources.slice() : [];
  sources.sort(compareAggregatedSource);

  if (format === "json") {
    return JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        sources,
      },
      null,
      2,
    );
  }

  const lines = [];
  lines.push("# Search Results");
  lines.push("");

  for (const source of sources) {
    const trust = source.trust || SOURCE_CATALOG[source.sourceId]?.trust || "secondary-mid";
    const label = SOURCE_CATALOG[source.sourceId]?.label || source.sourceId;
    lines.push(`## ${label}`);
    lines.push(`- 信頼度: ${trust}`);
    lines.push(`- ステータス: ${source.status || "unknown"}`);
    if (typeof source.durationMs === "number") {
      lines.push(`- 実行時間: ${source.durationMs}ms`);
    }
    if (source.error) {
      lines.push(`- エラー: ${source.error.message || source.error.code || "unknown error"}`);
    }

    const items = Array.isArray(source.items) ? source.items : [];
    if (items.length === 0) {
      lines.push("- 結果なし");
      lines.push("");
      continue;
    }

    for (const item of items.slice(0, 5)) {
      lines.push(`- ${item.title || "(untitled)"}`);
      if (item.url) {
        lines.push(`  URL: ${item.url}`);
      }
      if (item.snippet) {
        lines.push(`  Snippet: ${item.snippet}`);
      }
    }
    lines.push("");
  }

  return lines.join("\n");
}

function renderLocalExecution(query) {
  const plan = buildPlan(query);
  const lines = [];
  lines.push("# Search Planning Brief");
  lines.push("");
  lines.push(`- Query: ${plan.query}`);
  lines.push(`- Policy: ${plan.policyVersion}`);
  lines.push(`- Planned sources: ${plan.sources.length}`);
  lines.push("- Local mode validates the source plan; it does not fetch remote sources.");
  lines.push("");
  lines.push("## Canonical Sources");
  for (const source of plan.sources.filter((item) => item.canonical)) {
    lines.push(`- ${source.label} (${source.sourceId}, ${source.executionMode})`);
  }
  lines.push("");
  lines.push("## Reference Sources");
  for (const source of plan.sources.filter((item) => !item.canonical)) {
    lines.push(`- ${source.label} (${source.sourceId}, ${source.executionMode})`);
  }
  lines.push("");
  lines.push("## Reasoning");
  for (const entry of plan.reasoning) {
    lines.push(`- ${entry.sourceId}: ${entry.reason}`);
  }

  const envGaps = [];
  if (plan.canonicalSourceIds.includes("e-stat") && !getEstatApiId()) {
    envGaps.push("ESTAT_API_ID is not set, so direct e-Stat execution is unavailable.");
  }
  if (plan.referenceSourceIds.includes("x-search") && !process.env.XAI_API_KEY) {
    envGaps.push("XAI_API_KEY is not set, so xAI Search cannot run in the host session.");
  }
  if (
    plan.referenceSourceIds.includes("manus-wide-research")
    && !process.env.MANUS_API_KEY
    && !process.env.MANUS_MCP_API_KEY
  ) {
    envGaps.push("MANUS_API_KEY is not set, so Manus Wide Research cannot run in the host session.");
  }

  if (envGaps.length > 0) {
    lines.push("");
    lines.push("## Environment Gaps");
    for (const gap of envGaps) {
      lines.push(`- ${gap}`);
    }
  }

  lines.push("");
  lines.push("## Execution Status");
  lines.push("- Executed sources: 0");
  lines.push(`- Planned sources pending host execution: ${plan.sources.length}`);
  lines.push("");
  lines.push("## Execution Notes");
  lines.push("- Use canonical sources first for factual grounding.");
  lines.push("- WebSearch, xAI Search, and Manus Wide Research are default reference sources.");
  lines.push("- Use dashboard and other reference sources for overview and candidate discovery.");
  lines.push("- Do not use reference sources as sole evidence for critical facts.");

  return lines.join("\n");
}

function compareAggregatedSource(a, b) {
  const trustA = a.trust || SOURCE_CATALOG[a.sourceId]?.trust || "secondary-mid";
  const trustB = b.trust || SOURCE_CATALOG[b.sourceId]?.trust || "secondary-mid";
  const rankDelta = TRUST_RANK[trustA] - TRUST_RANK[trustB];
  if (rankDelta !== 0) return rankDelta;
  return String(a.sourceId).localeCompare(String(b.sourceId));
}

function main() {
  const parsed = parseCli(args);

  if (parsed.mode === "execute-local") {
    return executeLocalSearch(parsed.query).then((result) => {
      if (parsed.format === "json") {
        process.stdout.write(JSON.stringify(result, null, 2));
        return;
      }
      process.stdout.write(result.output);
    });
  }

  if (parsed.mode === "aggregate") {
    process.stdout.write(aggregateResults(parsed.inputPath, parsed.format));
    return;
  }

  if (parsed.mode === "run-local") {
    process.stdout.write(renderLocalExecution(parsed.query));
    return;
  }

  process.stdout.write(JSON.stringify(buildPlan(parsed.query), null, 2));
}

try {
  Promise.resolve(main()).catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
} catch (error) {
  console.error(error.message);
  process.exit(1);
}

module.exports = {
  buildPlan,
  executeLocalSearch,
  aggregatePayload,
  parseDuckDuckGoResults,
};
