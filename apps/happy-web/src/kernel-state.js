import { createCrowAdapter } from "./adapters/happy-app-crow.js";
import { createIntakeAdapter } from "./adapters/happy-app-intake.js";
import { createRecoveryAdapter } from "./adapters/happy-app-recovery.js";
import { createStateAdapter } from "./adapters/happy-app-state.js";

export const crowAdapter = createCrowAdapter();
export const stateAdapter = createStateAdapter({ crowAdapter });
export const intakeAdapter = createIntakeAdapter();
export const recoveryAdapter = createRecoveryAdapter({ stateAdapter });

export function buildIntakePacket(params) {
  return intakeAdapter.buildPacket(params);
}
