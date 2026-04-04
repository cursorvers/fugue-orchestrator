/**
 * thumbnail-gate2.js — Automated visual quality gate for thumbnails
 *
 * Sends the full-resolution image (1280x670) to Gemini Flash and asks
 * whether the main text would be readable at 160x90px display size.
 *
 * Design decisions:
 * - Send full-res, not downscaled 160x90 data
 * - No GUI/image-tool dependency
 * - Fail-open on API errors
 * - Called once after final image generation
 *
 * Exports: passGate2
 */

const ANALYSIS_MODEL = 'gemini-2.0-flash';

const ANALYSIS_PROMPT = `You are a thumbnail quality inspector. This image is a blog thumbnail (1280x670px).
It will be displayed at 160x90px on note.com feeds.

Evaluate the following and respond ONLY with valid JSON (no markdown, no explanation):
{
  "mainTextReadable": true/false,
  "contrastSufficient": true/false,
  "simplifiedChineseDetected": true/false,
  "overallPass": true/false,
  "reasoning": "Brief explanation in English"
}`;

function validateGate2Response(parsed) {
  if (typeof parsed !== 'object' || parsed === null) return null;
  const boolFields = ['mainTextReadable', 'contrastSufficient', 'simplifiedChineseDetected', 'overallPass'];
  for (const field of boolFields) {
    if (typeof parsed[field] !== 'boolean') return null;
  }
  if (typeof parsed.reasoning !== 'string') return null;
  return parsed;
}

function extractJsonFromText(text) {
  try {
    return JSON.parse(text);
  } catch {
    // continue
  }

  const codeFence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (codeFence) {
    try {
      return JSON.parse(codeFence[1].trim());
    } catch {
      // continue
    }
  }

  const braceBlock = text.match(/\{[\s\S]*\}/);
  if (braceBlock) {
    try {
      return JSON.parse(braceBlock[0]);
    } catch {
      // continue
    }
  }

  return null;
}

function log(level, msg, data) {
  const entry = { ts: new Date().toISOString(), level, component: 'thumbnail-gate2', msg, ...data };
  process.stderr.write(JSON.stringify(entry) + '\n');
}

export async function passGate2(imageBuffer, GoogleGenerativeAI, apiKey) {
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

    const result = await model.generateContent([
      { inlineData: { data: imageBuffer.toString('base64'), mimeType: 'image/png' } },
      { text: ANALYSIS_PROMPT },
    ]);

    const responseText = result?.response?.candidates?.[0]?.content?.parts
      ?.map((part) => part.text)
      .filter(Boolean)
      .join('') ?? '';

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
    log('error', 'Gate 2 failed (fail-open)', {
      error: err.message,
      stack: err.stack,
      errorType: err.constructor?.name,
    });
    return { overallPass: true, gate2Skipped: true };
  }
}
