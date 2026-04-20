import {
  DEFAULT_FORMAT,
  DEFAULT_MAX_RESULTS,
  DEFAULT_PARALLEL,
  KNOWN_SOURCES,
} from './config.js';

function createValidationError(message) {
  const error = new Error(message);
  error.name = 'ValidationError';
  return error;
}

function createFallbackSchema() {
  class FallbackSchema {
    /**
     * @param {(value: unknown) => unknown} parser
     */
    constructor(parser) {
      this.parser = parser;
    }

    parse(value) {
      return this.parser(value);
    }

    optional() {
      return new FallbackSchema((value) => {
        if (value === undefined) {
          return undefined;
        }
        return this.parse(value);
      });
    }

    default(defaultValue) {
      return new FallbackSchema((value) => {
        if (value === undefined) {
          return defaultValue;
        }
        return this.parse(value);
      });
    }
  }

  const z = {
    unknown() {
      return new FallbackSchema((value) => value);
    },
    string() {
      return new FallbackSchema((value) => {
        if (typeof value !== 'string') {
          throw createValidationError('Expected string');
        }
        return value;
      });
    },
    boolean() {
      return new FallbackSchema((value) => {
        if (typeof value !== 'boolean') {
          throw createValidationError('Expected boolean');
        }
        return value;
      });
    },
    number() {
      return new FallbackSchema((value) => {
        if (typeof value !== 'number' || Number.isNaN(value)) {
          throw createValidationError('Expected number');
        }
        return value;
      });
    },
    enum(values) {
      return new FallbackSchema((value) => {
        if (!values.includes(value)) {
          throw createValidationError(`Expected one of: ${values.join(', ')}`);
        }
        return value;
      });
    },
    array(schema) {
      return new FallbackSchema((value) => {
        if (!Array.isArray(value)) {
          throw createValidationError('Expected array');
        }
        return value.map((item) => schema.parse(item));
      });
    },
    record(valueSchema) {
      return new FallbackSchema((value) => {
        if (value === null || typeof value !== 'object' || Array.isArray(value)) {
          throw createValidationError('Expected object record');
        }
        /** @type {Record<string, unknown>} */
        const parsed = {};
        for (const [key, item] of Object.entries(value)) {
          parsed[key] = valueSchema.parse(item);
        }
        return parsed;
      });
    },
    object(shape) {
      return new FallbackSchema((value) => {
        if (value === null || typeof value !== 'object' || Array.isArray(value)) {
          throw createValidationError('Expected object');
        }
        /** @type {Record<string, unknown>} */
        const record = value;
        /** @type {Record<string, unknown>} */
        const parsed = {};
        for (const [key, schema] of Object.entries(shape)) {
          parsed[key] = schema.parse(record[key]);
        }
        return parsed;
      });
    },
    coerce: {
      number() {
        return new FallbackSchema((value) => {
          const parsed = Number(value);
          if (Number.isNaN(parsed)) {
            throw createValidationError('Expected coercible number');
          }
          return parsed;
        });
      },
    },
  };

  return z;
}

let z = createFallbackSchema();

try {
  const module = await import('zod');
  z = module.z;
} catch {
  z = createFallbackSchema();
}

const formatSchema = z.enum(['json', 'markdown', 'summary']);
const sourceSchema = z.enum(KNOWN_SOURCES);
const confidenceSchema = z.enum([
  'primary',
  'secondary-high',
  'secondary-mid',
  'secondary-low',
]);
const executionModeSchema = z.enum(['direct', 'claude-session']);
const executionStatusSchema = z.enum(['ok', 'error', 'timeout', 'stub']);

export const searchRequestSchema = z.object({
  query: z.string(),
  format: formatSchema.default(DEFAULT_FORMAT),
  maxResults: z.coerce.number().default(DEFAULT_MAX_RESULTS),
  parallel: z.boolean().default(DEFAULT_PARALLEL),
  sources: z.array(sourceSchema).optional(),
});

export const normalizedItemSchema = z.object({
  sourceId: sourceSchema,
  title: z.string(),
  url: z.string(),
  snippet: z.string(),
  confidenceLabel: confidenceSchema,
});

export const sourceErrorSchema = z.object({
  sourceId: sourceSchema,
  code: z.string(),
  message: z.string(),
});

export const mcpToolSchema = z.object({
  tool: z.string(),
  params: z.record(z.unknown()),
});

export const searchPlanSourceSchema = z.object({
  sourceId: sourceSchema,
  confidence: confidenceSchema,
  via: z.string(),
  executionMode: executionModeSchema,
  mcpTools: z.array(mcpToolSchema),
});

export const searchPlanSchema = z.object({
  query: z.string(),
  sources: z.array(searchPlanSourceSchema),
  options: z.object({
    maxResults: z.number(),
    timeout: z.number(),
    format: formatSchema,
  }),
});

export const searchExecutionItemSchema = z.object({
  title: z.string(),
  url: z.string(),
  snippet: z.string(),
  metadata: z.record(z.unknown()),
});

export const searchExecutionSourceSchema = z.object({
  sourceId: sourceSchema,
  status: executionStatusSchema,
  items: z.array(searchExecutionItemSchema),
  error: z
    .object({
      code: z.string(),
      message: z.string(),
    })
    .optional(),
  durationMs: z.number(),
});

export const searchExecutionResultSchema = z.object({
  sources: z.array(searchExecutionSourceSchema),
});
