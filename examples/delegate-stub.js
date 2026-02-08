#!/usr/bin/env node

/**
 * FUGUE Orchestrator - Delegation Script Stub
 *
 * This is a minimal reference implementation showing how delegation
 * scripts work. Replace the API calls with your actual provider SDKs.
 *
 * Usage:
 *   node delegate-stub.js -a architect -t "Design the auth system" -f src/auth.ts
 *
 * Environment:
 *   OPENAI_API_KEY - For Codex/GPT delegation
 *   GLM_API_KEY    - For GLM-4.7 delegation
 *   GEMINI_API_KEY - For Gemini delegation
 */

const { parseArgs } = require("node:util");

// --- CLI Argument Parsing ---

const { values } = parseArgs({
  options: {
    agent: { type: "string", short: "a" },
    task: { type: "string", short: "t" },
    file: { type: "string", short: "f" },
    provider: { type: "string", short: "p", default: "codex" },
    thinking: { type: "boolean", default: false },
  },
});

const AGENT = values.agent || "general-reviewer";
const TASK = values.task || "";
const FILE = values.file || "";
const PROVIDER = values.provider || "codex";

if (!TASK) {
  console.error("Error: --task (-t) is required");
  process.exit(1);
}

// --- Provider Configurations ---

const PROVIDERS = {
  codex: {
    name: "Codex (OpenAI)",
    envKey: "OPENAI_API_KEY",
    endpoint: "https://api.openai.com/v1/chat/completions",
    model: "gpt-4o",
    buildPayload: (systemPrompt, userPrompt) => ({
      model: "gpt-4o",
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      temperature: 0.2,
    }),
  },
  glm: {
    name: "GLM-4.7 (Z.ai)",
    envKey: "GLM_API_KEY",
    endpoint: "https://open.z.ai/api/paas/v4/chat/completions",
    model: "glm-4.7",
    buildPayload: (systemPrompt, userPrompt) => ({
      model: "glm-4.7",
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      temperature: 0.2,
    }),
  },
  gemini: {
    name: "Gemini (Google)",
    envKey: "GEMINI_API_KEY",
    endpoint:
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent",
    model: "gemini-2.0-flash",
    buildPayload: (_systemPrompt, userPrompt) => ({
      contents: [{ parts: [{ text: userPrompt }] }],
    }),
  },
};

// --- Agent System Prompts ---

const AGENT_PROMPTS = {
  architect: `You are a senior software architect. Analyze the design and provide:
- Architecture assessment
- Potential issues
- Recommendations
Be concise and actionable.`,

  "code-reviewer": `You are a code reviewer. Evaluate code quality on a 7-point scale:
1. Readability
2. Maintainability
3. Performance
4. Security
5. Test coverage
6. Error handling
7. Best practices
Provide specific, actionable feedback.`,

  "security-analyst": `You are a security analyst. Check for:
- OWASP Top 10 vulnerabilities
- Authentication/authorization issues
- Input validation gaps
- Secret exposure risks
Score security on a 3-point scale (0-3). Be specific about findings.`,

  "scope-analyst": `You are a requirements analyst. Evaluate:
- Scope clarity
- Edge cases
- Feasibility
- Risks
Provide structured analysis.`,

  "plan-reviewer": `You are a plan reviewer. Assess:
- Completeness
- Feasibility
- Risk identification
- Priority ordering
Score the plan and suggest improvements.`,

  "general-reviewer": `You are a general-purpose reviewer. Provide clear,
concise analysis of the given task. Focus on actionable insights.`,

  "math-reasoning": `You are a math and logic specialist. Verify calculations,
algorithms, and logical reasoning. Show your work step by step.`,
};

// --- Main Execution ---

async function delegate() {
  const provider = PROVIDERS[PROVIDER];
  if (!provider) {
    console.error(`Unknown provider: ${PROVIDER}`);
    console.error(`Available: ${Object.keys(PROVIDERS).join(", ")}`);
    process.exit(1);
  }

  const apiKey = process.env[provider.envKey];
  if (!apiKey) {
    console.error(`Missing ${provider.envKey} environment variable`);
    process.exit(1);
  }

  const systemPrompt =
    AGENT_PROMPTS[AGENT] || AGENT_PROMPTS["general-reviewer"];

  let userPrompt = `TASK: ${TASK}`;
  if (FILE) {
    // In a real implementation, read the file content here
    userPrompt += `\n\nFILE: ${FILE}`;
    // userPrompt += `\n\nCONTENT:\n${fs.readFileSync(FILE, 'utf-8')}`;
  }

  console.log(`\n  Delegating to ${provider.name} (${AGENT})...`);
  console.log(`  Model: ${provider.model}`);
  console.log(`  Task: ${TASK.substring(0, 80)}...`);

  const startTime = Date.now();

  try {
    const payload = provider.buildPayload(systemPrompt, userPrompt);

    const headers = { "Content-Type": "application/json" };

    if (PROVIDER === "gemini") {
      // Gemini uses query parameter for auth
      const url = `${provider.endpoint}?key=${apiKey}`;
      const response = await fetch(url, {
        method: "POST",
        headers,
        body: JSON.stringify(payload),
      });
      const data = await response.json();
      const text =
        data.candidates?.[0]?.content?.parts?.[0]?.text || "No response";
      console.log(`\n${text}`);
    } else {
      // OpenAI / GLM use Bearer token
      headers["Authorization"] = `Bearer ${apiKey}`;
      const response = await fetch(provider.endpoint, {
        method: "POST",
        headers,
        body: JSON.stringify(payload),
      });
      const data = await response.json();
      const text = data.choices?.[0]?.message?.content || "No response";
      console.log(`\n${text}`);
    }

    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
    console.log(`\n  Processing time: ${elapsed}s`);
  } catch (error) {
    console.error(`\n  Error: ${error.message}`);
    process.exit(1);
  }
}

delegate();
