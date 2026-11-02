"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const fs = require("node:fs");
const vm = require("node:vm");
const { spawnSync } = require("node:child_process");
const guard = require("../../scripts/platform-deploy.cjs");
const script = path.join(guard.root, "functions/scripts/platform-deploy.cjs");
function plan(demo = false, batch = "legacy") {
  const codebase = demo ? "demo-b2b" : "default";
  return { project: demo ? "innera-demo" : "moodsogood-9e45b", config: path.join(guard.root, demo ? "firebase.demo.json" : "firebase.json"), codebase,
    only: ({ legacy: ["createClinic", "setClinicStatus", "resendInitialAdminInvite"],
      f1: ["getClinicDetails", "updateClinicOperations"],
      f2: ["getClinicDetails", "updateClinicTrial"],
      all: ["createClinic", "setClinicStatus", "resendInitialAdminInvite", "getClinicDetails", "updateClinicOperations"]
    })[batch].map(n => `functions:${codebase}:${n}`).join(",") };
}
for (const demo of [false, true]) {
 for (const batch of ["legacy", "f1", "all"]) {
  test(`${demo ? "Demo" : "Production"}/${batch}: explicit local check passes without CLI execution`, () => {
    const p = plan(demo, batch);
    const args = ["--check", ...Object.entries(p).flatMap(([k,v]) => [`--${k}`,v])];
    // No CLI is available on PATH: success proves --check does not launch it.
    const result = spawnSync(process.execPath, [script, ...args], { env: { ...process.env, PATH: "" }, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr); assert.match(result.stdout, /Validated command/);
    assert.match(result.stdout, /--non-interactive/); assert.doesNotMatch(result.stdout, /--force/);
  });
  test(`${demo ? "Demo" : "Production"}/${batch}: predeploy accepts only matching context`, () => {
    const p = guard.validate(plan(demo, batch));
    const env = { INNERA_PLATFORM_DEPLOY_PLAN: JSON.stringify(p), GCLOUD_PROJECT: p.project, PROJECT_DIR: guard.root, RESOURCE_DIR: path.join(guard.root, demo ? "functions_demo" : "functions") };
    guard.main(["--predeploy"], env);
    for (const key of Object.keys(env)) assert.throws(() => guard.main(["--predeploy"], { ...env, [key]: "wrong" }));
  });
 }
}
test("wrong project, config and codebase combinations are rejected", () => {
  for (const patch of [{ project: "unknown" }, { project: "innera-demo" }, { config: path.join(guard.root, "firebase.demo.json") }, { codebase: "demo-b2b" }]) assert.throws(() => guard.validate({ ...plan(), ...patch }));
});
test("missing, broad, extra, duplicated and unqualified function selectors are rejected", () => {
  for (const only of [undefined, "functions", "functions:default", "functions:createClinic", plan().only + ",firestore", plan().only + ",functions:default:createClinic", "functions:default:createClinic"]) assert.throws(() => guard.validate({ ...plan(), only }));
});
for (const demo of [false, true]) {
  test(`${demo ? "Demo" : "Production"}: F1 partial, mixed, duplicate, wildcard and cross-project selectors fail`, () => {
    const p = plan(demo, "f1");
    const other = plan(!demo, "f1");
    for (const only of [p.only.split(",")[0], p.only + ",functions:" + p.codebase + ":createClinic",
      p.only + "," + p.only.split(",")[0], p.only + ",hosting", p.only + ",firestore",
      "functions:" + p.codebase + ":*", "functions:getClinicDetails,functions:updateClinicOperations",
      other.only, p.only + ",functions:" + p.codebase + ":deleteOwnAccount"]) {
      assert.throws(() => guard.validate({ ...p, only }));
    }
    assert.throws(() => guard.validate({ ...p, project: other.project }));
    assert.throws(() => guard.validate({ ...p, config: other.config }));
    assert.throws(() => guard.validate({ ...p, codebase: other.codebase }));
    assert.equal(guard.validate({ ...p, only: p.only.split(",").reverse().join(",") }).only,
      p.only.split(",").sort().join(","));
  });
}

function guardWithRead(transform) {
  const module = { exports: {} };
  const injectedRequire = name => name === "node:fs" ? {
    ...fs, readFileSync: (file, encoding) => transform(file, encoding, fs.readFileSync(file, encoding)),
  } : name === "node:child_process" ? { spawnSync() { throw new Error("CLI must not run"); } } : require(name);
  vm.runInNewContext(fs.readFileSync(script, "utf8"), {
    module, exports: module.exports, require: injectedRequire, __dirname: path.dirname(script), console,
  }, { filename: script });
  return module.exports;
}
test("F1 check blocks missing exports in either maintained source", () => {
  for (const demo of [true, false]) for (const name of ["getClinicDetails", "updateClinicOperations"]) {
    const filename = path.join(guard.root, demo ? "functions_demo" : "functions", "index.js");
    const altered = guardWithRead((file, encoding, value) => file === filename
      ? value.replace(`exports.${name} =`, `exports.removed_${name} =`) : value);
    assert.throws(() => altered.validate(plan(demo, "f1")), /Missing export/);
  }
});
test("F1 check blocks clinic or audit source drift without modifying workspace files", () => {
  for (const name of ["clinics.js", "platform_audit.js"]) {
    const filename = path.join(guard.root, "functions_demo/src/clinic", name);
    const altered = guardWithRead((file, encoding, value) => file === filename
      ? Buffer.concat([value, Buffer.from("\n// drift")]) : value);
    assert.throws(() => altered.validate(plan(true, "f1")), /source drift/);
  }
});
test("F1 frontends load environment config and shared scripts in the correct order", () => {
  const frontend = path.resolve(guard.root, "../Innera_platform_admin");
  for (const demo of [true, false]) {
    const html = fs.readFileSync(path.join(frontend, demo ? "dashboard.demo.html" : "dashboard.html"), "utf8");
    const scripts = [...html.matchAll(/<script src="([^"]+)"/g)].map(match => match[1]);
    assert.deepEqual(scripts.slice(-5), [`./js/firebase-config-${demo ? "demo" : "prod"}.js`,
      "./js/admin-core.js", "./js/admin-clinics.js", "./js/admin-clinic-details.js", "./js/admin-create-clinic.js"]);
    assert.match(scripts[scripts.length - 6], /firebase-functions-compat\.js$/);
    assert.doesNotMatch(html, /clinic-details-mock|data-innera-preview/);
    const context = { window: {} };
    vm.runInNewContext(fs.readFileSync(path.join(frontend, `js/firebase-config-${demo ? "demo" : "prod"}.js`), "utf8"), context);
    assert.equal(context.window.INNERA_FIREBASE_CONFIG.projectId, demo ? "innera-demo" : "moodsogood-9e45b");
    assert.equal(context.window.INNERA_ADMIN_ENV.projectId, context.window.INNERA_FIREBASE_CONFIG.projectId);
  }
  const details = fs.readFileSync(path.join(frontend, "js/admin-clinic-details.js"), "utf8");
  assert.match(details, /functions\("asia-east1"\)/);
  for (const name of ["getClinicDetails", "updateClinicOperations"]) assert.ok(details.includes(`call("${name}"`));
});
test("missing mode, unknown flags and duplicate arguments are rejected", () => {
  for (const args of [[], ["--force"], ["--check", "--execute"], ["--check", "--project"], ["--check", "--project", "a", "--project", "b"]]) assert.throws(() => guard.parse(args));
});
test("direct predeploy without wrapper plan is blocked", () => assert.throws(() => guard.main(["--predeploy"], {})));

test("both maintained configs contain the deployment guard", () => {
  for (const demo of [false, true]) assert.ok(JSON.parse(fs.readFileSync(plan(demo).config)).functions[0].predeploy[0].includes("platform-deploy.cjs"));
});
test("legacy npm deployment and Firebase predeploy both lead to a failing guard", () => {
  const legacy = path.resolve(guard.root, "../Innera_platform_admin");
  const config = JSON.parse(fs.readFileSync(path.join(legacy, "firebase.json")));
  const pkg = JSON.parse(fs.readFileSync(path.join(legacy, "functions/package.json")));
  assert.match(config.functions[0].predeploy[0], /block-deploy.cjs/);
  assert.equal(pkg.scripts.deploy, "node scripts/block-deploy.cjs");
  const result = spawnSync(process.execPath, [path.join(legacy, "functions/scripts/block-deploy.cjs")], { encoding: "utf8" });
  assert.equal(result.status, 1); assert.match(result.stderr, /Deployment blocked/);
  assert.match(fs.readFileSync(path.join(legacy, "functions/index.js"), "utf8"), /exports.createClinic/);
});
