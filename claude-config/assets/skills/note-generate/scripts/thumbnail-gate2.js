/**
 * thumbnail-gate2.js — Automated visual quality gate for thumbnails
 *
 * Sends the full-resolution image (1280x670) to Gemini Flash and asks
 * whether the main text would be readable at 160x90px display size.
 *
 * Design decisions (from critical review):
 * - Send full-res, NOT downscaled 160x90 (gives model actual pixel data)
 * - No sips dependency (headless/launchd compatibility)
 * - Fail-open on API errors (gate2Skipped=true, never blocks pipeline)
 * - Called once after final image, not inside retry loop
 *
 * Exports: passGate2
 */

// ── Constants ──────────────────────────────────────────────
const ANALYSIS_MODEL = 'gemini-2.0-flash';

const ANALYSIS_PROMPT = `You are a thumbnail quality inspector. This image is a blog thumbnail (1280x670px).
It will be displayed at 160x90px on note.com feeds.

Evaluate the following and respond ONLY with valid JSON (no markdown, no explanation):
{
  "mainTextReadable": true/false,  // Can the largest text be read at 160x90px?
  "contrastSufficient": true/false, // Is text-to-background contrast high enough?
  "simplifiedChineseDetected": true/false, // Does any text appear to be simplified Chinese?
  "overallPass": true/false, // true if mainTextReadable=true AND contrastSufficient=true AND simplifiedChineseDetected=false
  "reasoning": "Brief explanation in English"
}`;

// ── Response Validation ───────────────────────────────────
function validateGate2Response(parsed) {
  if (typeof parsed !== 'object' || parsed === null) return null;
  const boolFields = ['mainTextReadable', 'contrastSufficient', 'simplifiedChineseDetected', 'overallPass'];
  for (const f of boolFields) {
    if (typeof parsed[f] !== 'boolean') return null;
  }
  if (typeof parsed.reasoning !== 'string') return null;
  return parsed;
}

function extractJsonFromText(text) {
  // Try direct parse first
  try { return JSON.parse(text); } catch { /* continue */ }
  // Try extracting from markdown code fence
  const match = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (match) {
    try { return JSON.parse(match[1].trim()); } catch { /* continue */ }
  }
  // Try finding first { ... } block
  const braceMatch = text.match(/\{[\s\S]*\}/);
  if (braceMatch) {
    try { return JSON.parse(braceMatch[0]); } catch { /* continue */ }
  }
  return null;
}

// ── Logging ───────────────────────────────────────────────
function log(level, msg, data) {
  const entry = { ts: new Date().toISOString(), level, component: 'thumbnail-gate2', msg, ...data };
  process.stderr.write(JSON.stringify(entry) + '\n');
}

// ── Gate 2: Visual Quality Check ──────────────────────────
/**
 * @param {Buffer} imageBuffer — full-resolution PNG (1280x670)
 * @param {object} GoogleGenerativeAI — SDK constructor
 * @param {string} apiKey — Gemini API key
 * @returns {{ overallPass: boolean, gate2Skipped?: boolean, checks?: object, reasoning?: string }}
 */
export async function passGate2(imageBuffer, GoogleGenerativeAI, apiKey) {
  // Fail-open: no SDK or key = skip
  if (!GoogleGenerativeAI || !apiKey) {
    log('warn', 'Gate 2 skipped: no SDK or API key');
    return { overallPass: true, gate2Skipped: true };
  }

  if (!imageBuffer || imageBuffer.length === 0) {
    log('warn', 'Gate 2 skipped: empty buffer');
    return { overallPass: true, gate2Skipped: true };
  }

  try {
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
      model: ANALYSIS_MODEL,
      generationConfig: { responseMimeType: 'application/json' },
    });

    const base64Data = imageBuffer.toString('base64');
    const result = await model.generateContent([
      { inlineData: { data: base64Data, mimeType: 'image/png' } },
      { text: ANALYSIS_PROMPT },
    ]);

    const responseText = result?.response?.candidates?.[0]?.content?.parts
      ?.map(p => p.text).filter(Boolean).join('') ?? '';

    if (!responseText) {
      log('warn', 'Gate 2: empty Gemini response');
      return { overallPass: true, gate2Skipped: true };
    }

    const parsed = extractJsonFromText(responseText);
    const validated = parsed ? validateGate2Response(parsed) : null;

    if (!validated) {
      log('warn', 'Gate 2: invalid response structure', { raw: responseText.slice(0, 200) });
      return { overallPass: true, gate2Skipped: true };
    }

    log('info', 'Gate 2 result', validated);
    return {
      overallPass: validated.overallPass,
      gate2Skipped: false,
      checks: {
        mainTextReadable: validated.mainTextReadable,
        contrastSufficient: validated.contrastSufficient,
        simplifiedChineseDetected: validated.simplifiedChineseDetected,
      },
      reasoning: validated.reasoning,
    };
  } catch (err) {
    // Fail-open: API errors never block the pipeline
    log('error', 'Gate 2 failed (fail-open)', {
      error: err.message, stack: err.stack,
      errorType: err.constructor?.name,
    });
    return { overallPass: true, gate2Skipped: true };
  }
}
