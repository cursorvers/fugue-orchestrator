#!/usr/bin/env node
"use strict";

const fs = require("node:fs");

const MANUS_CLIENT_PATH = "/Users/masayuki/.codex/skills/slide/scripts/manus-api-client.js";

function argValue(args, name, fallback = "") {
  const idx = args.indexOf(name);
  if (idx < 0) return fallback;
  return args[idx + 1] || fallback;
}

function boolEnv(name, fallback = false) {
  const raw = String(process.env[name] || "").trim().toLowerCase();
  if (!raw) return fallback;
  return ["1", "true", "yes", "on"].includes(raw);
}

function resolveManusAccess() {
  const started = Date.now();
  if (!fs.existsSync(MANUS_CLIENT_PATH)) {
    return {
      apiKeyAvailable: false,
      clientAvailable: false,
      reason: "manus-client-missing",
      checkLatencyMs: Date.now() - started,
    };
  }
  try {
    const client = require(MANUS_CLIENT_PATH);
    const key = typeof client.resolveApiKey === "function" ? client.resolveApiKey() : "";
    return {
      apiKeyAvailable: Boolean(key),
      clientAvailable: true,
      reason: key ? "key-resolved" : "key-missing",
      checkLatencyMs: Date.now() - started,
    };
  } catch (err) {
    return {
      apiKeyAvailable: false,
      clientAvailable: false,
      reason: `client-load-failed: ${String(err && err.message ? err.message : err).slice(0, 120)}`,
      checkLatencyMs: Date.now() - started,
    };
  }
}

function main() {
  const args = process.argv.slice(2);
  const repo = argValue(args, "--repo", process.env.GITHUB_REPOSITORY || "");
  const issueNumber = argValue(args, "--issue-number", process.env.RECOVERY_ISSUE_NUMBER || "");
  const runUrl = argValue(args, "--run-url", "");
  const execute = args.includes("--execute") || boolEnv("RECOVERY_MANUS_EXECUTE", false);
  const access = resolveManusAccess();

  const recommendations = [];
  if (!access.clientAvailable) {
    recommendations.push("restore-or-install-manus-slide-client-before-routing-live-repair");
  }
  if (!access.apiKeyAvailable) {
    recommendations.push("resolve-manus-api-key-before-spending-repair-budget");
  }
  recommendations.push("prefer-github-actions-and-kernel-recovery-for-deterministic-repairs");
  recommendations.push("use-manus-only-for-novel-diagnosis-or-artifact-synthesis-after-local-tests-fail");
  recommendations.push("keep-manus-live-execution-manual-until-diagnosis-receipts-are-stable");

  const blockingCondition = !access.clientAvailable
    ? "api"
    : !access.apiKeyAvailable
      ? "auth"
      : "none";
  const overallHealthScore = access.clientAvailable && access.apiKeyAvailable
    ? 100
    : access.clientAvailable
      ? 70
      : 40;

  const receipt = {
    success: true,
    provider: "manus",
    mode: "diagnose",
    sloVersion: 1,
    execute,
    liveExecutionStarted: false,
    clientAvailable: access.clientAvailable,
    apiKeyAvailable: access.apiKeyAvailable,
    accessReason: access.reason,
    checkLatencyMs: access.checkLatencyMs,
    overallHealthScore,
    blockingCondition,
    componentHealth: {
      client: access.clientAvailable ? "ok" : "missing",
      apiKey: access.apiKeyAvailable ? "ok" : "missing",
      liveExecution: "disabled",
    },
    input: {
      repo,
      issueNumber,
      runUrl,
    },
    recommendations,
    nextAction: access.apiKeyAvailable
      ? "keep-manus-standby-and-run-deterministic-kernel-gha-recovery-first"
      : "fix-manus-key-resolution-before-enabling-any-live-manus-repair",
  };

  if (execute) {
    receipt.success = false;
    receipt.overallHealthScore = Math.min(receipt.overallHealthScore, 30);
    receipt.blockingCondition = "execute";
    receipt.componentHealth.liveExecution = "blocked";
    receipt.nextAction = "manual-approval-required-for-live-manus-repair";
    receipt.recommendations.unshift("live-manus-repair-is-intentionally-disabled-in-diagnose-mode");
  }

  console.log(JSON.stringify(receipt));
  process.exitCode = receipt.success ? 0 : 2;
}

main();
