// Exercise the real Metis handlers and worker over loopback with a disposable
// SQLite database and a deterministic model fixture.
import { once } from "node:events";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { tmpdir, userInfo } from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

// Synthetic authenticated page for integration tests only. It intentionally uses
// the public fixture account and the real cookie-protected auth/chat handlers.
function webWorkspaceFixture(username: string, cookieName: string, externalAddress: string) {
  const scriptValue = (value: string) => JSON.stringify(value).replaceAll("<", "\\u003c");
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Metis WebKit integration fixture</title>
  <style>
    body { font: 17px system-ui; margin: 20px; }
    button, a { display: block; min-height: 44px; margin: 12px 0; }
  </style>
</head>
<body>
  <main>
    <p>Synthetic integration fixture; not the Metis web design.</p>
    <h1>Authenticated web workspace fixture</h1>
    <p id="account"></p>
    <p id="cookie-state" role="status">Checking the web session…</p>
    <button id="save-chat">Save a chat from the web fixture</button>
    <h2>Saved chats</h2>
    <ul id="saved-chats"></ul>
    <button id="rotate-session">Rotate the web session</button>
    <p id="rotation-state" role="status"></p>
    <a href="/fixture-web/download" download="metis-web-fixture.txt">Download the public web fixture</a>
    <a href="${externalAddress}" target="_blank" rel="noopener">Open the external fixture in a new window</a>
    <button id="scripted-external">Get an API key from the web fixture</button>
    <button id="logout">Sign out from the web fixture</button>
    <a href="/?fixture=viewport">Open synthetic viewport fixture</a>
    <a href="/?fixture=composer-zoom">Open synthetic contenteditable composer fixture</a>
    <a href="/?fixture=viewport-empty">Open synthetic centered empty-state fixture</a>
    <a href="/?fixture=viewport-empty-flow">Open synthetic empty composer flow fixture</a>
    <a href="/?fixture=viewport-empty-large">Open synthetic large empty composer fixture</a>
    <a href="/?fixture=viewport-tall">Open synthetic tall composer transcript fixture</a>
    <a href="/?fixture=sidebar">Open synthetic sidebar fixture</a>
    <a href="/?fixture=toasts">Open notification safe-area fixture</a>
    <a href="/?fixture=model-preferences">Open synthetic model preference storage fixture</a>
    <p id="error" role="alert"></p>
  </main>
  <script>
    const expectedUsername = ${scriptValue(username)};
    const cookieName = ${scriptValue(cookieName)};
    const savedTitle = "Saved from web fixture";
    const element = id => document.getElementById(id);
    element("account").textContent = expectedUsername;
    const fail = error => { element("error").textContent = String(error.message || error); };
    async function request(url, options) {
      const response = await fetch(url, { credentials: "same-origin", ...options });
      if (!response.ok) throw new Error("Fixture request failed: " + response.status);
      return response;
    }
    async function verifyCookie() {
      const account = await (await request("/api/mobile/session")).json();
      if (account.username !== expectedUsername) throw new Error("Unexpected web session owner");
      const visibleCookie = document.cookie.split(";").some(part => part.trim().startsWith(cookieName + "="));
      if (visibleCookie) throw new Error("Session cookie must remain HttpOnly");
      element("cookie-state").textContent = "HttpOnly cookie verified";
    }
    async function loadChats() {
      const result = await (await request("/api/chats")).json();
      element("saved-chats").replaceChildren();
      for (const chat of result.chats.filter(chat => chat.title === savedTitle)) {
        const item = document.createElement("li");
        item.textContent = chat.title;
        element("saved-chats").append(item);
      }
    }
    element("save-chat").addEventListener("click", async () => {
      try {
        await request("/api/chats", {
          method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({ title: savedTitle }),
        });
        await loadChats();
      } catch (error) { fail(error); }
    });
    element("rotate-session").addEventListener("click", async () => {
      try {
        // Public synthetic fixture credentials. The real auth handler revokes the
        // old cookie and issues a new HttpOnly cookie; JavaScript never sees it.
        await request("/api/auth", {
          method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({ username: "metis-apple-fixture-alice", password: "apple-fixture-only" }),
        });
        window.location.assign("/?session=rotated");
      } catch (error) { fail(error); }
    });
    element("scripted-external").addEventListener("click", () => {
      // Mirrors setup buttons that open a provider page with window.open.
      window.open(${scriptValue(externalAddress)}, "_blank", "noopener,noreferrer");
    });
    element("logout").addEventListener("click", async () => {
      try {
        await request("/api/auth", { method: "DELETE" });
        window.location.reload();
      } catch (error) { fail(error); }
    });
    Promise.all([verifyCookie(), loadChats()]).then(() => {
      if (new URL(window.location.href).searchParams.get("session") === "rotated") {
        element("rotation-state").textContent = "Session rotated in web fixture";
      }
    }).catch(fail);
  </script>
</body>
</html>`;
}


// Dedicated, authenticated synthetic drawer fixture; no notebooks or automations are mutated.
let toastFixtureBundle: Promise<string> | undefined;
async function webToastFixture() {
  // tsx already supplies esbuild to this fixture runner; no product dependency.
  const require = createRequire(import.meta.url);
  const { build } = createRequire(require.resolve("tsx"))("esbuild");
  toastFixtureBundle ??= build({
    entryPoints: [path.resolve("clients/apple/Tests/toast-fixture.tsx")],
    bundle: true, write: false, minify: true, platform: "browser", format: "iife",
    define: { "process.env.NODE_ENV": '"production"' },
  }).then((result: { outputFiles: { text: string }[] }) => result.outputFiles[0].text);
  const script = (await toastFixtureBundle).replaceAll("</script", "<\\/script");
  return `<!doctype html><html lang="en"><head>
    <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <title>Notification safe-area fixture</title>
    <style>body{margin:0;font:17px system-ui;background:#fff;color:#171717}
      .metis-shell{padding:calc(16px + env(safe-area-inset-top)) 16px 16px}button{display:block;min-height:44px;margin:16px 0}
      #safe-area-probe{position:fixed;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) 0 env(safe-area-inset-left)}
      #toast-metrics{display:block;padding:16px;font:12px monospace;overflow-wrap:anywhere}</style>
    </head><body><div id="safe-area-probe"></div><div id="toast-root"></div>
    <output id="toast-metrics">Notice geometry: pending</output><script>${script}</script></body></html>`;
}

function webSidebarFixture(username: string) {
  const expectedUsername = JSON.stringify(username).replaceAll("<", "\\u003c");
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>SYNTHETIC sidebar navigation fixture — not Metis design</title>
<style>
:root{--background:#f6f4ee;--foreground:#20231e;--popover:#fffdf8;--muted:#e1e2da}
*{box-sizing:border-box}html,body{margin:0;height:100%;overflow:hidden;font:17px system-ui;background:var(--background);color:var(--foreground)}
[hidden]{display:none!important}button,input{font:inherit}button{min-height:44px;border:1px solid #989b90;border-radius:10px;padding:8px 12px;color:inherit;background:var(--popover)}
.metis-shell{height:100dvh;overflow:hidden;padding:12px}header{display:flex;gap:8px;align-items:center;min-height:56px}
main{padding:12px;overflow:auto;height:calc(100% - 56px)}h1{font-size:22px}#sidebar-state{font-size:10px;overflow-wrap:anywhere}
#sidebar-close-overlay{position:fixed;inset:0;z-index:10;background:#0002;opacity:0;pointer-events:none;border:0;transition:opacity 200ms}
aside[aria-label="Chats sidebar"]{position:fixed;inset:0 auto 0 0;z-index:20;width:min(320px,calc(100vw - 44px));background:var(--popover);border-right:1px solid #999;transition:transform 200ms ease-out}
.visible{visibility:visible;transform:translateX(0)}.invisible{visibility:hidden;transform:translateX(-100%)}
.sidebar-inner{height:100%;display:flex;flex-direction:column;overflow:hidden}.brand{padding:24px 12px 8px;flex:none}
.sidebar-nav{padding:12px 8px 4px;flex:none}.sidebar-nav>button{display:flex;width:100%;gap:8px;text-align:left;border:0;font-size:13px;padding:8px 10px}
.sidebar-nav span{flex:1}kbd{font-size:10px}.sidebar-nav kbd{display:none}.metis-sidebar-scroll{flex:1;min-height:0;overflow:auto;padding:8px}
.metis-sidebar-scroll>button{display:block;width:100%;margin:4px 0;font-size:12px}.sidebar-footer{position:relative;flex:none;padding:8px}
#sidebar-account{width:100%;min-height:48px;text-align:left}#fixture-account-menu{position:absolute;bottom:100%;left:8px;right:8px;padding:8px;border:1px solid #777;background:var(--popover);z-index:25}
.sidebar-search-dialog{position:fixed;z-index:50;top:14dvh;left:50%;transform:translateX(-50%);width:calc(100% - 24px);max-width:560px;background:var(--popover);border:1px solid #777;border-radius:14px;padding:12px}
.search-row{display:flex;gap:8px}#sidebar-search-input{width:100%;min-width:0;height:48px;border:1px solid #777;border-radius:8px;padding:8px}
.search-row input{font-size:14px}
#palette-results{max-height:min(60vh,420px);overflow:auto;padding:8px}#search-state{font:10px/12px system-ui;overflow:hidden;height:84px;overflow-wrap:anywhere}
#safe-bottom-probe{position:fixed;width:0;height:env(safe-area-inset-bottom);visibility:hidden;pointer-events:none}
</style></head><body>
<div class="metis-shell">
<header><button id="sidebar-open" aria-label="Open sidebar" aria-expanded="false">Chats</button><strong>SYNTHETIC sidebar fixture</strong></header>
<main><h1 id="destination">Synthetic destination: New chat</h1><p id="session-state">Checking synthetic sidebar session…</p><p id="sidebar-state" role="status"></p><p id="fixture-error" role="alert"></p><p>No composer is rendered here: Notebooks and Automations keep their normal page layout.</p></main>
<div class="mobile-sidebar-wrapper">
<button id="sidebar-close-overlay" aria-label="Close sidebar" tabindex="-1"></button>
<aside class="fixed inset-y-0 left-0 invisible" aria-label="Chats sidebar">
<div class="sidebar-inner">
<div class="brand" aria-label="Metis">SYNTHETIC Metis brand</div>
<div class="sidebar-nav">
<button id="nav-new" type="button"><span>New chat</span></button>
<button id="nav-search" type="button"><span>Search chats</span><kbd>⌘K</kbd></button>
<button id="nav-notebooks" type="button"><span>Notebooks</span></button>
<button id="nav-automations" type="button"><span>Automations</span></button>
</div>
<div class="metis-sidebar-scroll">
<button id="project-expand" aria-label="Expand synthetic project"><span>Automations</span></button>
<button id="programmatic-nav">Programmatically select New chat</button>
<button id="agent-mode">Use synthetic agent destination</button>
</div>
<div id="sidebar-footer" class="sidebar-footer">
<div id="fixture-account-menu" role="menu" hidden><button id="account-settings" role="menuitem">Settings</button></div>
<button id="sidebar-account" aria-label="Open account menu" aria-controls="fixture-account-menu">Fixture account settings</button>
</div></div></aside>
</div>
<div id="search-dialog" class="sidebar-search-dialog" data-slot="dialog-content" role="dialog" aria-label="Search chats and commands" hidden>
<div class="search-row"><input id="sidebar-search-input" role="combobox" aria-controls="palette-results" aria-label="Search chats or commands" placeholder="Search chats or run a command…" autocomplete="off"><button id="search-close" aria-label="Close search">Close</button></div>
<div id="palette-results" role="listbox" aria-label="Search results"><p>Synthetic search results and commands</p><p id="search-state" role="status"></p><p>Additional synthetic result 1</p><p>Additional synthetic result 2</p><p>Additional synthetic result 3</p><p>Additional synthetic result 4</p><p>Additional synthetic result 5</p><p>Additional synthetic result 6</p><p>Additional synthetic result 7</p><p>Additional synthetic result 8</p><p>Additional synthetic result 9</p><p>Additional synthetic result 10</p><p>Additional synthetic result 11</p><p>Additional synthetic result 12</p><button id="last-search-result">Open synthetic last search result</button></div>
</div>
</div><div id="safe-bottom-probe" aria-hidden="true"></div>
<script>
    const expectedUsername = ${expectedUsername};
    const el = id => document.getElementById(id);
    const sidebar = document.querySelector("aside[aria-label='Chats sidebar']");
    const overlay = el("sidebar-close-overlay");
    const dialog = el("search-dialog");
    const search = el("sidebar-search-input");
    const pageInstance = crypto.randomUUID();
    let activeDestination = "New chat", closeCount = 0, selectionCount = 0;
    let projectExpanded = false, agentMode = false, accountMenuOpen = false;
    let transition = null, transitionRevision = 0, verification = false, closeMotion = null;
    function sidebarOpen() { return sidebar.classList.contains("visible"); }
    function measure() {
      const box = sidebar.getBoundingClientRect(), footer = el("sidebar-footer").getBoundingClientRect();
      const account = el("sidebar-account").getBoundingClientRect();
      const controls = sidebar.querySelector("[data-metis-app-controls]")?.getBoundingClientRect();
      return { sidebarTop: box.top, sidebarHeight: box.height, sidebarBottom: box.bottom,
        footerTop: footer.top, footerBottom: footer.bottom, accountTop: account.top,
        settingsTop: controls?.top ?? null, safeBottom: parseFloat(getComputedStyle(el("safe-bottom-probe")).height) || 0,
        windowHeight: parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--metis-app-window-height")) || innerHeight,
        viewportHeight: innerHeight, width: innerWidth, documentScrollY: scrollY,
        viewportScale: visualViewport?.scale || 1, searchFontSize: parseFloat(getComputedStyle(search).fontSize),
        dialogTop: dialog.hidden ? null : dialog.getBoundingClientRect().top,
        resultsTop: el("palette-results").getBoundingClientRect().top, resultsHeight: el("palette-results").getBoundingClientRect().height };
    }
    function report() {
      const state = { pageInstance, activeDestination, sidebarOpen: sidebarOpen(), closeCount, selectionCount,
        projectExpanded, agentMode, accountMenuOpen, searchOpen: !dialog.hidden, query: search.value,
        authenticated: verification, metrics: measure(), transition, closeMotion };
      el("sidebar-state").textContent = "Synthetic sidebar state: " + JSON.stringify(state);
      el("search-state").textContent = "Synthetic sidebar search state: " + JSON.stringify(state);
    }
    function setSidebar(open) {
      sidebar.classList.toggle("visible", open);
      sidebar.classList.toggle("invisible", !open);
      overlay.tabIndex = open ? 0 : -1;
      overlay.style.pointerEvents = open ? "auto" : "none";
      overlay.style.opacity = open ? "1" : "0";
      el("sidebar-open").setAttribute("aria-expanded", String(open));
      report();
    }
    function select(destination) {
      if (destination === "New chat" && agentMode) {
        el("destination").textContent = "Synthetic new-agent dialog opened";
      } else {
        activeDestination = destination; selectionCount++;
        el("destination").textContent = "Synthetic destination: " + destination;
      }
      // Intentionally retain the server bug: the page switches, but this handler
      // never closes the mobile drawer. The app must invoke the existing close control.
      report();
    }
    el("nav-new").addEventListener("click", () => select("New chat"));
    el("nav-notebooks").addEventListener("click", () => select("Notebooks"));
    el("nav-automations").addEventListener("click", () => select("Automations"));
    el("sidebar-open").addEventListener("click", () => setSidebar(true));
    overlay.addEventListener("click", () => {
      closeCount++;
      const revision = closeCount, started = performance.now(), samples = [];
      const snapshot = () => {
        const box = sidebar.getBoundingClientRect();
        return { right: box.right, width: box.width, visibility: getComputedStyle(sidebar).visibility };
      };
      const initial = snapshot();
      closeMotion = null;
      setSidebar(false);
      function sample(now) {
        if (revision !== closeCount || sidebarOpen()) return;
        samples.push(snapshot());
        if (now - started < 450) { requestAnimationFrame(sample); return; }
        closeMotion = { revision, initial, final: snapshot(), frames: samples.length,
          reducedMotion: matchMedia("(prefers-reduced-motion: reduce)").matches,
          visibleMovingFrames: samples.filter(item => item.right > 1 && item.right < initial.right - 1 && item.visibility === "visible").length,
          hiddenBeforeOffscreen: samples.some(item => item.right > 1 && item.visibility === "hidden") };
        report();
      }
      requestAnimationFrame(sample);
    });
    el("project-expand").addEventListener("click", () => { projectExpanded = !projectExpanded; report(); });
    el("programmatic-nav").addEventListener("click", () => el("nav-new").click());
    el("agent-mode").addEventListener("click", () => {
      agentMode = !agentMode;
      el("nav-new").querySelector("span").textContent = agentMode ? "New agent" : "New chat";
      report();
    });
    el("sidebar-account").addEventListener("click", () => {
      accountMenuOpen = !accountMenuOpen; el("fixture-account-menu").hidden = !accountMenuOpen; report();
    });
    el("account-settings").addEventListener("click", () => {
      el("destination").textContent = "Synthetic settings selected"; report();
    });
    let sampleRevision = 0;
    function sampleSearch(phase) {
      const revision = ++sampleRevision, started = performance.now(), samples = [];
      const initial = measure();
      function sample(now) {
        if (revision !== sampleRevision) return;
        samples.push(measure());
        if (now - started < 900 || samples.length < 18) { requestAnimationFrame(sample); return; }
        const range = key => {
          const values = samples.map(item => item[key]).filter(value => value != null);
          return values.length ? Math.max(...values) - Math.min(...values) : 0;
        };
        transition = { revision: ++transitionRevision, phase, frames: samples.length, duration: now - started,
          initial, final: measure(), sidebarTopRange: range("sidebarTop"), sidebarHeightRange: range("sidebarHeight"),
          footerTopRange: range("footerTop"), accountTopRange: range("accountTop"), settingsTopRange: range("settingsTop"),
          documentScrollRange: range("documentScrollY"), scaleRange: range("viewportScale"), dialogTopRange: range("dialogTop") };
        report();
      }
      sample(started);
    }
    el("nav-search").addEventListener("click", () => {
      dialog.hidden = false;
      sampleSearch("open");
      report();
      setTimeout(() => search.focus({ preventScroll: true }), 0);
    });
    search.addEventListener("blur", () => { if (!dialog.hidden) sampleSearch("close"); });
    search.addEventListener("input", report);
    el("search-close").addEventListener("click", () => {
      search.blur(); dialog.hidden = true; report();
    });
    el("last-search-result").addEventListener("click", () => {
      activeDestination = "Search result"; selectionCount++;
      el("destination").textContent = "Synthetic destination: Search result";
      search.blur(); dialog.hidden = true; setSidebar(false); report();
    });
    for (const event of ["resize", "scroll"]) window.visualViewport?.addEventListener(event, report);
    window.addEventListener("resize", report);
    document.addEventListener("metis-native-layout", report);
    fetch("/api/mobile/session", { credentials: "same-origin" }).then(async response => {
      if (!response.ok || (await response.json()).username !== expectedUsername) throw new Error("Unexpected sidebar fixture session");
      verification = true; el("session-state").textContent = "Authenticated sidebar fixture session"; report();
    }).catch(error => { el("fixture-error").textContent = String(error.message || error); });
    setSidebar(false);
</script></body></html>`;
}

// Storage plumbing only. These values deliberately do not identify a model or
// imply provider capabilities; the production web UI validates its own catalog.
function webModelPreferenceFixture() {
  return `<!doctype html><html lang="en"><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>SYNTHETIC model preference storage probe</title>
    <style>body { font:17px system-ui; padding:20px; } button,a { display:block; min-height:44px; margin:12px 0; font:inherit; } p { overflow-wrap:anywhere; }</style>
    </head><body>
    <h1>SYNTHETIC model preference storage probe</h1>
    <p>Storage transport only; these example strings are not provider model IDs.</p>
    <button id="set-preferences">Store synthetic model preferences</button>
    <button id="remove-model">Remove synthetic model selection</button>
    <button id="clear-preferences">Clear synthetic local storage</button>
    <p id="preferences" role="status"></p>
    <a href="/">Return to authenticated web workspace fixture</a>
    <script>
      const keys = { model: "metis-ai_model", parameters: "metis-ai_model_params", unrelated: "metis-ai_fixture_draft" };
      const read = () => Object.fromEntries(Object.entries(keys).map(([name,key]) => [name,localStorage.getItem(key)]));
      const atScriptStart = read();
      const report = () => {
        document.getElementById("preferences").textContent = "Synthetic model preference storage: " + JSON.stringify({ atScriptStart, current:read() });
      };
      document.getElementById("set-preferences").addEventListener("click", () => {
        localStorage.setItem(keys.model, "SYNTHETIC selection example");
        localStorage.setItem(keys.parameters, JSON.stringify([{ id:"syntheticPreference", value:"example" }]));
        localStorage.setItem(keys.unrelated, "SYNTHETIC unsent draft must not persist");
        report();
      });
      document.getElementById("remove-model").addEventListener("click", () => { localStorage.removeItem(keys.model); report(); });
      document.getElementById("clear-preferences").addEventListener("click", () => { localStorage.clear(); report(); });
      report();
    </script></body></html>`;
}

// Production-like geometry, deliberately SYNTHETIC: this validates the app/web
// viewport boundary and sidebar bridge, never the production Metis design.
function webViewportFixture(username: string, contentEditableComposer = false, centeredEmptyState = false, productionEmptyState = false, tallComposer = false, largeEmptyComposer = false) {
  const expectedUsername = JSON.stringify(username).replaceAll("<", "\\u003c");
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>SYNTHETIC viewport fixture — not Metis design evidence</title>
  <style>
    :root { --background: #f5f3ed; --foreground: #22251f; --popover: #fffdf8; --muted: #e4e5de; }
    * { box-sizing: border-box; }
    html, body { margin: 0; height: 100%; overflow: hidden; color: var(--foreground); background: var(--background); font: 17px system-ui; }
    [hidden] { display: none !important; }
    button, textarea, a { font: inherit; }
    button, a { min-height: 44px; min-width: 44px; }
    button { border: 1px solid #74766c; border-radius: 12px; color: inherit; background: var(--popover); padding: 10px 12px; }
    a { display: block; padding: 10px 0; }
    #viewport { position: relative; display: flex; flex-direction: column; width: 100%; height: 100dvh; overflow: hidden; }
    header { flex: none; display: flex; flex-wrap: wrap; align-items: center; gap: 8px; padding: 8px 12px; border-bottom: 1px solid #cccfc3; background: var(--popover); }
    header strong { flex: 1; }
    #dismiss-keyboard { flex-basis: 100%; }
    #centered-empty-state { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); pointer-events: none; max-width: 80%; margin: 0; }
    #transcript { flex: 1; overflow: auto; min-height: 0; padding: 12px 16px 160px; overscroll-behavior: contain; }
    #transcript p { margin: 8px 0; }
    #viewport-metrics, #workspace-metrics, #page-instance { font-size: 11px; overflow-wrap: anywhere; }
    #focus-state { overflow-wrap: anywhere; }
    #composer-footer { position: absolute; inset: auto 0 0; padding: 12px 12px max(4px, env(safe-area-inset-bottom)); background: var(--background); }
    #composer { display: flex; align-items: end; gap: 8px; }
    #empty-chat-layout { position: relative; display: flex; flex: 1; min-height: 0; flex-direction: column; justify-content: center; padding-bottom: 10svh; }
    #empty-chat-layout > div { display: flex; flex: none; flex-direction: column; align-items: center; padding-inline: 16px; }
    #flow-empty-state { font-size: 28px; line-height: 1.2; margin: 0 0 20px; }
    #composer-footer.relative { position: relative; width: 100%; max-width: 672px; margin-inline: auto; }
    #composer-footer[class~="max-md:fixed"] { position: fixed; inset-inline: 0; bottom: 0; }
    body[data-empty-flow] #transcript { position: absolute; inset: 0; padding: 6px; overflow: auto; font-size: 8px; line-height: 10px; opacity: 0.2; pointer-events: none; z-index: 0; }
    body[data-empty-flow] #transcript button, body[data-empty-flow] #transcript a { display: none; }
    body[data-empty-flow] #empty-chat-layout { z-index: 1; }
    body[data-tall-composer] #draft, body[data-large-empty-composer] #draft { min-height: 132px; height: 132px; }
    body[data-tall-composer] #transcript { padding-bottom: 0; }
    body[data-tall-composer] #viewport-metrics, body[data-tall-composer] #keyboard-transition, body[data-tall-composer] #keyboard-dismissal, body[data-tall-composer] #focus-state { height: 32px; overflow: hidden; }
    /* Same class-level baseline as production; the app must prevent focus zoom. */
    .composer-input-area { font-size: 15px; }
    #draft { flex: 1; min-width: 0; height: 68px; margin: 0; padding: 12px; border: 1px solid #74766c; border-radius: 18px; color: inherit; background: var(--popover); resize: none; overflow: auto; }
    aside { position: fixed; z-index: 10; inset: 0 auto 0 0; display: flex; flex-direction: column; width: min(88vw, 360px); padding: 12px; background: var(--popover); border-right: 1px solid #74766c; }
    aside h2 { font-size: 20px; }
    #sidebar-footer { margin-top: auto; }
    #sidebar-footer button { width: 100%; text-align: left; }
    aside.workspace-surface { position: fixed; inset: 0; z-index: 20; width: 100%; border: 0; padding: 0; background: var(--background); }
    #workspace-content { flex: 1; min-height: 0; overflow: auto; padding: 12px; }
    #workspace-bottom-control { flex: none; width: 100%; }
    #safe-area-probe { position: fixed; visibility: hidden; pointer-events: none; padding-top: env(safe-area-inset-top); padding-bottom: env(safe-area-inset-bottom); }
    iframe { width: 100%; height: 220px; border: 1px solid #74766c; }
  </style>
</head>
<body>
  <div id="viewport" class="metis-shell">
    <header>
      <button id="open-sidebar" aria-label="Open sidebar" aria-expanded="false">Chats</button>
      <button id="open-workspace" aria-label="Open synthetic workspace panel">Workspace</button>
      <strong>SYNTHETIC viewport fixture</strong>
      <button id="measure-viewport">Measure viewport geometry</button>
      <button id="dismiss-keyboard">Dismiss keyboard, keep composer focus</button>
      <button id="blur-keyboard" aria-label="Blur composer and dismiss keyboard">Blur</button>
      <button id="arm-system-dismissal" aria-label="Arm native Done dismissal probe">Arm Done</button>
    </header>
    <main id="transcript" aria-label="Synthetic scrolling transcript">
      <h1>Synthetic viewport fixture</h1>
      <p>Integration geometry only. This is not the Metis web design.</p>
      <p id="session-state" role="status">Checking viewport fixture session…</p>
      <p id="focus-state" role="status">Composer is not focused</p>
      <p id="keyboard-transition" role="status">Synthetic keyboard transition not sampled</p>
      <p id="keyboard-dismissal" role="status">Synthetic keyboard dismissal not sampled</p>
      <p id="page-instance"></p>
      <p id="viewport-metrics" role="status"></p>
      <button id="check-session">Check viewport fixture session</button>
      <button id="show-subframe">Show same-origin subframe probe</button>
      <iframe id="subframe" title="Synthetic same-origin bridge probe" hidden></iframe>
      <p id="subframe-state" role="status"></p>
      <a href="/">Return to authenticated web workspace fixture</a>
      <button id="logout">Sign out from the viewport fixture</button>
      <p id="error" role="alert"></p>
      ${Array.from({ length: 12 }, (_, index) => `<p>Synthetic transcript row ${index + 1} — scroll content keeps the footer separate from the transcript.</p>`).join("")}
    </main>
    ${centeredEmptyState ? '<h2 id="centered-empty-state">Synthetic centered empty state</h2>' : ""}
    <footer id="composer-footer" class="pointer-events-none z-20 w-full">
      <form id="composer" aria-label="Synthetic web composer">
        ${contentEditableComposer
          ? '<div id="draft" class="composer-input-area" contenteditable="true" role="textbox" aria-multiline="true" aria-label="Synthetic viewport draft" tabindex="0"></div>'
          : '<textarea id="draft" class="composer-input-area" aria-label="Synthetic viewport draft" placeholder="Synthetic draft"></textarea>'}
        <button type="button" id="keep-draft">Keep draft</button>
      </form>
    </footer>
    <aside class="fixed inset-y-0 left-0" aria-label="Chats sidebar" hidden>
      <a href="/" aria-label="Metis">SYNTHETIC Metis brand</a>
      <button id="close-sidebar" aria-label="Close sidebar">Close chats</button>
      <h2>Synthetic chats</h2>
      <button id="measure-sidebar">Measure sidebar geometry</button>
      <p>App controls belong beside the web account entry.</p>
      <div id="sidebar-footer"><button aria-label="Open account menu">Fixture account</button></div>
    </aside>
    <aside id="synthetic-workspace" class="workspace-surface" aria-label="Synthetic workspace panel" hidden>
      <div id="workspace-content">
        <button id="close-workspace">Close synthetic workspace panel</button>
        <h2>SYNTHETIC right workspace geometry</h2>
        <p>Inset probe only; this panel does not implement a terminal or browser.</p>
        <button id="measure-workspace">Measure workspace geometry</button>
        <p id="workspace-metrics" role="status"></p>
      </div>
      <button id="workspace-bottom-control" type="button">Synthetic workspace bottom control</button>
    </aside>
  </div>
  <div id="safe-area-probe" aria-hidden="true"></div>
  <script>
    const expectedUsername = ${expectedUsername};
    const element = id => document.getElementById(id);
    const draft = element("draft");
    const sidebar = document.querySelector('aside[aria-label="Chats sidebar"]');
    const workspace = element("synthetic-workspace");
    const productionEmptyState = ${productionEmptyState};
    if (${largeEmptyComposer}) document.body.dataset.largeEmptyComposer = "true";
    if (productionEmptyState) {
      document.body.dataset.emptyFlow = "true";
      const layout = document.createElement("div");
      layout.id = "empty-chat-layout";
      layout.className = "relative flex min-h-0 flex-1 flex-col justify-center pb-[10svh] sm:pb-8";
      const group = document.createElement("div");
      group.className = "flex shrink-0 flex-col items-center px-4";
      const greeting = document.createElement("h2");
      greeting.id = "flow-empty-state";
      greeting.textContent = "Synthetic empty chat greeting";
      group.append(greeting);
      const dock = element("composer-footer");
      dock.classList.add("relative", "mx-auto", "max-w-2xl", "px-4");
      layout.append(group, dock);
      element("transcript").before(layout);
    }
    const emptyRect = () => (element("flow-empty-state") || element("centered-empty-state"))?.getBoundingClientRect();
    function greetingComposerGeometry() {
      const greeting = emptyRect();
      const composer = element("composer").getBoundingClientRect();
      return { greetingBottom: greeting?.bottom ?? null, composerTop: composer.top,
        greetingComposerGap: greeting ? composer.top - greeting.bottom : null };
    }
    const tallComposer = ${tallComposer};
    const anchorRect = () => element("transcript-anchor")?.getBoundingClientRect();
    let tallDockObserver;
    if (tallComposer) {
      document.body.dataset.tallComposer = "true";
      const transcript = element("transcript");
      const inner = document.createElement("div");
      inner.id = "transcript-inner";
      while (transcript.firstChild) inner.append(transcript.firstChild);
      const anchor = document.createElement("p");
      anchor.id = "transcript-anchor";
      anchor.textContent = "Synthetic transcript anchor row";
      inner.append(anchor);
      transcript.append(inner);
      // Mirror the real app-shell composer measurement and its sticky-bottom
      // transcript padding, including the tall-composer threshold.
      tallDockObserver = new ResizeObserver(() => {
        const stuckToBottom = transcript.scrollHeight - transcript.clientHeight - transcript.scrollTop <= 8;
        const height = Math.ceil(element("composer-footer").getBoundingClientRect().height);
        inner.style.paddingBottom = Math.max(172, height + 40) + "px";
        if (stuckToBottom) transcript.scrollTop = transcript.scrollHeight;
        scheduleMetrics();
      });
      tallDockObserver.observe(element("composer-footer"));
      transcript.addEventListener("scroll", scheduleMetrics);
    }
    let revision = 0;
    let measurementRevision = 0;
    let draftHasBeenFocused = false;
    let retainedFocusRequested = false;
    let retainedFocusVerified = false;
    let systemDismissalArmed = false;
    const fail = error => { element("error").textContent = String(error.message || error); };
    element("page-instance").textContent = "Synthetic page instance: " + crypto.randomUUID();
    async function verifySession() {
      const response = await fetch("/api/mobile/session", { credentials: "same-origin" });
      if (!response.ok) throw new Error("Viewport session request failed: " + response.status);
      const account = await response.json();
      if (account.username !== expectedUsername) throw new Error("Unexpected viewport session owner");
      element("session-state").textContent = "Authenticated viewport fixture session";
    }
    function updateMetrics() {
      const focused = document.activeElement === draft;
      element("focus-state").textContent = focused && retainedFocusRequested && retainedFocusVerified
        ? "Composer retains focus after keyboard dismissal"
        : (focused && !retainedFocusRequested ? "Composer retains focus"
          : "Composer focus probe: " + JSON.stringify({
            activeElement: document.activeElement?.tagName, activeID: document.activeElement?.id,
            readonly: draft.readOnly, retainedFocusRequested, retainedFocusVerified, focused,
          }));
      const report = "Synthetic viewport metrics: " + JSON.stringify({
        revision: ++revision, measurementRevision,
        width: innerWidth, height: innerHeight,
        safeAreaBottom: parseFloat(getComputedStyle(element("safe-area-probe")).paddingBottom) || 0,
        safeAreaTop: parseFloat(getComputedStyle(element("safe-area-probe")).paddingTop) || 0,
        shellHeight: element("viewport").getBoundingClientRect().height,
        headerTop: document.querySelector("header").getBoundingClientRect().top,
        sidebarTop: sidebar.getBoundingClientRect().top,
        sidebarHeight: sidebar.getBoundingClientRect().height,
        sidebarBrandTop: sidebar.querySelector('[aria-label="Metis"]').getBoundingClientRect().top,
        sidebarCloseTop: element("close-sidebar").getBoundingClientRect().top,
        composerDockBottom: parseFloat(getComputedStyle(element("composer-footer")).bottom) || 0,
        composerPosition: getComputedStyle(element("composer-footer")).position,
        composerServerFixed: element("composer-footer").classList.contains("max-md:fixed"),
        productionEmptyState,
        tallComposer,
        composerDockHeight: element("composer-footer").getBoundingClientRect().height,
        transcriptPaddingBottom: element("transcript-inner") ? parseFloat(getComputedStyle(element("transcript-inner")).paddingBottom) : null,
        transcriptBottomDistance: Math.max(0, element("transcript").scrollHeight - element("transcript").clientHeight - element("transcript").scrollTop),
        transcriptAnchorTop: anchorRect()?.top ?? null,
        emptyCenterY: emptyRect() ? (emptyRect().top + emptyRect().bottom) / 2 : null,
        ...greetingComposerGeometry(),
        composerBottom: draft.getBoundingClientRect().bottom,
        composerCenterX: (element("composer").getBoundingClientRect().left + element("composer").getBoundingClientRect().right) / 2,
        composerFontSize: parseFloat(getComputedStyle(draft).fontSize),
        composerContentEditable: draft.isContentEditable,
        viewportScale: window.visualViewport?.scale,
        viewportOffsetLeft: window.visualViewport?.offsetLeft,
        focused, readonly: draft.readOnly,
        workspaceOpen: !workspace.hidden,
        workspacePaddingBottom: parseFloat(getComputedStyle(workspace).paddingBottom) || 0,
        workspaceControlBottom: element("workspace-bottom-control").getBoundingClientRect().bottom,
        presentation: {
          stylePresent: Boolean(document.getElementById("metis-native-app-style")),
          nativeApp: document.documentElement.dataset.metisNativeApp || null,
          handlerPresent: Boolean(window.webkit?.messageHandlers?.metisAppControls),
          controlsCount: document.querySelectorAll("[data-metis-app-controls]").length,
        },
      });
      element("viewport-metrics").textContent = report;
      element("workspace-metrics").textContent = report;
    }
    function scheduleMetrics() { requestAnimationFrame(updateMetrics); }
    // Record the transition from the trusted touch before focus starts. This
    // measures DOM geometry every frame rather than only its settled endpoint.
    let transitionRevision = 0;
    let dismissalRevision = 0;
    let dismissalOffsetRevision = 0;
    let dockOffsetAttempts = 0;
    draft.addEventListener("pointerdown", () => {
      if (draft.readOnly) {
        draft.readOnly = false;
        draft.blur();
        draft.focus({ preventScroll: true });
      }
      retainedFocusRequested = false;
      retainedFocusVerified = false;
      const revision = ++transitionRevision;
      const started = performance.now();
      const samples = [];
      function sample(now) {
        if (revision !== transitionRevision) return;
        const header = document.querySelector("header").getBoundingClientRect();
        samples.push({
          headerTop: header.top, headerBottom: header.bottom,
          transcriptScrollTop: element("transcript").scrollTop, documentScrollY: scrollY,
          shellHeightDelta: element("viewport").getBoundingClientRect().height -
            (parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--metis-app-window-height")) || innerHeight),
          emptyCenterY: emptyRect() ? (emptyRect().top + emptyRect().bottom) / 2 : null,
          transcriptAnchorTop: anchorRect()?.top ?? null,
          dockHeight: element("composer-footer").getBoundingClientRect().height,
          ...greetingComposerGeometry(),
        });
        if (now - started < 700 || samples.length < 12) { requestAnimationFrame(sample); return; }
        const range = key => Math.max(...samples.map(item => item[key])) - Math.min(...samples.map(item => item[key]));
        element("keyboard-transition").textContent = "Synthetic keyboard transition: " + JSON.stringify({
          revision, frames:samples.length, duration:now-started,
          headerTopRange:range("headerTop"), headerBottomRange:range("headerBottom"),
          transcriptScrollRange:range("transcriptScrollTop"), documentScrollRange:range("documentScrollY"),
          maxShellHeightError:Math.max(...samples.map(item=>Math.abs(item.shellHeightDelta))),
          dockOffsetAttempts,
          emptyCenterYRange: emptyRect() ? range("emptyCenterY") : null,
          minGreetingComposerGap: emptyRect() ? Math.min(...samples.map(item => item.greetingComposerGap)) : null,
          greetingComposerGapRange: emptyRect() ? range("greetingComposerGap") : null,
          maxGreetingComposerShiftError: emptyRect() ? Math.max(...samples.map(item => Math.abs(
            (item.composerTop - samples[0].composerTop) - (item.greetingBottom - samples[0].greetingBottom)))) : null,
          transcriptAnchorTopRange: anchorRect() ? range("transcriptAnchorTop") : null,
          dockHeightRange: range("dockHeight"),
        });
        updateMetrics();
      }
      sample(started);
    });
    draft.addEventListener("focus", () => {
      draftHasBeenFocused = true;
      if (productionEmptyState) element("composer-footer").classList.add("max-md:fixed", "max-md:inset-x-0", "max-md:z-30");
      // Mirror the real web dock's transient keyboard-offset writes. The app's
      // first-party override must prevent this second subtraction of the IME.
      dockOffsetAttempts = 0;
      function writeTransientOffset() {
        if (document.activeElement !== draft || dockOffsetAttempts >= 18) return;
        element("composer-footer").style.bottom = "120px";
        dockOffsetAttempts++;
        requestAnimationFrame(writeTransientOffset);
      }
      writeTransientOffset();
    });
    draft.addEventListener("blur", () => {
      if (systemDismissalArmed) {
        systemDismissalArmed = false;
        sampleKeyboardDismissal("system-done");
      }
      element("composer-footer").style.bottom = "0px";
      if (productionEmptyState) element("composer-footer").classList.remove("max-md:fixed", "max-md:inset-x-0", "max-md:z-30");
    });
    for (const event of ["focus", "blur", "input"]) draft.addEventListener(event, scheduleMetrics);
    window.addEventListener("resize", scheduleMetrics);
    window.visualViewport?.addEventListener("resize", scheduleMetrics);
    window.visualViewport?.addEventListener("scroll", scheduleMetrics);
    function measureGeometry() {
      // A fresh trusted action samples CSS after WebKit applies its native safe
      // area, which can change without a window resize during initial display.
      if (workspace.hidden && draftHasBeenFocused) draft.focus({ preventScroll: true });
      requestAnimationFrame(() => requestAnimationFrame(() => {
        measurementRevision++;
        updateMetrics();
      }));
    }
    element("measure-viewport").addEventListener("mousedown", event => event.preventDefault());
    element("measure-viewport").addEventListener("click", measureGeometry);
    element("measure-workspace").addEventListener("click", measureGeometry);
    element("measure-sidebar").addEventListener("click", measureGeometry);
    function sampleKeyboardDismissal(kind) {
      const revision = ++dismissalRevision;
      const offsetRevision = ++dismissalOffsetRevision;
      const started = performance.now();
      const samples = [];
      let writes = 0;
      // Mirror late visualViewport writes after focus has already left the field.
      // Sampling only focus or a settled endpoint misses this production path.
      function writeClosingOffset() {
        if (offsetRevision !== dismissalOffsetRevision) return;
        element("composer-footer").style.bottom = (120 * Math.max(0, 1 - writes / 18)) + "px";
        writes++;
        if (writes <= 18) requestAnimationFrame(writeClosingOffset);
      }
      function sample(now) {
        if (revision !== dismissalRevision) return;
        const header = document.querySelector("header").getBoundingClientRect();
        const empty = emptyRect();
        const composer = element("composer").getBoundingClientRect();
        samples.push({
          headerTop: header.top, headerBottom: header.bottom,
          transcriptScrollTop: element("transcript").scrollTop, documentScrollY: scrollY,
          composerCenterX: (composer.left + composer.right) / 2,
          dockBottom: parseFloat(getComputedStyle(element("composer-footer")).bottom) || 0,
          viewportScale: window.visualViewport?.scale || 1,
          emptyCenterY: empty ? (empty.top + empty.bottom) / 2 : null,
          transcriptAnchorTop: anchorRect()?.top ?? null,
          dockHeight: element("composer-footer").getBoundingClientRect().height,
          ...greetingComposerGeometry(),
        });
        if (now - started < 900 || samples.length < 18) { requestAnimationFrame(sample); return; }
        const range = key => Math.max(...samples.map(item => item[key])) - Math.min(...samples.map(item => item[key]));
        element("keyboard-dismissal").textContent = "Synthetic keyboard dismissal: " + JSON.stringify({
          revision, kind, frames: samples.length, duration: now - started, offsetWrites: writes,
          headerTopRange: range("headerTop"), headerBottomRange: range("headerBottom"),
          transcriptScrollRange: range("transcriptScrollTop"), documentScrollRange: range("documentScrollY"),
          composerCenterXRange: range("composerCenterX"),
          maxDockBottom: Math.max(...samples.map(item => Math.abs(item.dockBottom))),
          viewportScaleRange: range("viewportScale"),
          emptyCenterYRange: empty ? range("emptyCenterY") : null,
          minGreetingComposerGap: empty ? Math.min(...samples.map(item => item.greetingComposerGap)) : null,
          greetingComposerGapRange: empty ? range("greetingComposerGap") : null,
          maxGreetingComposerShiftError: empty ? Math.max(...samples.map(item => Math.abs(
            (item.composerTop - samples[0].composerTop) - (item.greetingBottom - samples[0].greetingBottom)))) : null,
          transcriptAnchorTopRange: anchorRect() ? range("transcriptAnchorTop") : null,
          dockHeightRange: range("dockHeight"),
        });
        updateMetrics();
      }
      sample(started);
      requestAnimationFrame(writeClosingOffset);
    }
    for (const [id,kind] of [["dismiss-keyboard","retained-focus"],["blur-keyboard","blur"]]) {
      element(id).addEventListener("pointerdown", () => sampleKeyboardDismissal(kind));
    }
    // The web action only arms sampling. The real native Done button must
    // blur the draft before the system-dismissal probe can start.
    element("arm-system-dismissal").addEventListener("mousedown", event => event.preventDefault());
    element("arm-system-dismissal").addEventListener("click", () => { systemDismissalArmed = true; });
    element("blur-keyboard").addEventListener("mousedown", event => event.preventDefault());
    element("blur-keyboard").addEventListener("click", () => { draft.blur(); scheduleMetrics(); });
    element("dismiss-keyboard").addEventListener("mousedown", event => event.preventDefault());
    element("dismiss-keyboard").addEventListener("click", () => {
      // Explicitly focus the real readonly textarea after the trusted action.
      // WebKit may blur a field while dismissing its software keyboard, so the
      // final marker requires a delayed activeElement measurement.
      retainedFocusRequested = true;
      retainedFocusVerified = false;
      draft.readOnly = true;
      draft.focus({ preventScroll: true });
      scheduleMetrics();
      setTimeout(() => {
        draft.focus({ preventScroll: true });
        setTimeout(() => { retainedFocusVerified = true; updateMetrics(); }, 200);
      }, 300);
    });
    function setSidebar(open) {
      sidebar.hidden = !open;
      element("open-sidebar").setAttribute("aria-expanded", String(open));
    }
    element("open-sidebar").addEventListener("click", () => { setSidebar(true); scheduleMetrics(); });
    element("open-workspace").addEventListener("click", () => { workspace.hidden = false; scheduleMetrics(); });
    element("close-workspace").addEventListener("click", () => { workspace.hidden = true; scheduleMetrics(); });
    element("close-sidebar").addEventListener("click", () => { setSidebar(false); scheduleMetrics(); });
    element("check-session").addEventListener("click", () => verifySession().catch(fail));
    element("show-subframe").addEventListener("click", () => {
      element("subframe").hidden = false;
      element("subframe").src = "/?fixture=app-controls-subframe";
    });
    window.addEventListener("message", event => {
      if (event.origin === location.origin && event.source === element("subframe").contentWindow
          && event.data === "synthetic-subframe-menu-posted") {
        element("subframe-state").textContent = "Same-origin subframe sent menu";
      }
    });
    element("logout").addEventListener("click", async () => {
      try {
        const response = await fetch("/api/auth", { method: "DELETE", credentials: "same-origin" });
        if (!response.ok) throw new Error("Viewport sign-out failed: " + response.status);
        location.reload();
      } catch (error) { fail(error); }
    });
    element("composer").addEventListener("submit", event => event.preventDefault());
    verifySession().catch(fail);
    updateMetrics();
  </script>
</body>
</html>`;
}

function webAppControlsSubframeFixture() {
  return `<!doctype html><html lang="en"><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>SYNTHETIC same-origin subframe probe</title>
    <style>body { font: 15px system-ui; margin: 8px; } button { min-height: 44px; font: inherit; }</style>
    </head><body>
    <button id="request-menu">Request iPhone controls from same-origin subframe</button>
    <button id="request-preferences">Post model preferences from same-origin subframe</button>
    <p id="state" role="status"></p>
    <script>
      document.getElementById("request-preferences").addEventListener("click", () => {
        const handler = window.webkit?.messageHandlers?.metisModelPreferences;
        if (!handler) { document.getElementById("state").textContent = "Model preference bridge unavailable"; return; }
        handler.postMessage({ "metis-ai_model":"SYNTHETIC forbidden subframe selection", "metis-ai_model_params":"[]" });
        document.getElementById("state").textContent = "Same-origin subframe posted model preferences";
      });
      document.getElementById("request-menu").addEventListener("click", () => {
        const handler = window.webkit?.messageHandlers?.metisAppControls;
        if (!handler) { document.getElementById("state").textContent = "Native bridge unavailable in subframe"; return; }
        handler.postMessage("menu");
        parent.postMessage("synthetic-subframe-menu-posted", location.origin);
      });
    </script>
    </body></html>`;
}

async function main() {
  const root = mkdtempSync(path.join(tmpdir(), "metis-apple-fixture-"));
  const workspace = path.join(root, "model-workspace");
  const defaultWorkspace = path.join(root, "unmapped-workspace");
  for (const folder of [workspace, defaultWorkspace]) mkdirSync(folder, { mode: 0o700 });
  process.on("exit", () => rmSync(root, { recursive: true, force: true }));
  const port = Number(process.argv[2] ?? 43100);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error("Invalid fixture port");
  Object.assign(process.env, {
    AI_CHAT_ROOT: root, AI_CHAT_INSTALL_DIR: process.cwd(), CHAT_DATA_DIR: root,
    CHAT_DB_PATH: path.join(root, "chat.sqlite"), AI_CHAT_MCP_STATE_DIR: path.join(root, "mcp-state"),
    AGENT_CWD: defaultWorkspace, MCP_ENABLE_OPTIONAL_SERVERS: "false", MCP_ENABLE_REMOTE_SERVERS: "false",
    CHAT_LEGACY_HEADER_AUTH: "false", METIS_AI_BOOTSTRAP_PASSWORD: "",
    METIS_AI_ADMIN_USERNAMES: "", AI_CHAT_TRUSTED_PROXIES: "", AI_CHAT_ALLOW_ROOT_AGENTS: "false",
    AI_CHAT_PUBLIC_URL: `http://localhost:${port}`, AI_CHAT_INTERNAL_ORIGIN: `http://127.0.0.1:${port}`,
    MCP_PUBLIC_URL: `http://127.0.0.1:${port}`, MCP_BEARER_TOKEN: "",
    AI_CHAT_INTERNAL_MCP_SERVER: path.resolve("lib/internal-mcp-server.mjs"),
  });
  const { createUser, getAuthenticatedCookieUser, CHAT_COOKIE } = await import("../../../lib/auth");
  const { createChat, appendMessage } = await import("../../../lib/db-store");
  const { getDatabase } = await import("../../../lib/sqlite");
  const auth = await import("../../../app/api/auth/route");
  const chats = await import("../../../app/api/chats/route");
  const chat = await import("../../../app/api/chats/[id]/route");
  const submit = await import("../../../app/api/chat/route");
  const cancel = await import("../../../app/api/chat/cancel/route");
  const events = await import("../../../app/api/chats/events/route");
  const fileUploads = await import("../../../app/api/file-uploads/route");
  const fileUpload = await import("../../../app/api/file-uploads/[id]/route");
  const storedUpload = await import("../../../app/api/uploads/[chatId]/[name]/route");
  const models = await import("../../../app/api/models/route");
  const notifications = await import("../../../app/api/notifications/inbox/route");
  const projects = await import("../../../app/api/projects/route");
  const mobileDevices = await import("../../../app/api/mobile/devices/route");
  const mobileSession = await import("../../../app/api/mobile/session/route");
  const profile = await import("../../../app/api/profile/route");
  const mobileCapabilities = await import("../../../app/api/mobile/capabilities/route");
  const { upsertProviderConnection } = await import("../../../lib/provider-connections");
  const { claimNextJob } = await import("../../../lib/db-jobs");
  const { runJobById } = await import("../../../lib/worker-runner");
  const { ensureUserAccess } = await import("../../../lib/user-access");
  const { ensureAllModelAccess } = await import("../../../lib/model-access");
  const runs = await import("../../../app/api/runs/route");

  const alice = createUser("metis-apple-fixture-alice", "apple-fixture-only");
  const bob = createUser("metis-apple-fixture-bob", "apple-fixture-only");
  const db = getDatabase();
  db.prepare("UPDATE users SET is_admin=1 WHERE id=?").run(alice.id);
  ensureUserAccess(alice.id, workspace, userInfo().username);
  ensureAllModelAccess(alice.id);
  upsertProviderConnection(alice.id, {
    providerKey: "compatible", slug: "fixture", label: "Fixture model", authType: "local",
    baseUrl: `http://127.0.0.1:${port}/fixture-provider`, config: { modelIds: ["metis-fixture"] },
  });
  const thread = createChat("Fixture chat", undefined, alice.id);
  createChat("Other user's chat", undefined, bob.id);
  for (let index = 1; index <= 75; index++) {
    appendMessage(thread.id, { role: index % 2 ? "user" : "assistant", content: `Nachricht ${index} 🌱` }, alice.id);
  }
  const now = new Date().toISOString();
  const job = { id: "fixture-run", chatId: thread.id, userId: alice.id, status: "completed" };
  db.prepare("INSERT INTO jobs (id, chat_id, user_id, data, status, updated_at) VALUES (?, ?, ?, ?, ?, ?)")
    .run(job.id, thread.id, alice.id, JSON.stringify(job), job.status, now);
  const insertEvent = db.prepare("INSERT INTO run_events (job_id, chat_id, user_id, event, data, created_at) VALUES (?, ?, ?, ?, ?, ?)");
  insertEvent.run(job.id, thread.id, alice.id, "text", JSON.stringify({ text: "Grüße 🌱" }), now);
  insertEvent.run(job.id, thread.id, alice.id, "text", JSON.stringify({ text: " from Metis" }), now);

  const droppedReplies = new Set<string>();
  let delayedHistory: { chatId: string; jobId: string } | undefined;
  let offline = false;
  let mobileProfileUnavailable = false;
  let fallbackProfileReads = 0;
  let unknownCapabilitiesVersion = false;
  // This gate belongs only to the disposable loopback fixture. The UI test
  // releases it explicitly after observing startup, rather than racing a timer.
  let holdSessionVerification = false;
  const heldSessionVerifications = new Set<() => void>();
  const server = createServer(async (incoming, outgoing) => {
    const abort = new AbortController();
    outgoing.once("close", () => abort.abort());
    try {
      const url = new URL(incoming.url ?? "/", `http://localhost:${port}`);
      const method = incoming.method;
      if (url.pathname === "/fixture-control" && method === "GET") {
        outgoing.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
        outgoing.end(JSON.stringify({ holdSessionVerification, heldSessionRequests: heldSessionVerifications.size, fallbackProfileReads }));
        return;
      }
      if (url.pathname === "/fixture-control" && method === "POST") {
        const state = url.searchParams.get("state");
        if (state === "offline" || state === "online") offline = state === "offline";
        else if (state === "profile-fallback" || state === "profile-mobile") {
          mobileProfileUnavailable = state === "profile-fallback";
          fallbackProfileReads = 0;
        }
        else if (state === "capabilities-unknown" || state === "capabilities-current") unknownCapabilitiesVersion = state === "capabilities-unknown";
        else if (state === "hold-session") holdSessionVerification = true;
        else if (state === "release-session") {
          holdSessionVerification = false;
          for (const release of [...heldSessionVerifications]) release();
        }
        else if (state === "external-message") {
          appendMessage(thread.id, { role: "assistant", content: "Message sent from another client 🌱" }, alice.id);
        }
        else if (state === "revoke") {
          db.prepare("DELETE FROM sessions WHERE user_id=?").run(alice.id);
          createChat("Fixture post-revocation signal", undefined, alice.id);
        }
        else { outgoing.writeHead(400).end(); return; }
        console.warn(`Fixture session test control: ${state}`);
        outgoing.writeHead(204).end();
        return;
      }
      if (offline) { outgoing.destroy(); return; }
      // Native restore validates the saved cookie with GET /api/chats. Hold
      // before dispatching the real handler so revocation is still authoritative.
      if (holdSessionVerification && url.pathname === "/api/chats" && method === "GET") {
        await new Promise<void>(resolve => {
          const release = () => {
            heldSessionVerifications.delete(release);
            abort.signal.removeEventListener("abort", release);
            resolve();
          };
          heldSessionVerifications.add(release);
          abort.signal.addEventListener("abort", release, { once: true });
        });
        if (abort.signal.aborted) return;
      }
      if (url.pathname === "/fixture-provider/models" && method === "GET") {
        outgoing.writeHead(200, { "content-type": "application/json" });
        outgoing.end(JSON.stringify({ object: "list", data: [{ id: "metis-fixture", object: "model" }] }));
        return;
      }
      const body = method && ["POST", "PUT", "DELETE", "PATCH"].includes(method)
        ? await Array.fromAsync(incoming) : undefined;
      const request = new Request(url, {
        method,
        headers: new Headers(incoming.headers as Record<string, string>),
        body: body ? Buffer.concat(body) : undefined,
        signal: abort.signal,
      });
      if (url.pathname === "/fixture-provider/chat/completions" && method === "POST") {
        outgoing.writeHead(200, { "content-type": "text/event-stream" });
        const chunk = (delta: object, finish: string | null) =>
          `data: ${JSON.stringify({ id: "fixture-completion", object: "chat.completion.chunk", created: 1,
            model: "metis-fixture", choices: [{ index: 0, delta, finish_reason: finish }] })}\n\n`;
        // Leave enough visible text for the adapter's raw tool-marker lookahead.
        outgoing.write(chunk({ role: "assistant", content: "Live fixture streamed before the run completed. " }, null));
        await new Promise(resolve => setTimeout(resolve, 8_000));
        outgoing.write(chunk({ content: "Final response 🌱" }, null));
        outgoing.end(chunk({}, "stop") + "data: [DONE]\n\n");
        return;
      }
      const match = /^\/api\/chats\/([^/]+)$/.exec(url.pathname);
      const upload = /^\/api\/file-uploads\/([^/]+)$/.exec(url.pathname);
      const download = /^\/api\/uploads\/([^/]+)\/([^/]+)$/.exec(url.pathname);
      let response: Response;
      // This deliberately small synthetic HTML page tests the native WebKit/session
      // boundary. It is not the Metis web UI and is not design/screenshot evidence.
      if (url.pathname === "/" && method === "GET") {
        const account = getAuthenticatedCookieUser(request);
        const externalAddress = url.origin.replace("localhost", "127.0.0.1") + "/fixture-external";
        const fixture = url.searchParams.get("fixture");
        const html = account && (fixture === "viewport" || fixture === "composer-zoom" || fixture === "viewport-empty" || fixture === "viewport-empty-flow" || fixture === "viewport-tall" || fixture === "viewport-empty-large"
          ? webViewportFixture(account.username, fixture === "composer-zoom", fixture === "viewport-empty", fixture === "viewport-empty-flow" || fixture === "viewport-empty-large", fixture === "viewport-tall", fixture === "viewport-empty-large")
          : fixture === "toasts" ? await webToastFixture()
          : fixture === "sidebar" ? webSidebarFixture(account.username)
          : fixture === "model-preferences" ? webModelPreferenceFixture()
          : fixture === "app-controls-subframe" ? webAppControlsSubframeFixture()
          : webWorkspaceFixture(account.username, CHAT_COOKIE, externalAddress));
        response = account ? new Response(html, {
          headers: { "content-type": "text/html; charset=utf-8", "cache-control": "private, no-store" },
        }) : new Response("The synthetic web fixture requires an authenticated cookie.", {
          status: 401, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
        });
      }
      else if (url.pathname === "/fixture-web/download" && method === "GET") {
        response = getAuthenticatedCookieUser(request) ? new Response("Metis public WebKit download fixture.\n", {
          headers: {
            "content-type": "text/plain; charset=utf-8",
            "content-disposition": 'attachment; filename="metis-web-fixture.txt"',
            "cache-control": "private, no-store",
          },
        }) : new Response(null, { status: 401 });
      }
      else if (url.pathname === "/fixture-external" && method === "GET") {
        const receivedMetisCookie = request.headers.get("cookie")?.split(";")
          .some(part => part.trim().startsWith(CHAT_COOKIE + "="));
        // Do not echo any cookie values. The positive marker requires that the
        // authenticated WebKit cookie has not crossed into the external browser.
        const message = receivedMetisCookie ? "External fixture received a Metis cookie"
          : "External fixture opened without a Metis cookie";
        response = new Response(`<!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>External browser fixture</title></head><body><h1>${message}</h1></body></html>`, {
          status: receivedMetisCookie ? 403 : 200,
          headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
        });
      }
      else if (url.pathname === "/api/auth" && method === "POST") {
        const credentials = await request.clone().json().catch(() => null);
        if (credentials?.username === "metis-apple-fixture-redirect") {
          response = new Response(null, { status: 307, headers: { Location: "/fixture-redirect-target" } });
        } else {
          response = await auth.POST(request);
        }
      }
      else if (url.pathname === "/api/auth" && method === "DELETE") response = await auth.DELETE(request);
      else if (url.pathname === "/api/chats" && method === "GET") response = await chats.GET(request);
      else if (url.pathname === "/api/chats" && method === "POST") response = await chats.POST(request);
      else if (url.pathname === "/api/chats/events" && method === "GET") response = await events.GET(request);
      else if (url.pathname === "/api/chat" && method === "POST") {
        const submission = await request.clone().json().catch(() => null);
        response = await submit.POST(request);
        const accepted = response.status === 202 ? await response.clone().json() : null;
        if (accepted && typeof accepted.jobId === "string") {
          const entry = db.prepare("SELECT json_extract(data,'$.modelId') AS modelId FROM jobs WHERE id=?")
            .get(accepted.jobId);
          if (typeof entry?.modelId === "string" && entry.modelId.endsWith(":metis-fixture")) {
            const job = claimNextJob();
            if (job && job.id === accepted.jobId) void runJobById(job.id).catch(error => console.error(error));
          }
          if (submission?.message === "Hello from the iPhone simulator" && !droppedReplies.has(accepted.jobId)) {
            droppedReplies.add(accepted.jobId);
            delayedHistory = { chatId: submission.chatId, jobId: accepted.jobId };
            console.warn("Fixture dropped the first reply after committing the chat job");
            outgoing.writeHead(202, { "content-type": "application/json", "content-length": "512" });
            outgoing.write("{", () => outgoing.destroy());
            return;
          }
        }
      }
      else if (url.pathname === "/api/models" && method === "GET") response = await models.GET(request);
      else if (url.pathname === "/api/notifications/inbox" && method === "GET") response = await notifications.GET(request);
      else if (url.pathname === "/api/projects" && method === "GET") response = await projects.GET(request);
      else if (url.pathname === "/api/profile" && method === "GET") {
        if (mobileProfileUnavailable) fallbackProfileReads++;
        response = await profile.GET(request);
      }
      else if (url.pathname === "/api/mobile/capabilities" && method === "GET") {
        response = await mobileCapabilities.GET(request);
        if (response.ok && unknownCapabilitiesVersion) response = Response.json({ version: 999, apns: true });
      }
      else if (url.pathname === "/api/mobile/devices" && method === "GET") response = await mobileDevices.GET(request);
      else if (url.pathname === "/api/mobile/session" && (method === "GET" || method === "POST" || method === "DELETE")) {
        response = method === "GET" && mobileProfileUnavailable
          ? new Response(null, { status: 404 }) : await mobileSession[method](request);
      }
      else if (url.pathname === "/api/chat/cancel" && method === "POST") response = await cancel.POST(request);
      else if (url.pathname === "/api/file-uploads" && method === "POST") response = await fileUploads.POST(request);
      else if (upload && (method === "PUT" || method === "POST" || method === "DELETE")) {
        response = await fileUpload[method](request, { params: Promise.resolve({ id: decodeURIComponent(upload[1]) }) });
      }
      else if (download && method === "GET") response = await storedUpload.GET(request, {
        params: Promise.resolve({ chatId: decodeURIComponent(download[1]), name: decodeURIComponent(download[2]) }),
      });
      else if (match && method === "GET") {
        const id = decodeURIComponent(match[1]);
        response = await chat.GET(request, { params: Promise.resolve({ id }) });
        if (response.ok && delayedHistory?.chatId === id &&
            db.prepare("SELECT status FROM jobs WHERE id=?").get(delayedHistory.jobId)?.status === "completed") {
          delayedHistory = undefined;
          console.warn("Fixture delayed the saved transcript after the streamed reply");
          await new Promise(resolve => setTimeout(resolve, 4_000));
        }
      }
      else if (url.pathname === "/api/runs" && method === "GET") response = await runs.GET(request);
      else response = new Response(null, { status: 404 });
      if (process.env.METIS_FIXTURE_LOG_REQUESTS === "1" || response.status >= 500) {
        const cursor = match && method === "GET"
          ? " messageBefore=" + (url.searchParams.has("messageBefore") ? Number(url.searchParams.get("messageBefore")) : "latest")
          : "";
        console.warn(`Fixture ${method} ${url.pathname}${cursor} returned ${response.status}`);
        if (url.pathname === "/api/runs" && url.searchParams.get("stream") === "1") {
          console.warn(`Fixture run stream after cursor ${Number(url.searchParams.get("after"))}`);
        }
        if (url.pathname === "/api/models" && response.ok) {
          const catalog = await response.clone().json();
          console.warn(`Fixture catalog: ${catalog.models.length} model(s), default configured: ${Boolean(catalog.defaultModelId)}`);
        }
      }
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      if (response.body) await pipeline(Readable.fromWeb(response.body as import("node:stream/web").ReadableStream), outgoing);
      else outgoing.end();
    } catch (error) {
      if (abort.signal.aborted) return;
      console.error(error);
      if (!outgoing.headersSent) outgoing.writeHead(500);
      outgoing.end();
    }
  });
  server.listen(port, "127.0.0.1");
  await once(server, "listening");
  console.log(`Metis fixture listening on http://localhost:${port}`);
  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.once(signal, () => server.close(() => process.exit(0)));
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
