"use strict";
const { PROJECT, requireThat } = require("./protocol");
// Temporary acceptance hook, exclusively in the isolated encrypted demo codebase.
const ENABLED = false;
async function afterProviderResponse({ projectId, uid, clinicId }) {
  if (!ENABLED) return;
  requireThat(projectId === PROJECT && uid === "demo-encrypted-sleep-patient" && clinicId === "demo-sleep-clinic", "failed-precondition");
  console.info("demo.openai.race_delay", { stage: "response_received_before_authorization_recheck", delayMs: 15000 });
  await new Promise(resolve => setTimeout(resolve, 15000));
}
module.exports = { ENABLED, afterProviderResponse };
