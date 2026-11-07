# Metis for iPhone

Open `MetisApple.xcodeproj`, select the shared **Metis** scheme and choose an
iPhone running iOS 17 or later. The scheme embeds the Share Extension and the
watchOS 8+ companion. For signed builds, follow the
[signing and provisioning steps](../../docs/APPSTORE-RELEASE-CHECKLIST.md).

Enter the canonical HTTPS origin of a configured Metis server, such as
`https://metis.example.com`, and sign in with an existing Metis account.
The approved native sign-in checks the session against the chat API, then
opens the server's **complete responsive Metis Web UI inside the app**.
Chat appearance, rich messages, model/effort/fast controls, mode and access
selection, context/usage, workspace panels and account settings therefore
use the same implementation and live contracts as the website.

On iPhone the Web UI's chat drawer and full-screen workspace replace the
desktop's side columns. Open account Settings for providers/API keys,
appearance, agent settings, devices and the other sections available to
your account. Server permissions and discovered model capabilities remain
authoritative; unavailable options are not invented by the iPhone client.

Open the chat sidebar's **iPhone controls** entry for **iPhone settings**,
native Watch/push access, connection details, sign-out and reload/back/forward.
Under **App protection**, opt in to **Protect Metis with Face ID** or **Touch ID**.
The name comes from LocalAuthentication discovery. Enabling requires biometrics;
unlocking and disabling support the system's device-passcode fallback. Backgrounding
locks the app, and a scene window also covers open sheets and app-switcher snapshots.
Cancelled authentication keeps the app covered. Drafts remain mounted while locked.
The optional local preference survives restart; it starts disabled on a new install.
These actions appear in an on-demand native sheet; there is no permanent bottom
bar. On same-origin pages without the sidebar, a compact native fallback keeps
the actions reachable. The Web workspace fills the available height through
the bottom safe area; its CSS owns home-indicator clearance. A native UIKit
keyboard layout guide clips the Web view above the actual input surface,
including a visible accessory bar during rotation. Within chat panes, the shell
retains the full window height so keyboard transitions do not recenter the
background or repin the transcript. Only the composer translates when it would
otherwise overlap the input surface; its original in-flow/absolute footprint
and horizontal pane alignment stay unchanged through focus and blur. The empty
welcome heading and optional incognito text follow the editor by the same
displacement, so a full-height keyboard cannot push the editor across the heading. The app restores
its session from Keychain after restart. Shared-text and shortcut drafts retain
their native review composer; push/Watch chat links open the corresponding Web chat.

See [Web workspace integration](#web-workspace-integration) for authentication,
downloads, external sites and verification boundaries.

On a paired Watch, opt in under **Allow Apple Watch access** on the iPhone.
The Watch can list chats and pending requests, send short prompts after
confirmation, deny a current approval with server acknowledgement, and hand
off a chat to the iPhone. Review the full tool context and allow actions on
the iPhone.

Share links or text to Metis from the system share sheet, then open Metis to
review the draft. In a chat, use **Attach** to choose files, photos or camera
images. Metis uploads only when you tap **Send**.

## watchOS 8 compatibility

The Watch target declares `WATCHOS_DEPLOYMENT_TARGET = 8.0`. Its navigation
uses `NavigationView` and selection-based `NavigationLink`, and its change
handlers use the single-value `onChange` overload. The minimum is watchOS 8
because the UI uses SwiftUI `task` and confirmation dialogs. The Watch
continues to relay requests through an unlocked, signed-in iPhone with
**Allow Apple Watch access** enabled. It stores no server credentials.

Use the shared **MetisWatch** scheme for simulator builds. Check chat opening
and Back, creating a chat and opening it immediately, prompt confirmation,
retry after a lost connection, pending requests and confirmed denial. Disable
Watch access or sign out on the paired iPhone while a prompt is open: the
Watch must clear the old account's chats and return to the root. Watch
Simulator availability does not prove watchOS 8 runtime compatibility;
record the actual runtime and the built app's minimum OS separately.

Xcode 27.2 could not download the requested watchOS 8.3 arm64 simulator
runtime; the available watchOS 27.2 runtime is a separate current-OS check.
A toolchain/runtime that supports watchOS 8 is still needed for the legacy
runtime acceptance test. The committed/device target remains 8.0. For a
current Watch simulator, use the
[simulator-only invocation](../../docs/APPLE-CLIENTS-IMPLEMENTATION.md#building-with-a-newer-watch-simulator-sdk)
to derive its minimum from live SDK metadata and override only the simulator
build. Xcode 27.2's SDK requires 9.0 for a full build; Apple's matrix lists
watchOS 8 deployment support in Xcode 26.6. A successful source typecheck at
8.0 does not make a 9.0-minimum simulator artifact an 8.0 runtime test.

## Build version and notification placement

The iPhone marketing version is `0.1.$(CURRENT_PROJECT_VERSION)`. Build 14
therefore reports **0.1.14** in iPhone settings; advancing the build to 15
reports **0.1.15** without a separate UI version string. Settings appends the
optional `METIS_RELEASE_CHANNEL` from the bundle, currently **Developer Beta**,
so the current display is **0.1.14 Developer Beta**. Apple bundle version
metadata remains numeric; an empty release channel shows only that version.

Inside the iPhone Web workspace, top Sonner notices retain the library's
desktop/mobile gap and add `env(safe-area-inset-top)`. This keeps them below
the notch or Dynamic Island, including after rotation. The rule applies only
to the app's first-party presentation; it does not move the website's notices
or change the default Web-based app interface.

## Native appearance

The native sign-in keeps the Metis palette, labeled fields and original
vector wordmark. The post-login Web workspace uses the actual server UI and
its account appearance settings. It is not a separately restyled Swift copy
of the website. Native device sheets use the device's light/dark appearance. App controls use
Liquid Glass on iOS 26+, with material controls on older supported iOS releases
and opaque controls for reduced-transparency or increased-contrast preferences.
Mobile drawer selections for New chat, Notebooks and Automations reuse the
existing close action after navigation. The mobile drawer stays visible through
its exit slide and hides only when it finishes; reopening shows it immediately,
and reduced-motion settings skip the slide. Search, account controls, project
expanders, New agent and desktop navigation retain their existing behavior.
The drawer and its account/settings footer keep full-window geometry while
search opens the input surface; the keyboard covers the footer. Search uses
readable text without focus zoom, a stable phone-dialog top and a results list
bounded by the visible space so its final result remains reachable.
The trusted Web workspace receives app-only translucent header/composer/sidebar
surfaces using the server's existing color tokens. Server features, parameters
and account state remain authoritative.
The previous native chat interface remains available only to Debug regression
tests with the explicit launch flag `-metis.native-interface`.

Design references: `app/globals.css`, `components/app-shell.tsx`,
`components/composer-add-menu.tsx`, and `public/metis-wordmark.svg` in
[the official repository](https://github.com/f1shyondrugs/metis), reviewed at
`7d3bf21562244ed3596b5bba9c3bea7dee34885d`. The asset catalog retains the
wordmark's paths and proportions and renders it as a light/dark template.

On 6 November 2026 the updated views compiled with Xcode 27.2. Four selected
UI tests passed across light/dark and paired iPhone-simulator runs: HTTPS
rejection, live chat and session recovery, accessible sign-in with large text
and landscape, and Watch opt-in restoration after restart. The suite exports
real simulator screenshots. The Watch source passed an 8.0 API availability
type-check; the previous source failed that same check on newer APIs. Its
current-SDK simulator build uses an explicit 9.0 override and its process
started on watchOS 27.2. Direct watchOS 8 execution, manual Watch navigation
and VoiceOver verification remain open. No physical-device installation or
production deployment was performed in this simulator validation pass.

## Web workspace integration

`MetisWebWorkspace.swift` owns a unique nonpersistent WebKit data store.
It installs the validated host-only HttpOnly session cookie before loading
the configured origin. Cookie rotation updates the native session/Keychain;
logout or an unauthorized page clears the workspace and returns to native
sign-in. Authentication is never injected into JavaScript or a navigation URL.
The embedded browser does not share this session with external sites.

User-activated external links open a Safari sheet. Scripted setup popups from
the trusted first-party page require a native confirmation showing the host;
unsolicited off-origin redirects remain blocked. First-party downloads use a
unique managed temporary folder and the system share sheet. Only owned
temporary files are removed after dismissal. Web file inputs and media
permission prompts stay under system/user control; microphone and camera
usage descriptions are included.

No Web backend deployment is needed for the primary workspace: it loads the
configured server's currently installed UI. Mobile-only device registration,
offline revocation tickets and Watch helpers still depend on their existing
server endpoints and report unavailable when those endpoints are absent.
The Personal Team variant's Push/Share/Watch limitations below still apply.
A Web surface exposes existing server features; it does not prove every
provider OAuth flow, device capability or account setting has been exercised.

The glass-polish pass balances the sidebar's content gutters and uses a more
opaque sidebar surface than the account/settings surfaces. Native device sheets
use a shared material background with an opaque accessibility fallback. App-only
composer CSS keeps editable text at least 16px to prevent iOS focus autozoom
while preserving deliberate pinch zoom.

The native session now preserves only the Web UI's model-selection storage
family (its configured-prefix `_model` and `_model_params` keys). Preferences
stay bound to the verified origin/session in Keychain and are restored before
Web UI hydration; cookies and other Web storage remain nonpersistent. Model IDs
are opaque and the canonical Web UI still validates them and parameter choices
against the current model catalog. Logout/account switching clears this cache.

Startup uses a neutral session-restoration view until the saved cookie has been
checked against the server. A network error offers Retry without flashing the
login form; a revoked or expired session returns to sign-in. No authenticated
Web content is shown before the server accepts the session.

The earlier session-preferences pass confirmed twenty selected functional cases
across focused simulator runs. In addition to held server verification, offline recovery, revocation, focus
scale/centering, pinch, session rotation and external actions, they cover model
preference restart/rotation/account isolation/removal, canonical profile fallback,
push availability explanations, full-height sidebar material and safe controls.

The geometry checks use an immutable public XCUITest snapshot and retain the
2-point assertion. A native video/geometry pass also found a root WebKit focus
scroll animation that DOM-only probes missed. After keyboard-driven resizing,
only a fitted, unzoomed root with no user gesture/insets is normalized and stale
bounds animations are removed; longer pages, gestures and pinch retain their
behavior. Correction covers both opening and closing through UIKit's reported
transition duration and the following settle frames. Chat-only clipped root
boxes keep the larger background from becoming a scrollable root document;
other Web panes keep their normal viewport layout. A reserve inside the dock
retains its measured Home-indicator footprint while the native input surface
changes. Empty-state flow stays steady, and the canonical transcript observer
does not repin messages because a tall composer's measured height lost its inset.
The keyboard regression repeatedly opens and dismisses both established-chat
and empty-state composers using Web blur and the actual system Done button;
readonly focus with a retained input accessory remains a separate geometry case.
Frame samples measure the empty greeting-to-editor gap and matching displacement,
plus header/root/transcript stability during transitions, not only their endpoints.
An explicit Debug Simulator-only launch flag, `-metis.synthetic-input-occlusion`,
adds a labelled 360 pt native occlusion surface while the real keyboard guide is
raised. This covers larger occupied areas when Simulator only shows its input
accessory; it is not an Apple software-keyboard rendering claim and is excluded
from physical-device builds. The temporary native diagnostic code is removed from
the final source.

Account details use the canonical profile API when the optional mobile session
endpoint is absent. Missing push-device APIs are explained separately. The
Personal Team variant declares its intentionally removed push entitlement in an
explicit Info.plist; build permission, iOS denial, server configuration, missing
API, network errors and unknown capability versions remain distinct. Push is
reported enabled only after actual registration succeeds. This variant cannot
enable real APNs delivery; a push-enabled signed build and configured mobile
push backend are required.

The fixtures are synthetic integration evidence rather than screenshots of the
complete live Metis Web UI. The earlier largest-text native sign-in key-plane
visibility failure and direct watchOS 8 runtime validation remain open.

For focused Mac verification:

```sh
swiftc clients/apple/MetisiOS/MetisWebWorkspace.swift \
  clients/apple/Tests/WebWorkspacePolicySmoke.swift -o /tmp/metis-web-policy-smoke
/tmp/metis-web-policy-smoke

swiftc -parse-as-library clients/apple/MetisiOS/MetisAppLock.swift \
  clients/apple/Tests/AppLockSmoke.swift -o /tmp/metis-app-lock-smoke
/tmp/metis-app-lock-smoke

# Use a fresh fixture/database for the API smoke test, separate from UI tests.
node --import tsx clients/apple/Tests/fixture-server.ts 43102
# In another terminal:
swiftc -D DEBUG -parse-as-library clients/apple/MetisiOS/MetisAPI.swift \
  clients/apple/Tests/Smoke.swift -o /tmp/metis-apple-api-smoke
/tmp/metis-apple-api-smoke http://localhost:43102

```

App-lock UI tests use an explicit Debug Simulator-only biometric fixture with
a labelled synthetic confirmation dialog. They cover the detected Face ID/Touch ID
labels, unavailable devices, cancellation, coverage of native sheets, restart,
authenticated disable and retained Web drafts. They do not prove a real biometric
match or physical Touch ID operation. The fixture is excluded from device builds.

The default Web XCUITests exercise native login, HttpOnly authentication,
a persisted server action, app restart, cookie rotation, logout, downloads,
external links and scripted popup confirmation. Their loopback HTML fixture
is explicitly synthetic integration content, **not** a screenshot of the
Metis Web design. Preserve the existing native regression tests using their
explicit Debug flag.

## Personal Team iPhone test

For a free Personal Team, prepare a separate iPhone-only project on the Mac:

```sh
python3 clients/apple/scripts/prepare-personal-team.py \
  --team '<TEAM_ID_FROM_XCODE>' \
  --bundle-id '<YOUR_UNIQUE_BUNDLE_ID>' \
  --output /tmp/metis-personal-team-test
```

Use your own Team ID from Xcode Settings → Accounts and an available bundle ID.
The output directory must be new and outside the checkout. The helper creates
`MetisPersonalTeam.xcodeproj` with the shared **Metis Test** scheme and display
name. Open that generated project, select the connected iPhone and run with
your authenticated Personal Team. Preparation does not build, provision or
install anything; the original project and schemes stay unchanged.
Regenerate the temporary project if its directory or the source checkout moves.

This variant omits Push entitlements, App Groups, the Share Extension and Watch
companion. Push alerts, share-sheet handoff and the Watch app are unavailable.
Chat, attachments and the existing HTTPS/Keychain session behavior remain in
the iPhone sources. No Watch Simulator runtime download is needed.

## Local fixture

From the repository root, install the repository dependencies and start the
fixture in one terminal:

```sh
pnpm install --frozen-lockfile
node --import tsx clients/apple/Tests/fixture-server.ts
```

The fixture binds only to IPv4 loopback on port 43100 and uses a fresh temporary
database. It routes HTTP requests to the real Metis handlers and supplies
synthetic data and replay events. The live-run test uses the real submission
and agent workers plus the built-in MCP tool catalog. Its compatible model
provider is a deterministic HTTP fixture on the same loopback listener.
Run the fixture as your normal non-root Mac user.
Stop it with Ctrl-C.

Use `http://localhost:43100` in a **Debug iPhone Simulator** build with
`metis-apple-fixture-alice` / `apple-fixture-only`. These are public fixture
credentials, never use them for a real account. Physical devices and Release
builds require HTTPS.

To run the API smoke test on the Mac while the fixture is running:

```sh
swiftc -D DEBUG clients/apple/MetisiOS/MetisAPI.swift clients/apple/Tests/Smoke.swift -o /tmp/metis-apple-smoke
/tmp/metis-apple-smoke
```

The smoke test changes chats, messages and run state. Before running the UI
tests, stop only the fixture with Ctrl-C in its terminal and start it again:

```sh
node --import tsx clients/apple/Tests/fixture-server.ts
```

Each restart creates a fresh temporary database with the original seed.
Restart between smoke and UI test runs so the suites do not share mutated data.
With an installed iPhone Simulator runtime and the fresh fixture running,
run the native UI tests:

```sh
xcodebuild -project clients/apple/MetisApple.xcodeproj -scheme Metis \
  -destination 'platform=iOS Simulator,name=<installed iPhone>' \
  -parallel-testing-enabled NO test
```

Keep normal simulator code signing enabled for UI tests so Keychain session
restoration can be exercised. Simulator signing does not require an Apple
Developer team. The commands below disable signing for compilation checks.

To compile without code signing:

```sh
xcodebuild -project clients/apple/MetisApple.xcodeproj -scheme Metis \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project clients/apple/MetisApple.xcodeproj -scheme Metis \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

See the [implementation notes](../../docs/APPLE-CLIENTS-IMPLEMENTATION.md)
for the tested scope and device requirements.
