"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const root = path.resolve(__dirname, "../..");
const legacyFunctions = ["createClinic", "setClinicStatus", "resendInitialAdminInvite"];
const f1Functions = ["getClinicDetails", "updateClinicOperations"];
const f2DemoFunctions = ["getClinicDetails", "updateClinicTrial"];
// Exact reviewed batches only: never arbitrary subsets or a broad codebase.
const functionBatches = [legacyFunctions, f1Functions, [...legacyFunctions, ...f1Functions]];
const targets = {
  "moodsogood-9e45b": { config: "firebase.json", codebase: "default", source: "functions" },
  "innera-demo": { config: "firebase.demo.json", codebase: "demo-b2b", source: "functions_demo" },
};
function validate(plan) {
  const target = targets[plan.project];
  if (!target || plan.codebase !== target.codebase || path.resolve(plan.config || "") !== path.join(root, target.config)) throw new Error("Wrong project/config/codebase combination");
  const selected = (plan.only || "").split(",").sort();
  const allowedBatches = plan.project === "innera-demo" ? [...functionBatches, f2DemoFunctions] : functionBatches;
  const functions = allowedBatches.find(batch => JSON.stringify(selected) === JSON.stringify(
    batch.map(name => `functions:${target.codebase}:${name}`).sort()
  ));
  if (!functions) throw new Error("An exact explicit batch is required: legacy three, F1 pair, all five, or Demo-only F2 pair");
  const expected = functions.map(name => `functions:${target.codebase}:${name}`).sort();
  const config = JSON.parse(fs.readFileSync(plan.config, "utf8"));
  const entries = config.functions;
  if (!Array.isArray(entries) || entries.length !== 1 || entries[0].codebase !== target.codebase || entries[0].source !== target.source) throw new Error("Unexpected function source in config");
  if (fs.realpathSync(path.join(root, target.source)) !== path.join(fs.realpathSync(root), target.source)) throw new Error("Unexpected source redirection");
  const exports = fs.readFileSync(path.join(root, target.source, "index.js"), "utf8");
  for (const name of functions) if (!exports.includes(`exports.${name} =`)) throw new Error(`Missing export: ${name}`);
  for (const name of ["clinics.js", "platform_audit.js", "clinic_trial.js"]) {
    if (!fs.readFileSync(path.join(root, "functions/src/clinic", name)).equals(fs.readFileSync(path.join(root, "functions_demo/src/clinic", name)))) throw new Error(`Production/Demo source drift: ${name}`);
  }
  if (functions === f2DemoFunctions) {
    const source = fs.readFileSync(path.join(root, target.source, "src/clinic/clinics.js"), "utf8");
    for (const name of functions) {
      const declaration = new RegExp(`exports\\.${name} = onCall\\(\\s*\\{\\s*region: "asia-east1"\\s*\\}`);
      if (!declaration.test(source)) throw new Error(`Unexpected F2 region declaration: ${name}`);
    }
  }
  return { project: plan.project, config: path.join(root, target.config), codebase: target.codebase, only: expected.join(",") };
}
function parse(args) {
  const plan = {}; let mode;
  for (let i = 0; i < args.length; i++) {
    const key = args[i];
    if (["--check", "--execute", "--predeploy"].includes(key)) { if (mode) throw new Error("Choose one mode"); mode = key; }
    else if (["--project", "--config", "--codebase", "--only"].includes(key)) {
      if (plan[key.slice(2)] || !args[i + 1] || args[i + 1].startsWith("--")) throw new Error("Missing or duplicate argument");
      plan[key.slice(2)] = args[++i];
    } else throw new Error("Unknown argument");
  }
  if (!mode) throw new Error("Specify --check (local validation) or --execute (deployment)");
  return { mode, plan };
}
function main(args, env = process.env) {
  const { mode, plan } = parse(args);
  if (mode === "--predeploy") {
    if (Object.keys(plan).length) throw new Error("Predeploy accepts only wrapper context");
    const verified = validate(JSON.parse(env.INNERA_PLATFORM_DEPLOY_PLAN || "null") || {});
    if (env.GCLOUD_PROJECT !== verified.project || path.resolve(env.PROJECT_DIR || "") !== root || path.resolve(env.RESOURCE_DIR || "") !== path.join(root, targets[verified.project].source)) throw new Error("CLI deployment context does not match approved plan");
    console.log("Platform predeploy context validated"); return;
  }
  const verified = validate(plan);
  const cliArgs = ["deploy", "--project", verified.project, "--config", verified.config, "--only", verified.only, "--non-interactive"];
  console.log("Validated command:", "firebase", ...cliArgs.map(arg => arg.includes(" ") ? `"${arg}"` : arg));
  if (mode === "--check") return; // Never loads Firebase CLI or contacts a service.
  // An explicit --execute is required. Never use --force or accept deletion prompts.
  const result = spawnSync(process.platform === "win32" ? "firebase.cmd" : "firebase", cliArgs, {
    cwd: root, stdio: "inherit", shell: process.platform === "win32",
    env: { ...env, INNERA_PLATFORM_DEPLOY_PLAN: JSON.stringify(verified) },
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error("Firebase deploy failed; no automatic retry");
}
if (require.main === module) { try { main(process.argv.slice(2)); } catch (error) { console.error("Deployment blocked:", error.message); process.exitCode = 1; } }
module.exports = { validate, parse, main, root };
