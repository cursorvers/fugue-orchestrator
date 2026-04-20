import { searchRequestSchema } from './schemas.js';
import { DEFAULT_FORMAT, DEFAULT_MAX_RESULTS, DEFAULT_PARALLEL } from './config.js';

export function getHelpText() {
  return [
    'Usage: node scripts/search.js [query] [options]',
    '',
    'Options:',
    '  --query <text>         Search query',
    '  --plan-only            Print execution plan JSON and exit',
    '  --aggregate <file>     Read execution result JSON and format it',
    '  --format <format>      Output format: summary | json | markdown',
    '  --max-results <count>  Maximum number of results',
    '  --sources <list>       Comma-separated source ids',
    '  --parallel [true|false]',
    '  --no-parallel',
    '  --help                 Show this help',
  ].join('\n');
}

function parseBooleanFlag(value, fallback) {
  if (value === undefined) {
    return fallback;
  }
  if (value === 'true') {
    return true;
  }
  if (value === 'false') {
    return false;
  }
  throw new Error(`Invalid boolean value: ${value}`);
}

export function parseArgs(argv) {
  /** @type {{
   * query?: string,
   * format: string,
   * maxResults: number,
   * parallel: boolean,
   * sources?: string[],
   * planOnly: boolean,
   * aggregate?: string,
   * help: boolean,
   * warnings: string[],
   * }} */
  const draft = {
    format: DEFAULT_FORMAT,
    maxResults: DEFAULT_MAX_RESULTS,
    parallel: DEFAULT_PARALLEL,
    planOnly: false,
    help: false,
    warnings: [],
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--help') {
      draft.help = true;
      continue;
    }
    if (token === '--query') {
      if (argv[index + 1] === undefined) {
        throw new Error('Missing value for --query');
      }
      draft.query = argv[index + 1];
      index += 1;
      continue;
    }
    if (token === '--format') {
      if (argv[index + 1] === undefined) {
        throw new Error('Missing value for --format');
      }
      draft.format = argv[index + 1];
      index += 1;
      continue;
    }
    if (token === '--plan-only') {
      draft.planOnly = true;
      continue;
    }
    if (token === '--aggregate') {
      if (argv[index + 1] === undefined) {
        throw new Error('Missing value for --aggregate');
      }
      draft.aggregate = argv[index + 1];
      index += 1;
      continue;
    }
    if (token === '--max-results') {
      if (argv[index + 1] === undefined) {
        throw new Error('Missing value for --max-results');
      }
      draft.maxResults = Number(argv[index + 1]);
      index += 1;
      continue;
    }
    if (token === '--sources') {
      if (argv[index + 1] === undefined) {
        throw new Error('Missing value for --sources');
      }
      const value = argv[index + 1] ?? '';
      draft.sources = value
        .split(',')
        .map((item) => item.trim())
        .filter(Boolean);
      index += 1;
      continue;
    }
    if (token === '--parallel') {
      const next = argv[index + 1];
      if (next && !next.startsWith('--')) {
        draft.parallel = parseBooleanFlag(next, DEFAULT_PARALLEL);
        index += 1;
      } else {
        draft.parallel = true;
      }
      continue;
    }
    if (token === '--no-parallel') {
      draft.parallel = false;
      continue;
    }
    if (token.startsWith('--')) {
      draft.warnings.push(`Unknown option ignored: ${token}`);
      continue;
    }
    if (!token.startsWith('--') && !draft.query) {
      draft.query = token;
    }
  }

  if (draft.help) {
    return {
      help: true,
      warnings: draft.warnings,
    };
  }

  const parsed = searchRequestSchema.parse({
    ...draft,
    query: draft.query ?? '',
  });
  if (draft.aggregate) {
    return {
      ...parsed,
      help: false,
      planOnly: draft.planOnly,
      aggregate: draft.aggregate,
      warnings: draft.warnings,
    };
  }

  if (!parsed.query || !parsed.query.trim()) {
    throw new Error('Query is required');
  }
  return {
    ...parsed,
    help: false,
    planOnly: draft.planOnly,
    aggregate: draft.aggregate,
    query: parsed.query.trim(),
    warnings: draft.warnings,
  };
}
