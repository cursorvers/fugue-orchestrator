import { createCrowAdapter } from "./adapters/happy-app-crow.js";
import { createEndpointClient } from "./adapters/happy-endpoint-client.js";
import { createIntakeAdapter } from "./adapters/happy-app-intake.js";
import { createRecoveryAdapter } from "./adapters/happy-app-recovery.js";
import { createStateAdapter } from "./adapters/happy-app-state.js";
import { resolveHappyRuntimeConfig } from "./config/happy-runtime-config.js";

export const runtimeConfig = resolveHappyRuntimeConfig();
export const endpointClient = createEndpointClient({ config: runtimeConfig });
export const crowAdapter = createCrowAdapter();
export const stateAdapter = createStateAdapter({ crowAdapter, config: runtimeConfig, endpointClient });
export const intakeAdapter = createIntakeAdapter();
export const recoveryAdapter = createRecoveryAdapter({ stateAdapter });

export function buildIntakePacket(params) {
  return intakeAdapter.buildPacket(params);
}
