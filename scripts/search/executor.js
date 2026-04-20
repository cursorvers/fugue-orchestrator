import { DEFAULT_TIMEOUT_MS, SOURCE_TIMEOUT_MS } from './config.js';

function createTimeoutError(sourceId, timeoutMs) {
  return {
    status: 'timeout',
    source: sourceId,
    sourceId,
    code: 'TIMEOUT',
    message: `Source timed out after ${timeoutMs}ms`,
  };
}

function toSourceError(sourceId, error) {
  if (error && typeof error === 'object' && 'code' in error && 'message' in error) {
    return {
      ...(error.status ? { status: String(error.status) } : {}),
      ...(error.source ? { source: String(error.source) } : {}),
      sourceId,
      code: String(error.code),
      message: String(error.message),
    };
  }
  if (error instanceof Error) {
    return {
      sourceId,
      code: error.name || 'SOURCE_ERROR',
      message: error.message,
    };
  }
  return {
    sourceId,
    code: 'SOURCE_ERROR',
    message: String(error),
  };
}

async function runWithTimeout(sourceId, operation, timeoutMs) {
  const abortController = new AbortController();
  const timer = setTimeout(() => abortController.abort(), timeoutMs);
  try {
    return await operation(abortController.signal);
  } catch (error) {
    if (abortController.signal.aborted) {
      throw createTimeoutError(sourceId, timeoutMs);
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

function createStubExecution(sourcePlan) {
  return {
    sourceId: sourcePlan.sourceId,
    status: 'stub',
    ok: false,
    items: [],
    error: {
      sourceId: sourcePlan.sourceId,
      code: 'STUB_SOURCE',
      message: `Source ${sourcePlan.sourceId} requires claude-session execution`,
    },
    durationMs: 0,
  };
}

export async function executePlan(plan, sourceRegistry) {
  const sourcePlans = plan.sourcePlans ?? plan.sources.map((entry) => {
    if (typeof entry === 'string') return { sourceId: entry };
    return { sourceId: entry.sourceId, ...entry };
  });
  const tasks = sourcePlans.map(async (sourcePlan) => {
    const sourceId = sourcePlan.sourceId;
    if (sourcePlan.executionMode === 'claude-session') {
      return createStubExecution(sourcePlan);
    }

    const source = sourceRegistry[sourceId];
    if (!source) {
      return {
        sourceId,
        status: 'error',
        ok: false,
        items: [],
        error: {
          sourceId,
          code: 'UNKNOWN_SOURCE',
          message: `Source not registered: ${sourceId}`,
        },
        durationMs: 0,
      };
    }

    const startedAt = Date.now();
    try {
      const timeoutMs = SOURCE_TIMEOUT_MS[sourceId] ?? DEFAULT_TIMEOUT_MS;
      const response = await runWithTimeout(
        sourceId,
        (signal) =>
          source.search({
            query: plan.query,
            maxResults: plan.maxResults,
            signal,
          }),
        timeoutMs,
      );
      return {
        sourceId,
        status: response.error ? 'error' : 'ok',
        ok: !(response.error),
        items: response.items ?? [],
        error: response.error ?? null,
        durationMs: Date.now() - startedAt,
      };
    } catch (error) {
      const sourceError = toSourceError(sourceId, error);
      return {
        sourceId,
        status: sourceError.code === 'TIMEOUT' ? 'timeout' : 'error',
        ok: false,
        items: [],
        error: sourceError,
        durationMs: Date.now() - startedAt,
      };
    }
  });

  const settled = await Promise.allSettled(tasks);
  return settled.map((result, index) => {
    if (result.status === 'fulfilled') {
      return result.value;
    }
    const sourceId = sourcePlans[index].sourceId;
    return {
      sourceId,
      status: 'error',
      ok: false,
      items: [],
      error: toSourceError(sourceId, result.reason),
      durationMs: 0,
    };
  });
}
