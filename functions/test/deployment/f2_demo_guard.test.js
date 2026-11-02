"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const fs = require("node:fs");
const vm = require("node:vm");
const root = path.resolve(__dirname, "../../..");
const script = path.join(root, "functions/scripts/platform-deploy.cjs");
const config = path.join(root, "firebase.demo.json");
function plan(demo = true) {
  const codebase = demo ? "demo-b2b" : "default";
  return { project: demo ? "innera-demo" : "moodsogood-9e45b", codebase,
    config: demo ? config : path.join(root, "firebase.json"),
    only: ["getClinicDetails", "updateClinicTrial"].map(n => `functions:${codebase}:${n}`).join(",") };
}

// Supply only the missing Demo config in memory. Source files and exports are real.
function guardWithRead(transform = (_file, _encoding, value) => value) {
  const module = { exports: {} };
  function injectedRequire(name) {
    if (name === "node:child_process") return { spawnSync() { throw new Error("CLI must not run"); } };
    if (name === "node:fs") return { ...fs, readFileSync(file, encoding) {
      const value = file === config
        ? JSON.stringify({ functions: [{ source: "functions_demo", codebase: "demo-b2b" }] })
        : fs.readFileSync(file, encoding);
      return transform(file, encoding, value);
    } };
    return require(name);
  }
  vm.runInNewContext(fs.readFileSync(script, "utf8"), {
    module, exports: module.exports, require: injectedRequire, __dirname: path.dirname(script), console,
  }, { filename: script });
  return module.exports;
}
const guard = guardWithRead();

test("F2 Demo exact pair passes check without CLI and matching predeploy only", () => {
  const p = plan();
  guard.main(["--check", ...Object.entries(p).flatMap(([k, v]) => [`--${k}`, v])], {});
  assert.equal(guard.validate(p).only, p.only);
  assert.equal(guard.validate({ ...p, only: p.only.split(",").reverse().join(",") }).only, guard.validate(p).only);
  const env = { INNERA_PLATFORM_DEPLOY_PLAN: JSON.stringify(p), GCLOUD_PROJECT: p.project,
    PROJECT_DIR: guard.root, RESOURCE_DIR: path.join(guard.root, "functions_demo") };
  guard.main(["--predeploy"], env);
  for (const key of Object.keys(env)) assert.throws(() => guard.main(["--predeploy"], { ...env, [key]: "wrong" }));
});
test("F2 rejects Production, incorrect project/codebase/config and non-exact selectors", () => {
  const p = plan();
  assert.throws(() => guard.validate(plan(false)));
  for (const patch of [{ project: "unknown" }, { project: "moodsogood-9e45b" }, { codebase: "default" },
    { config: path.join(guard.root, "firebase.json") }]) assert.throws(() => guard.validate({ ...p, ...patch }));
  for (const only of ["functions", "functions:demo-b2b", "functions:demo-b2b:*", ...p.only.split(","),
    "functions:getClinicDetails,functions:updateClinicTrial", p.only + ",functions:demo-b2b:createClinic",
    p.only + ",functions:demo-b2b:updateClinicOperations", p.only + ",firestore", p.only + ",hosting",
    p.only + ",functions:demo-b2b:updateClinicTrial"]) assert.throws(() => guard.validate({ ...p, only }));
});
test("F2 rejects missing export, trial helper drift and wrong region", () => {
  const p = plan();
  const helper = path.join(guard.root, "functions_demo/src/clinic/clinic_trial.js");
  assert.throws(() => guardWithRead((file, encoding, value) => file === helper
    ? Buffer.concat([value, Buffer.from("\n// drift")]) : value).validate(p), /source drift/);
  const entry = path.join(guard.root, "functions_demo/index.js");
  assert.throws(() => guardWithRead((file, encoding, value) => file === entry
    ? value.replace("exports.updateClinicTrial =", "exports.missing =") : value).validate(p), /Missing export/);
  // Modify both in-memory copies to isolate the region check from parity checks.
  assert.throws(() => guardWithRead((file, encoding, value) => file.endsWith(path.join("src", "clinic", "clinics.js"))
    ? encoding ? value.replaceAll('"asia-east1"', '"us-central1"') : Buffer.from(value.toString().replaceAll('"asia-east1"', '"us-central1"'))
    : value).validate(p), /region/);
});
