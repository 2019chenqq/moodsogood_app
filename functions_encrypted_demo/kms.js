"use strict";
const { createPublicKey } = require("node:crypto");
const { requireThat, versionName } = require("./protocol");

// Configuration contains only public resource names, never key material.
// No fallback to a local private key is allowed in the deployed adapter.
function createKms({ mapping, credential, fetchImpl = fetch }) {
  requireThat(mapping && typeof mapping === "object", "failed-precondition");
  const owners = new Map();
  for (const [clinic, config] of Object.entries(mapping)) {
    requireThat(Array.isArray(config.readVersions) && config.readVersions.includes(config.writeVersion), "failed-precondition");
    for (const version of config.readVersions) {
      versionName(version);
      const key = version.split("/cryptoKeyVersions/")[0];
      requireThat(!owners.has(key) || owners.get(key) === clinic, "failed-precondition");
      owners.set(key, clinic);
    }
  }
  function canRead(clinic, version) { return mapping[clinic]?.readVersions.includes(version) === true; }
  function canWrite(clinic, version) { return mapping[clinic]?.writeVersion === version; }
  async function call(version, suffix, body) {
    versionName(version);
    const { access_token } = await credential.getAccessToken();
    const response = await fetchImpl(`https://cloudkms.googleapis.com/v1/${version}${suffix}`, {
      method: body ? "POST" : "GET",
      headers: { Authorization: `Bearer ${access_token}`, "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(15000),
    });
    requireThat(response.ok, "unavailable");
    return response.json();
  }
  return {
    canRead, canWrite,
    async publicKey(clinic) {
      const keyVersion = mapping[clinic]?.writeVersion;
      requireThat(keyVersion, "failed-precondition");
      const result = await call(keyVersion, "/publicKey");
      requireThat(result.algorithm === "RSA_DECRYPT_OAEP_3072_SHA256" && result.name === keyVersion, "failed-precondition");
      const key = createPublicKey(result.pem);
      requireThat(key.asymmetricKeyDetails?.modulusLength === 3072, "failed-precondition");
      return { keyVersion, publicKeyPem: result.pem };
    },
    async unwrap(clinic, version, ciphertext) {
      requireThat(canRead(clinic, version));
      const result = await call(version, ":asymmetricDecrypt", { ciphertext: ciphertext.toString("base64") });
      const plain = Buffer.from(result.plaintext || "", "base64");
      requireThat(plain.length === 32, "data-loss");
      return plain;
    },
  };
}
module.exports = { createKms };
