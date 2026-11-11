import { test } from "node:test";
import assert from "node:assert/strict";
import { parseConfig } from "../src/config.js";

test("valid config with default replicas", () => {
  const r = parseConfig({ port: 8080, host: "api", tls: { enabled: false } });
  assert.deepEqual(r, { ok: true, config: { port: 8080, host: "api", tls: { enabled: false }, replicas: 1 } });
});

test("all errors reported with paths", () => {
  const r = parseConfig({ port: 70000, host: "", tls: { enabled: true }, replicas: 0 });
  assert.equal(r.ok, false);
  if (!r.ok) {
    assert.deepEqual(r.errors.sort(), [
      "host: must be a non-empty string",
      "port: must be an integer between 1 and 65535",
      "replicas: must be an integer >= 1",
      "tls.certPath: required when tls.enabled is true",
    ]);
  }
});

test("non-object input", () => {
  assert.deepEqual(parseConfig(42), { ok: false, errors: ["config: must be an object"] });
});
