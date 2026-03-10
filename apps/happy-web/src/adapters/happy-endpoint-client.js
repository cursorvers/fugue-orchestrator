function buildHeaders(authToken) {
  const headers = {
    "Content-Type": "application/json",
  };
  if (authToken) headers.Authorization = `Bearer ${authToken}`;
  return headers;
}

export function createEndpointClient({ config }) {
  async function fetchJson(url, options = {}) {
    const response = await fetch(url, {
      method: options.method || "GET",
      headers: {
        ...buildHeaders(config?.authToken),
        ...(options.headers || {}),
      },
      body: options.body ? JSON.stringify(options.body) : undefined,
    });

    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(`HTTP ${response.status}: ${text || response.statusText}`);
    }

    if (response.status === 204) return {};

    const text = await response.text();
    if (!text.trim()) return {};

    return JSON.parse(text);
  }

  return {
    fetchJson,
  };
}
