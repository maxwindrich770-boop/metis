import { createConnection } from "node:net";

export type HostUpdateRequest =
  | { action: "start"; jobId: string; channel: "releases" | "commits"; ref: string }
  | { action: "status"; jobId?: string };

export type HostUpdateStatus = {
  jobId?: string;
  running: boolean;
  exitCode?: number;
};

/** Fixed update operation, separate from provider tools and arbitrary host commands. */
export function callHostUpdater(
  request: HostUpdateRequest,
  socketPath = process.env.METIS_UPDATE_SOCKET,
): Promise<HostUpdateStatus> {
  if (!socketPath) return Promise.reject(new Error("The host updater is not configured."));
  return new Promise((resolve, reject) => {
    const connection = createConnection(socketPath);
    let output = "";
    let settled = false;
    const finish = (error?: Error, value?: HostUpdateStatus) => {
      if (settled) return;
      settled = true;
      connection.destroy();
      if (error) reject(error); else resolve(value!);
    };
    connection.setTimeout(35_000, () => finish(new Error("The host updater timed out.")));
    connection.once("error", () => finish(new Error("The host updater is unavailable. An operator must check its service and socket permissions.")));
    connection.once("connect", () => connection.write(JSON.stringify(request) + "\n"));
    connection.on("data", data => {
      output += data.toString("utf8");
      if (Buffer.byteLength(output) > 64 * 1024) return finish(new Error("Invalid host updater response."));
      const end = output.indexOf("\n");
      if (end < 0) return;
      try {
        const value = JSON.parse(output.slice(0, end));
        if (value.ok === false && typeof value.error === "string") return finish(new Error(value.error));
        if (value.ok !== true || typeof value.running !== "boolean"
          || (value.jobId !== undefined && typeof value.jobId !== "string")
          || (value.exitCode !== undefined && (!Number.isInteger(value.exitCode) || value.exitCode < 0))) {
          throw new Error("Invalid host updater response.");
        }
        if (request.jobId && value.jobId !== request.jobId) throw new Error("The host updater returned a different update job.");
        finish(undefined, { jobId: value.jobId, running: value.running, exitCode: value.exitCode });
      } catch (error) { finish(error instanceof Error ? error : new Error("Invalid host updater response.")); }
    });
    connection.once("close", () => finish(new Error("The host updater disconnected.")));
  });
}
