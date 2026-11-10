# Apple clients implementation

## Watch installation failure — 10 November 2026

Build 17 is **not provisioned for the physical Watch**. The iPhone installation
log records actual Watch rejection `ApplicationVerificationFailed / 0xe8008015`
at 12:15:08 local time: a valid provisioning profile was not found. Both Watch
profiles authorize only the phone UDID. The previous successful build/signature
checks did not check this device authorization.

A fresh automatic target-only Watch build repeated the same phone-only profiles;
it did not fix the failure. No replacement beta is reported as fixed or installed.
The phone companion registry and a direct paired Watch lockdown connection report
watchOS 8.8.2 and armv7k, but Xcode 26.6/27.2 destination discovery still reports
an empty version and undefined architecture. Watch registration/profile creation
through Xcode is consequently unresolved in this environment. No cached profile
authorizes the Watch.

`scripts/verify-watch-install.py` now checks phone/Watch/extension profile device
IDs, expiry, team/application binding, bundle relationships and deep code
signatures. Five regression tests include the observed phone-only profile case.
Require this check to pass for the real device IDs before treating another build
as installable. A successful signature check alone is insufficient.

## watchOS 8 chat controls — 10 November 2026

Developer Beta 0.1.17 replaces the single-target Watch package with a watchOS 8
WatchKit container and SwiftUI extension. Xcode 26.6 compiles and links armv7k
and arm64_32; both Mach-O slices report minimum watchOS 8.0. Personal Team
preparation now has an opt-in `--include-watch`; the default remains iPhone-only.
Push/Share entitlements remain omitted. The signed iPhone app embeds the Watch
container and extension.

The Watch lists recent chats, creates chats, displays recent message excerpts
in a separate conversation screen, and submits confirmed text/dictation prompts.
It loads models and all advertised parameter choices from the authenticated
iPhone relay, in bounded pages. Missing options remain unavailable. Defaults
and saved values are checked on switches; the iPhone reloads discovery and
validates submitted parameters before sending through the existing chat API.
No usage/quota is relayed. No credentials are transferred to the Watch.
Session contexts carry a fresh revision so account changes clear old screens.

Verification: model-contract Swift smoke (unknown capabilities, defaults,
switches, numeric bounds, duplicates and Codable relay), Personal Team packaging
tests, existing Swift API smoke and mobile Apple server tests. Debug simulator
fixtures exercise the real Watch views without live accounts; fixture code is
excluded from release/device builds. The available simulator runs watchOS 27.2,
not watchOS 8; it is layout/launch evidence only.

Build environment: Xcode 26.6 Swift/compiler/linker and watchOS 26.5 SDK.
Its asset compiler required a matching simulator component; for this local
build only, `ASSETCATALOG_EXEC` used Xcode 27.2's asset compiler with the original
8.0 deployment setting. The optional 26.5 runtime download was cancelled after
the complete signed package built. No Xcode installation or production service
was replaced. Build output and raw evidence are in the Mac Desktop folder
`metis apple/Entwicklung/Build17-WatchOS8-Final`.

Hardware boundary: iPhone installation and launch succeeded. The paired Series 3
is listed by Xcode, but direct CoreDevice queries timed out; Watch installation,
watchOS 8 execution, dictation and live phone-to-Watch round trips are not yet
confirmed. Install the bundled companion through the iPhone Watch app and enable
Watch access in Metis for hardware acceptance.


## First delivery

Branch `feat/apple-clients`, based on upstream `master` at
`a5a70d4bbcb56c9a8cf582d37e3a7467840d35ce`. The remote HEAD matched the plan.
The Apple clients use the existing TypeScript handlers and SQLite data as the
source of truth. The Xcode project contains the iPhone app, Watch companion,
and iPhone Share Extension. The server adds an optional APNs device registry,
outbox and versioned mobile approval routes. See the
[API inventory](./APPLE-API-INVENTORY.md).

| Milestone | Evidence and remaining scope |
| --- | --- |
| A, audit and spikes | Pinned source, API inventory, SSE replay and a live Metis worker stream against a deterministic local provider verified. Signed device launch and Series 3 hardware testing remain open. |
| B, connection | Login, logout, active server selection and expired-session handling. The latest valid cookie is restored through device-only Keychain storage. Offline logout erases login credentials and queues a revocation-only ticket. |
| C, chats | List, search, pin, archive, paginated history, create/send, live SSE, resume cursor and cancel. Chat rows refresh by ID during live sync and the visible history uses HTTP validators. The transcript has Markdown, code copying and expandable tool activity and reasoning previews. |
| D, Push | Owner-scoped encrypted registration, durable outbox, APNs HTTP/2 delivery and notification routing. Stubbed delivery tests cover retry and revocation. Signed APNs delivery still needs a test device. |
| E, decisions | Native approval review with biometric confirmation, versioned server-side resolution and question forms. Allow and question answers require the phone app. |
| F, iPhone features | Chats, Activity, Projects and Settings tabs. The Activity badge counts chats with pending decisions. Model catalog, project agents, system dictation, attachments, account and device settings, and redacted diagnostics. Main controls have German translations. |
| G, Watch | watchOS 10+ companion with opt-in phone relay, chat status, new chats, short prompts, pending questions and approvals, confirmed denial and iPhone handoff. Pairing, dictation, foreground/background behavior and mirrored notifications require testing on hardware. |
| H, device integrations | File/photo/camera selection, Shortcuts with a draft preview, and Share Extension for text and links. App Group provisioning and device tests remain open. |
| I, release | Reproducible unsigned builds, app icons, a privacy manifest, local tests, CI configuration, and a [release checklist](./APPSTORE-RELEASE-CHECKLIST.md). Signing, store screenshots, review demo, TestFlight and external acceptance remain open. |

## Foreground chat follow-up — 6 November 2026

The previous uncommitted Apple implementation is preserved in baseline commit
`cc70add` on branch `feat/apple-foreground-sync`. The follow-up changes are
separate from that snapshot.

- Chat-sync batches now invalidate the open transcript when its chat changes
  or the stream requests a full snapshot. An unrelated chat event does not
  reload the visible conversation. The detail view coalesces refreshes, waits
  for in-flight history loads and cancels its refresh task outside the foreground.
  The existing history window, run cursor, streamed text and composer binding
  remain in place.
- Sending validates an explicit or persisted model ID against the current
  server catalog before uploading attachments. A removed selection produces
  an English/German error and retains the draft. An unset selection uses only
  an available default returned by the server. Explicit server-provided legacy
  aliases resolve to their canonical account model only when the match is unique;
  an exact model ID takes precedence.
- Automatic refreshes retain send errors and the stable submission ID for a
  manual retry after a lost acknowledgement, including attachment-only messages.
- The fixture can append an external message through its loopback-only test
  control. The iPhone regression test requires that message to appear without
  navigation or a foreground switch and checks that the unsent draft survives.
  The same test failed on the previous transcript implementation at that assertion.
  CI now restarts its own fixture between Swift smoke and UI suites to avoid
  sharing mutated seed data. UI tests use normal simulator ad-hoc signing for
  Keychain access; unsigned compilation alone does not exercise session restoration.
- The development plan's status now points here instead of claiming that no
  implementation exists. Signing, APNs device delivery and Watch hardware
  acceptance remain open. Watch simulator/runtime downloads are deferred by
  operator instruction.

### Follow-up verification

On the existing Mac toolchain (Xcode 27.2, iOS 27.2 simulator, Node 26.3.0):

- Both iPhone UI tests passed: external foreground changes, preserved drafts,
  history pagination, lost-acknowledgement retry without duplicates, live worker
  streaming, background resume, Keychain relaunch, offline recovery and session
  revocation. The UI suite used simulator ad-hoc signing without a developer team.
- The final Swift smoke binary passed against a fresh isolated fixture, including
  live explicit/default model selection, rejection of a missing model, and
  server-advertised legacy alias resolution. It also exercised auth/isolation,
  history, replay, attachments and a real local worker stream.
- The focused backend command
  `node --import tsx --test tests/mobile-apple.test.ts tests/chat-submit-worker.test.ts tests/run-event-stream.test.ts`
  passed all 10 tests. The inherited revocation fixture now creates its isolated
  job through `enqueueJob` before appending events, satisfying the existing foreign key.
- The unsigned generic iPhone Release build (including Watch and Share Extension),
  TypeScript check, focused ESLint and Apple CI shell syntax checks passed.
  `NEXT_DIST_DIR=tmp/metis-apple-foreground-web-build pnpm build` passed with an
  isolated data directory. Generated temporary TypeScript paths were removed.
- `pnpm test` completed the backlog/provider groups (80/80 and 52/52) and the shared
  group (1,138 passed, 2 failed, 1 skipped). It stopped at that group's nonzero
  exit, so later chained groups were not reached. Both failures reproduced in a
  separate unchanged `cc70add` worktree: server-monitor startup reads a missing
  temporary `server-metrics.json`; workspace glob search compares macOS
  `/private/var/...` with `/var/...`. These remain pre-existing Web test issues.

No Watch runtime was installed or downloaded. No production deployment,
TestFlight upload, signed device/APNs delivery or physical Watch test was performed.

## Session and transport

Deployment target is iOS 17. The prototype bundle ID is a local build default.
Each login attempt owns an ephemeral URLSession. The app keeps only the active
session cookie and its exact origin in a device-only Keychain item, accessible
while the device is unlocked. Passwords are never stored. A restored cookie is
used only after an authenticated GET succeeds. A 401 clears local chat state.
Logout immediately erases the login cookie. On the next reachable foreground
contact, the app redeems a separately scoped revocation ticket if server
logout could not be confirmed. The ticket cannot read or create account data.
Unsent text stays in the current account's in-memory composer across chat
navigation. A retry of the same draft keeps its message ID. Logout and app
termination clear these drafts.

The iPhone closes both live streams outside the foreground. On activation it
refreshes the chat list and open transcript before reconnecting. A run that
remained open in memory resumes from its last processed event ID. The iPhone
simulator verified that switching away mid-response and returning resumes
from a nonzero cursor and displays the complete response.

Server origins must be HTTPS with normal system trust. Subpaths, credentials in
the URL, query strings, fragments and redirects are rejected. Only Debug on the
simulator and the Mac smoke binary accept HTTP on `localhost`. The Release
device bundle has no ATS exception. The local-network usage description covers
connections to a self-hosted instance on the LAN. A real deployment needs a
certificate trusted by the device and a route to the server, such as a VPN.

## APNs registration and review policy

The iPhone requests permission from the account menu. Device registration is
bound to the session owner and configured APNs topic/environment. Tokens are
encrypted with AES-256-GCM. Registrations expire with their session.
The server removes devices on session revocation, explicit deregistration and
permanent token rejection. Event filters apply per installation. The existing
observer dispatches a bounded outbox without coupling
push failures to the feed. See Apple's
[server setup](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)
and [device registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).

Lock-screen payloads are generic and include only an opaque reference for
authenticated retrieval. The notification's Open Metis action requires device
authentication and opens the current server state. A Watch denial requires
confirmation and an online iPhone relay that verifies the latest approval ID
and version. The Watch
displays success after the server accepts the denial. The phone loads the
current tool context and checks biometrics for Allow.
The server requires the current approval version and uses the existing
atomic transition. Biometrics are a phone UI control. They do not prove
device authentication to the server. A stale/repeated decision is rejected.

## watchOS 8 and Apple Watch Series 3

The Watch target now declares a minimum of watchOS 8.0. It uses
`NavigationView` with ID-tagged, selection-based `NavigationLink` instead of
the watchOS 9 `NavigationStack` APIs. Creating a chat selects its ID; losing
phone reachability, revoking Watch access or changing the phone session
clears that selection with the cached chat list. The two-argument
`onChange` calls are replaced by the watchOS 7-compatible single-value
overload. SwiftUI tasks and confirmation dialogs keep the minimum at
watchOS 8 rather than 7.

The WatchConnectivity request/response contract and session-revision check
are unchanged. Sending still uses the iPhone's authenticated API and server
model validation; approval denial still requires the current approval ID,
version and server acknowledgement. The Watch cannot approve a tool action.
No server credentials or provider defaults are introduced on the Watch.

The existing single-target app, `WKApplication` property and companion
bundle ID remain in place. Both Watch build configurations inherit
`MetisWatch.xcconfig`; no project-file override or target restructuring is
needed for this source change. Apple's current symbol documentation lists
`NavigationView` and `WKApplication` from watchOS 7, and the selected
`NavigationLink` initializer from watchOS 6:
[NavigationView](https://developer.apple.com/documentation/swiftui/navigationview),
[selection-based NavigationLink](https://developer.apple.com/documentation/swiftui/navigationlink/init(destination:tag:selection:label:)),
[onChange](https://developer.apple.com/documentation/swiftui/view/onchange(of:perform:)),
[WKApplication](https://developer.apple.com/documentation/bundleresources/information-property-list/wkapplication).

### Verification boundaries

Apple Watch Series 3 supports watchOS 8.8.1. Declaring 8.0 and removing newer
source APIs is the compatibility implementation; it is not evidence that
the app ran on Series 3 or an 8.x simulator. Xcode 27.2 lists a newer supported
deployment range. Its requested watchOS 8.3 arm64 simulator download returned
“not available for download”; watchOS 27.2 downloaded successfully. A test
on that newer runtime must be reported as such. See
[Apple Watch compatibility](https://support.apple.com/en-us/118490) and
[Xcode requirements](https://developer.apple.com/xcode/system-requirements/).

The installed Xcode 27.2 SDK metadata declares
`SupportedTargets.watchsimulator.MinimumDeploymentTarget = 9.0` and
`SupportedTargets.watchos.MinimumDeploymentTarget = 9.0`. The full build at
8.0 failed at that SDK deployment-range check. A direct Swift typecheck of
`MetisWatchApp.swift` with target `arm64-apple-watchos8.0-simulator` and the
27.2 Watch Simulator SDK returned exit 0. This checks source/API availability;
it does not produce or run a watchOS 8 app. The SDK's concurrency minimum is
8.0, which is distinct from its full-build minimum.

Keep the repository and device deployment target at 8.0. Building a device
artifact for that minimum requires an SDK that supports it: Apple's
[current Xcode support matrix](https://developer.apple.com/support/xcode/)
lists watchOS 8–26.5 deployment support for Xcode 26.6 and watchOS 9–27 for
Xcode 27.2. A current simulator may use the destination-specific command below without
changing that device requirement.

For simulator acceptance, build the **MetisWatch** scheme and inspect the
result's `MinimumOSVersion` and executable deployment metadata. Record the
actual runtime, SDK and simulator minimum. The simulator override below is
not evidence of an 8.x device build. Then verify:

- Opening an existing chat, returning with Back, and creating a new chat
  that opens its prompt screen immediately.
- Prompt entry and confirmation; cancellation sends nothing; an acknowledged
  prompt clears the draft, and a failed attempt retains its submission ID.
- Unreachable phone, signed-out phone and Watch access disabled. Revoking
  access or changing accounts while a prompt is open clears navigation and
  cached account content.
- Pending question/approval display, phone handoff and confirmed denial.
  The iPhone must still reject stale approval versions.
- Compact Watch dimensions, larger text and reachability changes during
  navigation. Use a paired simulator only where WatchConnectivity is
  supported, and identify any relay scenarios the simulator cannot exercise.

### Building with a newer Watch Simulator SDK

Resolve the SDK from the selected Xcode installation. This command reads its
documented target metadata, fails if that metadata is absent or malformed,
and uses the greater of the app's requested minimum and the SDK's minimum.
The ordinary deployment-setting assignment applies only to this explicit
Watch Simulator build invocation. It does not alter `MetisWatch.xcconfig`.
Do not copy that override into a device build or the project's persistent
settings. Replace the destination placeholder with an actually installed
Watch simulator ID.

```sh
METIS_WATCH_REQUESTED_OS=8.0
METIS_WATCH_SIM_SDK="$(xcrun --sdk watchsimulator --show-sdk-path)"
METIS_WATCH_SIM_ARCH="$(uname -m)"
METIS_WATCH_SIM_MIN="$(python3 - "$METIS_WATCH_SIM_SDK/SDKSettings.json" "$METIS_WATCH_REQUESTED_OS" <<'PY'
import json
import re
import sys

with open(sys.argv[1]) as metadata:
    sdk_minimum = json.load(metadata)["SupportedTargets"]["watchsimulator"]["MinimumDeploymentTarget"]
requested = sys.argv[2]

def version(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ValueError("Missing or malformed SDK/deployment version")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))

print(max((requested, sdk_minimum), key=version))
PY
)" || exit 1

# Source/API check at the requested minimum; no artifact or runtime test.
xcrun --sdk watchsimulator swiftc -typecheck -parse-as-library \
  -target "$METIS_WATCH_SIM_ARCH-apple-watchos$METIS_WATCH_REQUESTED_OS-simulator" \
  -sdk "$METIS_WATCH_SIM_SDK" clients/apple/MetisWatch/MetisWatchApp.swift || exit 1

# Full build for this Watch Simulator destination only.
xcodebuild -project clients/apple/MetisApple.xcodeproj -scheme MetisWatch \
  -sdk watchsimulator -destination 'platform=watchOS Simulator,id=<installed-watch-udid>' \
  "WATCHOS_DEPLOYMENT_TARGET=$METIS_WATCH_SIM_MIN" \
  CODE_SIGNING_ALLOWED=NO build
```

Run the build only after the typecheck succeeds. A 9.0 simulator minimum from
this calculation is expected for SDK 27.2; never label that artifact as a
watchOS 8 build. Keep both `-sdk watchsimulator` and the Watch Simulator
destination in this command. Check resolved build settings and artifact
metadata after running it. SDK conditions are supported inside xcconfig
files, but bracketed conditional assignments must not be passed directly as
`xcodebuild` command-line settings: this toolchain parses the first equals
sign as the assignment separator.

Before claiming watchOS 8 runtime compatibility, repeat the applicable
checks with an installed 8.x runtime and a supporting toolchain. Physical
Series 3 pairing, dictation and notification mirroring are separate hardware
acceptance steps; the current operator scope is simulators only. App Store
SDK/submission requirements are a separate release gate and are not proven
by a simulator build.

## Verification and handoff

- Xcode 27.2 compiled Debug for the iPhone 17 simulator and archived unsigned
  Release for generic iPhone. The archive contained the iPhone app, Watch app,
  Share Extension and privacy manifest. Release had no ATS exception.
- Native Foundation smoke test passed on macOS against the real Metis
  handlers with isolated SQLite. It covered credentials, two-account
  isolation, pagination, conditional HTTP 304, logout, replay, idempotency, cancellation, chunked
  upload and byte-exact download. It also ran the real Metis worker against a
  deterministic loopback provider, verified that the first response chunk
  arrived before completion, and compared streamed text with the saved
  assistant message. No external provider was called.
- The iPhone 17 simulator on iOS 27.2 passed the transport policy and
  sign-in/chat tests. The tests sent a prompt through the SwiftUI interface
  and the real Metis worker, displayed the fixture response and restored the
  Keychain session on relaunch. They also opened the Activity, Projects and
  Settings tabs, read the authenticated account name and returned to Chats.
- With the test server unreachable at launch, the iPhone kept the saved
  session and restored it after a manual retry. After server-side revocation,
  it returned to sign-in, hid chats and stayed signed out after relaunch.
- The chat fixture contains 75 messages. The Swift test loads all pages and
  checks for gaps or duplicates after a refresh. The iPhone test scrolls to
  the first message before sending and again after the live response.
- A delayed transcript request verified that the complete streamed text stays
  visible until the saved assistant message arrives.
- The fixture truncated the HTTP acknowledgement after committing a prompt.
  The iPhone kept the draft and displayed one user message after a manual
  retry. The Swift API test confirmed that both attempts used the same
  committed job and that only one message was stored.
- A two-account HTTP probe verified that an ID-filtered chat-list response
  returns only requested and accessible chats, rejects empty IDs and requires
  authentication.
- Backend tests covered durable delivery, account isolation, approval races,
  Web submission idempotency and SSE replay. The focused suite passed 32
  tests, including a loopback HTTP/2 check of the APNs request, ES256
  signature, and redacted payload. This check did not contact Apple.
  The full Web suite also ran. Its two failures, the server-monitor
  startup sample and the macOS temporary-path comparison in workspace search,
  reproduced on the unchanged upstream baseline. The Next.js production build
  and TypeScript checks passed. Targeted lint passed. Repository-wide lint
  reported 39 errors and 18 warnings in unchanged files. Reproduction
  instructions are in the
  [client README](../clients/apple/README.md).
- Device gate: choose a signing team and available bundle ID, install on an
  iPhone, then check trusted HTTPS, local network permissions, login, history,
  logout and session expiry against an isolated Metis instance.
- Next acceptance steps: sign a development build, run the device matrix,
  then validate the release archive and APNs sandbox/production configuration.
