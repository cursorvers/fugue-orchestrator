'use strict';
/**
 * manus-api-client.js — Manus API HTTP client for FUGUE slide pipeline
 * Zero external deps. Node.js built-ins only.
 *
 * Extracted from manus-slide-generator.js (v4.0 -> v4.2) to separate
 * API transport concerns from slide content/prompt logic.
 *
 * Exports: makeRequest, pollTaskCompletion, downloadFile,
 *          extractOutputFiles, downloadOutputFiles, maskApiKey, API_CONFIG
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

// API-related configuration (immutable)
const API_CONFIG = Object.freeze({
  baseURL: 'api.manus.ai',
  apiVersion: 'v1',
  timeout: 300000,
  pollInterval: 15000,
  maxPollAttempts: 120,
});

// === Utility ===

/** Mask API keys and tokens in log messages to prevent credential leakage. */
function maskApiKey(message) {
  return String(message)
    .replace(/API_KEY[:\s]+[A-Za-z0-9_.\-]{8,}/gi, 'API_KEY: ***MASKED***')
    .replace(/Bearer [A-Za-z0-9_.\-]{20,}/g, 'Bearer ***MASKED***')
    .replace(/[A-Za-z0-9_\-]{32,}/g, '***MASKED***');
}

// === HTTP Layer ===

/** Build request headers for Manus API calls. */
function buildRequestHeaders(method, apiKey, postData) {
  const baseHeaders = {
    'API_KEY': apiKey,
    'Accept': 'application/json',
    'User-Agent': 'FUGUE-SlideGenerator/4.2',
  };
  if (method === 'GET' || !postData) return baseHeaders;
  return {
    ...baseHeaders,
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(postData),
  };
}

/** Send an HTTP request to the Manus API. Returns parsed JSON response. */
function makeRequest(method, apiPath, data) {
  return new Promise((resolve, reject) => {
    const apiKey = process.env.MANUS_API_KEY || process.env.MANUS_MCP_API_KEY;
    if (!apiKey) { reject(new Error('MANUS_API_KEY or MANUS_MCP_API_KEY not set')); return; }

    const postData = data ? JSON.stringify(data) : null;
    const options = {
      hostname: API_CONFIG.baseURL, port: 443,
      path: `/${API_CONFIG.apiVersion}${apiPath}`, method,
      headers: buildRequestHeaders(method, apiKey, postData),
      timeout: API_CONFIG.timeout,
    };

    const req = https.request(options, (res) => {
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => {
        const body = Buffer.concat(chunks).toString();
        try {
          const json = JSON.parse(body);
          if (res.statusCode >= 200 && res.statusCode < 300) resolve(json);
          else reject(new Error(`API ${res.statusCode}: ${json.message || body}`));
        } catch { reject(new Error(`API ${res.statusCode}: ${body.substring(0, 200)}`)); }
      });
    });
    req.on('error', (err) => reject(new Error(`Network error: ${err.message}`)));
    req.on('timeout', () => { req.destroy(); reject(new Error('Request timeout')); });
    if (postData) req.write(postData);
    req.end();
  });
}

// === Task Polling ===

/** Poll a Manus task until completion or failure. Handles transient 404s. */
async function pollTaskCompletion(taskId) {
  const maxTransient404 = 3;
  let transient404Count = 0;
  for (let attempt = 0; attempt < API_CONFIG.maxPollAttempts; attempt++) {
    let status;
    try {
      status = await makeRequest('GET', `/tasks/${taskId}`);
    } catch (err) {
      // Treat 404 as transient during early polls (task may not be queryable yet)
      if (err.message.includes('API 404') && transient404Count < maxTransient404) {
        transient404Count += 1;
        console.error(`[POLL] Task not found yet (${transient404Count}/${maxTransient404}), retrying...`);
        await new Promise(r => setTimeout(r, API_CONFIG.pollInterval));
        continue;
      }
      throw err;
    }
    transient404Count = 0; // Reset on successful response
    if (status.status === 'completed') return status;
    if (status.status === 'failed')
      throw new Error(`Manus task failed: ${status.error || 'Unknown error'}`);
    const elapsed = ((attempt + 1) * API_CONFIG.pollInterval / 1000).toFixed(0);
    console.error(`[POLL] ${status.status || 'processing'}... (${elapsed}s elapsed)`);
    await new Promise(r => setTimeout(r, API_CONFIG.pollInterval));
  }
  throw new Error(`Polling timeout after ${API_CONFIG.maxPollAttempts * API_CONFIG.pollInterval / 1000}s`);
}

// === File Download ===

/** Download a file (binary-safe, follows redirects). */
function downloadFile(fileUrl, destPath) {
  return new Promise((resolve, reject) => {
    const url = new URL(fileUrl);
    const options = {
      hostname: url.hostname, port: url.port || 443,
      path: url.pathname + url.search, method: 'GET', timeout: API_CONFIG.timeout,
    };
    const req = https.request(options, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        downloadFile(res.headers.location, destPath).then(resolve).catch(reject);
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        reject(new Error(`Download failed: HTTP ${res.statusCode}`)); return;
      }
      const stream = fs.createWriteStream(destPath);
      res.pipe(stream);
      stream.on('finish', () => { stream.close(); resolve(destPath); });
      stream.on('error', reject);
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Download timeout')); });
    req.end();
  });
}

// === Output File Extraction ===

/** Extract file entries from Manus API response (supports multiple structures). */
function extractOutputFiles(taskResult) {
  // Structure 1: Manus actual — output[].content[].type === "output_file"
  if (Array.isArray(taskResult.output)) {
    const outputFiles = taskResult.output
      .filter(entry => entry && Array.isArray(entry.content))
      .flatMap(entry => entry.content)
      .filter(item => item && item.type === 'output_file' && item.fileUrl)
      .map(item => ({ url: item.fileUrl, name: item.fileName || 'output.html' }));
    if (outputFiles.length > 0) return outputFiles;
  }

  // Structure 2: Legacy — output_files / files / artifacts arrays
  const legacyFiles = taskResult.output_files || taskResult.files || taskResult.artifacts || [];
  return legacyFiles.map(file => {
    if (typeof file === 'string') {
      return { url: file, name: path.basename(new URL(file).pathname) };
    }
    const url = file.url || file.download_url || file.fileUrl || '';
    const name = file.name || file.filename || file.fileName
      || (url ? path.basename(new URL(url).pathname) : 'output.html');
    return { url, name };
  }).filter(f => f.url);
}

/** Download all output files from completed Manus task. */
async function downloadOutputFiles(taskResult, outputDir) {
  if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true });

  const files = extractOutputFiles(taskResult);
  const downloaded = [];

  for (const file of files) {
    const destPath = path.join(outputDir, file.name);
    try {
      await downloadFile(file.url, destPath);
      downloaded.push(destPath);
      console.error(`[OK] Downloaded: ${file.name}`);
    } catch (err) {
      console.error(`[WARN] Failed to download ${file.name}: ${maskApiKey(err.message)}`);
    }
  }

  // Fallback: save inline output as HTML if no files extracted
  if (downloaded.length === 0 && taskResult.output) {
    const inlineContent = typeof taskResult.output === 'string'
      ? taskResult.output
      : JSON.stringify(taskResult.output);
    const inlinePath = path.join(outputDir, 'master.html');
    fs.writeFileSync(inlinePath, inlineContent, 'utf-8');
    downloaded.push(inlinePath);
    console.error('[OK] Saved inline output as master.html');
  }
  return downloaded;
}

// === Module Exports (immutable) ===

module.exports = Object.freeze({
  makeRequest,
  pollTaskCompletion,
  downloadFile,
  extractOutputFiles,
  downloadOutputFiles,
  maskApiKey,
  API_CONFIG,
});
