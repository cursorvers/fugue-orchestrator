import { createSourceError } from './base.js';

export function createStubSource(sourceId, message) {
  return {
    id: sourceId,
    async search() {
      return {
        items: [],
        error: createSourceError(sourceId, 'STUB_SOURCE', message),
      };
    },
  };
}
