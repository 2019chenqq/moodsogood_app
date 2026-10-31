"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createKms } = require("../kms");
const { VERSION, keyPair } = require("./helpers");
const mapping = { "clinic-a": { writeVersion: VERSION, readVersions: [VERSION] } };
test("KMS adapter binds approved demo key versions and does not accept private key material", async () => {
  let calls = 0;
  const kms = createKms({ mapping, credential: { getAccessToken: async () => ({ access_token: "synthetic-test-token" }) },
    fetchImpl: async (url, options) => {
      calls++;
      assert.ok(url.startsWith(`https://cloudkms.googleapis.com/v1/${VERSION}`));
      if (options.method === "GET") return { ok: true, json: async () => ({ name: VERSION,
        algorithm: "RSA_DECRYPT_OAEP_3072_SHA256", pem: keyPair.publicKey.export({ type: "spki", format: "pem" }) }) };
      return { ok: true, json: async () => ({ plaintext: Buffer.alloc(32).toString("base64") }) };
    },
  });
  assert.equal((await kms.publicKey("clinic-a")).keyVersion, VERSION);
  assert.equal((await kms.unwrap("clinic-a", VERSION, Buffer.alloc(384))).length, 32);
  await assert.rejects(() => kms.unwrap("clinic-b", VERSION, Buffer.alloc(384)));
  assert.equal(calls, 2);
  assert.throws(() => createKms({ mapping: { "clinic-a": { writeVersion: VERSION.replace("innera-demo", "production"), readVersions: [VERSION.replace("innera-demo", "production")] } } }));
  assert.throws(() => createKms({ mapping: { ...mapping, "clinic-b": mapping["clinic-a"] } }));
});
