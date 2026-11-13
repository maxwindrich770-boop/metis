# Server updates from an isolated app

The host-administrator update action in Settings is shared by the web app and
the iOS web workspace. A sandboxed web process cannot use the host systemd bus;
`systemd-run: Failed to connect to bus: Operation not permitted` is a startup
failure, before any installer executes. Do not grant the web process general
systemd access or disable its sandbox.

## Fixed-operation host service

Set `METIS_UPDATE_SOCKET` in the app's operator-managed environment to the Unix
socket provided by `services/host-updater/server.py`. With this setting, both
startup and status checks go through that socket. Failure to connect does not
fall back to a local installer or another privilege path.

The existing authenticated host-admin API validates the selected GitHub release
or commit. It sends only a durable job UUID, channel and pinned release tag/full
commit SHA. The host service authenticates the caller's Linux UID with
`SO_PEERCRED`, rejects unknown request fields, and appends only `--version TAG`
or `--commit SHA` to its fixed command. Callers cannot choose paths, a shell,
environment variables, systemd properties or another service.

The updater launches a separate transient systemd unit. The app and broker may
restart while it runs. Root-owned state and the existing job-bound installer log
preserve status, exact exit code and errors. Concurrent starts are rejected and
repeating a job UUID cannot change its target. Completion still requires the
installer's verified-success marker and a restarted app; exit zero alone is not
reported as a successful installation.

## Operator installation

This is production configuration and requires explicit operator approval.
Installing these source files in the development checkout does not activate it.

1. Review the actual deployment layout and its existing upgrade/rollback
   transaction. Install that approved updater command at a root-owned path.
   It must accept `--version TAG` and `--commit SHA`, verify the target, build
   before activation, preserve users/data/environment and service isolation,
   verify app/frontend/worker/MCP health, and print
   `Metis AI installed successfully.` only after those checks pass. A release
   symlink deployment must retain its release activation and rollback procedure;
   do not run the generic in-place installer over its current release.
2. Copy `server.py` to
   `/usr/local/libexec/metis-host-updater/server.py` and the example policy to
   `/etc/metis-host-updater.json`. Set the actual app account, existing data
   directory and the approved fixed command. Code, command, policy, state and
   all their parent directories must be root-owned and not writable by other
   accounts. The data directory may belong to the app; its parent remains
   root-controlled. Do not point the command at a copied script inside app data
   or at a writable source checkout.
3. Install `metis-host-updater.service`. Create its runtime/state directories
   with the modes declared in the unit and add an operator drop-in with
   `ReadWritePaths=/actual/data/directory`. Run the installed script with
   `--config /etc/metis-host-updater.json --check` as root, then enable/start only
   this new updater service. Its socket is mode 0600, owned by the configured
   app account; keep it outside provider/agent namespace mounts.
4. Configure the app's `METIS_UPDATE_SOCKET` and restart the app through the
   approved deployment. In the iPhone app open the regular Settings → Updates
   page, choose an available version, and use Update now. The existing
   maintenance page shows progress and reconnects after restart. Verify the
   active release, HTTP health and durable job/history result before declaring
   the production update successful.

For a conventional installer-managed checkout, the fixed command can be a
root-owned reviewed copy of `install/linux.sh` invoked with explicit
`--non-interactive --native --install-dir ... --data-dir ... --service-name ...`.
Use the installation's intended service identity and configured ports. Do not
replace a deployment's existing hardened service users or unit configuration
with generic installer units.

## Immutable releases and later upgrades

`services/host-updater/release.py` is an optional fixed command for an immutable
release deployment. Its operator-owned policy declares the repository, release
pointers, unprivileged build account, toolchain, health URLs and actual service
names. It builds in a separate systemd sandbox, checks the exact source/artifact
identity, copies only tracked source plus dependencies/build output, makes a
new immutable release, and atomically switches the release pointer. Only the
configured web app restarts. Worker and gateway PIDs must remain unchanged and
their actual HTTP health must pass. A failed activation restores the previous
app. SQLite's online backup runs before switching; existing databases,
credentials and environment files are never replaced.

Keep the installed broker, release command, policy and compatibility patch
outside every release. Keep `METIS_UPDATE_SOCKET` in the persistent operator
environment or a systemd drop-in. The regular Linux installer already merges
unknown environment keys from the old installation; it must retain this key.
Do not copy a whole production environment into a build sandbox.

Until the native integration is included upstream, the operator may provide a
reviewed compatibility patch. The unprivileged build applies it with a checked
three-way merge and runs the focused updater tests before building. An already
fully integrated patch is recognized. A partial upstream merge or conflict
fails **before activation**, leaving the current release running. An open pull
request alone does not guarantee that future upstream releases contain a fix;
refresh the patch when upstream changes require it.

The release command accepts a direct operator-only `--prepared-source` option
for bootstrapping an already verified clean checkout/build at the exact
`--commit`. Do not put that option in the broker's fixed command. Normal app
updates always fetch, build and validate the requested release/commit first.

## Checks and rollback

Run `corepack pnpm exec tsx --test tests/host-updater.test.ts
tests/installer-update.test.ts tests/updater-stability.test.ts
tests/update-job.test.ts`. This executes real Unix-socket/peer checks, a harmless
installer fixture, restart recovery and malformed-request tests without touching
host systemd. The systemd launch itself must additionally be checked by the
operator on an isolated named test installation before production activation.

To roll back configuration, first check for an active update. Restore the
previous app environment and its release via the existing deployment rollback.
Stop/remove only the newly installed updater when no update job is running.
Keep live app, worker, MCP, credential/console and remote-client services running.
