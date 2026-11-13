import assert from "node:assert/strict";
import test from "node:test";
import { createServer } from "node:net";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { callHostUpdater, type HostUpdateRequest } from "../lib/installer-update-host";
import { runInstallerUpdate } from "../lib/installer-update";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const jobId = "96444ef8-4f93-48bc-9400-8886d08f13a1";

async function withSocket(respond: (request: HostUpdateRequest) => unknown, run: (socket: string, directory: string) => Promise<void>) {
  const directory = await mkdtemp(path.join(os.tmpdir(), "metis-upd-"));
  const socket = path.join(directory, "s");
  const server = createServer(connection => {
    connection.setEncoding("utf8");
    let request = "";
    connection.on("data", value => {
      request += value;
      if (!request.includes("\n")) return;
      const result = respond(JSON.parse(request.split("\n")[0]));
      void Promise.resolve(result).then(response => connection.end(JSON.stringify(response) + "\n"));
    });
  });
  try {
    await new Promise<void>(resolve => server.listen(socket, resolve));
    await run(socket, directory);
  } finally {
    await new Promise<void>(resolve => server.close(() => resolve()));
    await rm(directory, { recursive: true, force: true });
  }
}

test("host updater authenticates peers, validates targets and persists results (Python)", () => {
  for (const suite of ["tests/host-updater.test.py", "tests/host-updater-release.test.py"]) {
    const result = spawnSync("python3", [suite, "-v"], { cwd: root, encoding: "utf8", timeout: 15000 });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stderr, /Ran \d+ tests/);
  }
});

test("client validates job identity, typed status, broker errors and unavailable sockets", async () => {
  for (const response of [
    { ok: true, jobId: "other-job", running: false, exitCode: 0 },
    { ok: true, jobId, running: "yes" },
    { ok: true, jobId, running: false, exitCode: -1 },
    null,
  ]) {
    await withSocket(() => response, async socket => {
      await assert.rejects(callHostUpdater({ action: "status", jobId }, socket));
    });
  }
  await withSocket(() => ({ ok: false, error: "An installer update is already running." }), async socket => {
    await assert.rejects(callHostUpdater({ action: "start", jobId, channel: "releases", ref: "v1.2.3" }, socket), /already running/);
  });
  await assert.rejects(callHostUpdater({ action: "status" }, "/no-such-metis-updater.sock"), /unavailable/);
});

test("configured updates use only the host protocol and never copy or execute an app-controlled installer", async () => {
  const requests: HostUpdateRequest[] = [];
  await withSocket(request => {
    requests.push(request);
    return { ok: true, jobId, running: false, exitCode: 0 };
  }, async (socket, dataDir) => {
    const before = process.env.METIS_UPDATE_SOCKET;
    process.env.METIS_UPDATE_SOCKET = socket;
    try {
      const result = await runInstallerUpdate({
        root: path.join(dataDir, "nonexistent-readonly-release"), dataDir,
        serviceName: "app-sandbox", docker: false, platform: "linux",
        channel: "releases", tag: "v1.2.3", jobId,
      }, () => {});
      assert.equal(result.tag, "v1.2.3");
      assert.deepEqual(requests, [{ action: "start", jobId, channel: "releases", ref: "v1.2.3" }]);
      await assert.rejects(readFile(path.join(dataDir, "metis-ai-update-run.sh")), /ENOENT/);
    } finally {
      if (before === undefined) delete process.env.METIS_UPDATE_SOCKET; else process.env.METIS_UPDATE_SOCKET = before;
    }
  });
});

test("configured updater failure propagates without a direct-systemd fallback", async () => {
  await withSocket(() => ({ ok: true, jobId, running: false, exitCode: 23 }), async (socket, dataDir) => {
    const before = process.env.METIS_UPDATE_SOCKET;
    process.env.METIS_UPDATE_SOCKET = socket;
    try {
      await assert.rejects(runInstallerUpdate({
        root: dataDir, dataDir, serviceName: "test", docker: false, platform: "linux",
        channel: "releases", tag: "v1.2.3", jobId,
      }, () => {}), /status 23/);
    } finally {
      if (before === undefined) delete process.env.METIS_UPDATE_SOCKET; else process.env.METIS_UPDATE_SOCKET = before;
    }
  });
});

for (const completed of [false, true]) test(completed
  ? "terminal host status reads the completed log after a concurrent installer finish"
  : "a fresh app process recovers a host job even when its runner never wrote an exit marker", async () => {
  let currentDirectory = "";
  await withSocket(async () => {
    if (completed) {
      await new Promise(resolve => setTimeout(resolve, 100));
      await writeFile(path.join(currentDirectory, "metis-installer-update.log"), "[metis-update-job:" + jobId + "]\nMetis AI installed successfully.\n[metis-update-exit:0]\n");
    }
    return { ok: true, jobId, running: false, exitCode: completed ? 0 : 1 };
  }, async (socket, dataDir) => {
    currentDirectory = dataDir;
    await writeFile(path.join(dataDir, "metis-update-job.json"), JSON.stringify({
      jobId, status: "preparing", startedAt: new Date().toISOString(), startedByPid: 1, logs: [],
    }));
    await writeFile(path.join(dataDir, "metis-installer-update.log"), "[metis-update-job:" + jobId + "]\n");
    const runner = path.join(dataDir, "recover.mjs");
    await writeFile(runner, `import { resolveUpdateJob } from ${JSON.stringify(path.join(root, "lib/update-job.ts"))};
const job = await resolveUpdateJob(${JSON.stringify(jobId)});
if (job?.status !== ${JSON.stringify(completed ? "ready" : "failed")}) throw new Error(JSON.stringify(job));
console.log("HOST_JOB_FAILURE_RECOVERED");`);
    // Keep the socket server's event loop available while the child polls it.
    const { spawn } = await import("node:child_process");
    const output = await new Promise<string>((resolve, reject) => {
      const child = spawn(process.execPath, ["--import", path.join(root, "node_modules/tsx/dist/loader.mjs"), runner], {
        cwd: root, env: { ...process.env, AI_CHAT_ROOT: dataDir, CHAT_DATA_DIR: dataDir, METIS_UPDATE_SOCKET: socket }, timeout: 10000,
      });
      let text = "";
      child.stdout.on("data", value => { text += value; });
      child.stderr.on("data", value => { text += value; });
      child.once("error", reject);
      child.once("close", code => code === 0 ? resolve(text) : reject(new Error(text)));
    });
    assert.match(output, /HOST_JOB_FAILURE_RECOVERED/);
    const stored = JSON.parse(await readFile(path.join(dataDir, "metis-update-job.json"), "utf8"));
    assert.equal(stored.status, completed ? "ready" : "failed");
  });
});
