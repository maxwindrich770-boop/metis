import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

// Execute the exact app-owned script, not a second implementation of the bridge.
const swift = readFileSync(new URL("../MetisiOS/MetisWebWorkspace.swift", import.meta.url), "utf8");
const source = swift.match(/static let userScript = #"""\n([\s\S]*?)\n    """#/)[1];
const origin = "https://metis.example";
const alice = "metis:onboarding:v1:fixture-alice:browser";
const bob = "metis:onboarding:v1:fixture-bob:browser";
const done = JSON.stringify({ version: 1, phase: "done", tourIndex: 0 });
function page({ seed = [], pageOrigin = origin, subframe = false, blocked = false, existingHook = false } = {}) {
  class Storage {
    values = new Map();
    getItem(key) { return this.values.get(String(key)) ?? null; }
    setItem(key, value) { if (blocked) throw new Error("Storage disabled"); this.values.set(String(key), String(value)); }
    removeItem(key) { this.values.delete(String(key)); }
    clear() { this.values.clear(); }
  }
  const localStorage = new Storage(), sessionStorage = new Storage(), messages = [], previousWrites = [];
  if (existingHook) {
    const original = Storage.prototype.setItem;
    Storage.prototype.setItem = function(key, value) {
      original.apply(this, arguments);
      previousWrites.push([String(key), String(value)]);
    };
  }
  const window = { localStorage, webkit: { messageHandlers: { metisOnboarding: {
    postMessage: body => messages.push(body),
  } } } };
  window.top = subframe ? {} : window;
  const context = vm.createContext({
    window, location: { origin: pageOrigin }, Storage, URL, TextEncoder,
    metisOnboardingOrigin: origin, metisCompletedOnboardingKeys: seed,
  });
  vm.runInContext(source, context);
  return { localStorage, sessionStorage, messages, previousWrites };
}
test("a fresh app does not skip the guide or persist an incomplete guide", () => {
  const p = page();
  assert.equal(p.localStorage.getItem(alice), null);
  p.localStorage.setItem(alice, JSON.stringify({ version: 1, phase: "welcome", tourIndex: 0 }));
  assert.equal(p.messages.length, 0);
});
test("real completion survives a recreated ephemeral page before hydration", () => {
  const first = page();
  first.localStorage.setItem(alice, done);
  assert.equal(first.messages.length, 1);
  assert.equal(first.messages[0].key, alice);
  assert.equal(first.messages[0].value, done);
  const restarted = page({ seed: first.messages.map(message => message.key) });
  assert.equal(restarted.localStorage.getItem(alice), done);
  assert.equal(restarted.messages.length, 0, "Restoring must not generate a persistence loop");
});
test("one account does not skip the guide for another account", () => {
  const p = page({ seed: [alice] });
  assert.equal(p.localStorage.getItem(alice), done);
  assert.equal(p.localStorage.getItem(bob), null);
});
test("foreign origins and subframes cannot restore or report completions", () => {
  for (const options of [{ pageOrigin: "https://other.example" }, { subframe: true }]) {
    const p = page({ ...options, seed: [alice] });
    assert.equal(p.localStorage.getItem(alice), null);
    p.localStorage.setItem(alice, done);
    assert.equal(p.messages.length, 0);
  }
});
test("unrelated storage, credentials and desktop onboarding are excluded", () => {
  const keys = ["auth_token", "x_model", "metis-onboarding-completed",
    "metis:onboarding:v1::browser", "metis:onboarding:v1:alice:desktop",
    "metis:onboarding:v1:" + "a".repeat(600) + ":browser"];
  const p = page({ seed: keys });
  for (const key of keys) {
    assert.equal(p.localStorage.getItem(key), null);
    p.localStorage.setItem(key, done);
    assert.equal(p.localStorage.getItem(key), done, "Unrelated Web UI storage remains usable");
  }
  assert.equal(p.messages.length, 0);
  p.sessionStorage.setItem(alice, done);
  assert.equal(p.messages.length, 0);
});
test("malformed, future-version and unfinished state cannot complete the guide", () => {
  const p = page();
  for (const value of ["null", "{}", "invalid", "x".repeat(1025),
    '{"version":true,"phase":"done","tourIndex":0}',
    '{"version":2,"phase":"done","tourIndex":0}',
    '{"version":1,"phase":"tour","tourIndex":0}',
    '{"version":1,"phase":"done","tourIndex":1}']) {
    p.localStorage.setItem(alice, value);
  }
  assert.equal(p.messages.length, 0);
});
test("manual reopening is not blocked and does not erase previous native completion", () => {
  const p = page({ seed: [alice] });
  p.localStorage.setItem(alice, '{"version":1,"phase":"welcome","tourIndex":0}');
  assert.equal(JSON.parse(p.localStorage.getItem(alice)).phase, "welcome");
  assert.equal(p.messages.length, 0);
  p.localStorage.clear();
  assert.equal(p.localStorage.getItem(alice), null);
  assert.equal(page({ seed: [alice] }).localStorage.getItem(alice), done);
});
test("completion bridging composes with the existing model preference storage hook", () => {
  const p = page({ existingHook: true });
  p.localStorage.setItem("fixture_model", "opaque-fixture-model");
  p.localStorage.setItem(alice, done);
  assert.equal(p.localStorage.getItem("fixture_model"), "opaque-fixture-model");
  assert.equal(p.previousWrites.length, 2);
  assert.equal(p.messages.length, 1);
  assert.equal(p.messages[0].key, alice);
});
test("disabled Web storage fails closed without forcing completion", () => {
  const p = page({ seed: [alice], blocked: true });
  assert.equal(p.localStorage.getItem(alice), null);
  assert.equal(p.messages.length, 0);
});
test("the native string catalog has no non-English translation on German devices", () => {
  const catalog = JSON.parse(readFileSync(new URL("../Shared/Localizable.xcstrings", import.meta.url)));
  assert.equal(catalog.sourceLanguage, "en");
  assert.ok(Object.hasOwn(catalog.strings, "iPhone controls"));
  for (const entry of Object.values(catalog.strings)) {
    assert.deepEqual(Object.keys(entry.localizations ?? {}).filter(locale => locale !== "en"), []);
  }
});
