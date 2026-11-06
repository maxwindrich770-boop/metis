import SafariServices
import SwiftUI
import UIKit
import WebKit

/// The server's responsive workspace is the primary app surface. Native chrome
/// only exposes device-level controls and never covers the web composer.
@MainActor
struct WebWorkspaceView: View {
    @ObservedObject var workspace: MetisWebWorkspace
    let origin: String
    let showConnectionSettings: () -> Void

    @State private var hasLoadedWorkspace = false
    @State private var openConnectionSettingsAfterDismiss = false
    @State private var confirmExternalNavigation = false

    var body: some View {
        ZStack {
            MetisTheme.background

            WorkspaceWebView(webView: workspace.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .vertical)
                .accessibilityHidden(!hasLoadedWorkspace || workspace.errorMessage != nil)
                .allowsHitTesting(hasLoadedWorkspace && workspace.errorMessage == nil)

            if let error = workspace.errorMessage {
                connectionFailure(error)
            } else if !hasLoadedWorkspace {
                openingWorkspace
                    .allowsHitTesting(false)
            }
        }
        // The whole workspace must opt out of SwiftUI keyboard avoidance.
        // Opting out only the UIKit child still lets its parent move that child
        // during the transition, even when the DOM and inner WK frame are stable.
        // UIKit's keyboard guide alone owns the usable web viewport below.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .top) {
            if workspace.isLoading && hasLoadedWorkspace && workspace.errorMessage == nil {
                ProgressView(value: workspace.progress)
                    .progressViewStyle(.linear)
                    .tint(MetisTheme.ink)
                    .frame(height: 2)
                    .accessibilityLabel("Loading workspace")
            }
        }
        .overlay(alignment: .topTrailing) {
            if !hasLoadedWorkspace || workspace.errorMessage != nil || !workspace.appControlsAvailable {
                Button {
                    workspace.appControlsRequested = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(WorkspaceGlassButtonStyle())
                .accessibilityLabel("iPhone controls")
                .accessibilityIdentifier("metis.appControlsFallback")
                .padding(12)
            }
        }
        .background(MetisTheme.background.ignoresSafeArea())
        .task {
            await workspace.start()
            markWorkspaceLoaded()
        }
        .onChange(of: workspace.isLoading) { _, loading in
            if !loading { markWorkspaceLoaded() }
        }
        .onChange(of: workspace.externalConfirmationURL, initial: true) { _, url in
            confirmExternalNavigation = url != nil
        }
        .onChange(of: confirmExternalNavigation) { _, presented in
            if !presented { workspace.cancelExternalNavigation() }
        }
        .alert("Open external website?", isPresented: $confirmExternalNavigation) {
            Button("Open in browser") { workspace.approveExternalNavigation() }
            Button("Cancel", role: .cancel) { workspace.cancelExternalNavigation() }
        } message: {
            Text("This workspace wants to open \(externalWebsiteHost).")
        }
        .sheet(isPresented: $workspace.appControlsRequested, onDismiss: {
            if openConnectionSettingsAfterDismiss {
                openConnectionSettingsAfterDismiss = false
                showConnectionSettings()
            }
        }) {
            WorkspaceAppControls(workspace: workspace, origin: origin) {
                openConnectionSettingsAfterDismiss = true
                workspace.appControlsRequested = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
            .presentationBackground { MetisGlassSheetSurface() }
        }
        .sheet(item: externalPresentation, onDismiss: { workspace.externalURL = nil }) { destination in
            WorkspaceExternalPage(url: destination.url)
                .ignoresSafeArea()
        }
        .sheet(item: sharedFilePresentation, onDismiss: { workspace.sharedFile = nil }) { destination in
            WorkspaceShareSheet(url: destination.url) {
                // The workspace owns downloaded-file cleanup when this is cleared.
                workspace.sharedFile = nil
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var openingWorkspace: some View {
        VStack(spacing: 20) {
            MetisWordmark(width: 88)
            ProgressView()
                .tint(MetisTheme.ink)
            Text("Opening your workspace…")
                .font(.subheadline)
                .foregroundStyle(MetisTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MetisTheme.background)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("metis.workspaceLoading")
    }

    private func connectionFailure(_ error: String) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "network.slash")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(MetisTheme.muted)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Couldn’t open Metis")
                        .font(.title2.weight(.semibold))
                    Text(verbatim: error)
                        .font(.body)
                        .foregroundStyle(MetisTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: URL(string: origin)?.host ?? origin)
                        .font(.footnote)
                        .foregroundStyle(MetisTheme.muted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    Button("Try again") { workspace.retry() }
                        .buttonStyle(MetisPrimaryButtonStyle())
                        .accessibilityIdentifier("metis.workspaceRetry")
                    Button("iPhone settings", action: showConnectionSettings)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(MetisTheme.ink)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .background(MetisTheme.background)
        .accessibilityIdentifier("metis.workspaceError")
    }

    private func markWorkspaceLoaded() {
        if !workspace.isLoading && workspace.errorMessage == nil && workspace.webView.url != nil {
            hasLoadedWorkspace = true
        }
    }

    private var externalWebsiteHost: String {
        workspace.externalConfirmationURL?.host ?? String(localized: "an external website")
    }

    private var externalPresentation: Binding<WorkspacePresentation?> {
        Binding(
            get: { workspace.externalURL.map { WorkspacePresentation(url: $0) } },
            set: { workspace.externalURL = $0?.url }
        )
    }

    private var sharedFilePresentation: Binding<WorkspacePresentation?> {
        Binding(
            get: { workspace.sharedFile.map { WorkspacePresentation(url: $0) } },
            set: { workspace.sharedFile = $0?.url }
        )
    }
}

/// Device actions are deliberately on demand: the canonical web header and
/// composer keep their entire hit areas and the app reserves no bottom rail.
@MainActor
private struct WorkspaceAppControls: View {
    @ObservedObject var workspace: MetisWebWorkspace
    let origin: String
    let showConnectionSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    MetisWordmark(width: 72)
                    Spacer(minLength: 16)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(WorkspaceGlassButtonStyle())
                    .accessibilityLabel("Close iPhone controls")
                    .accessibilityIdentifier("metis.appControlsClose")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("iPhone controls")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: URL(string: origin)?.host ?? origin)
                        .font(.footnote)
                        .foregroundStyle(MetisTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Button(action: showConnectionSettings) {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone")
                            .font(.title3)
                            .accessibilityHidden(true)
                        Text("iPhone settings")
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(WorkspaceGlassButtonStyle())
                .accessibilityIdentifier("metis.iPhoneSettings")

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) { navigationActions }
                } else {
                    HStack(spacing: 12) { navigationActions }
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(MetisTheme.ink)
        .accessibilityIdentifier("metis.appControlsSheet")
    }

    @ViewBuilder
    private var navigationActions: some View {
        navigationAction("Back", symbol: "chevron.left", identifier: "metis.workspaceBack",
                         disabled: !workspace.canGoBack) {
            workspace.back()
        }
        navigationAction("Forward", symbol: "chevron.right", identifier: "metis.workspaceForward",
                         disabled: !workspace.canGoForward) {
            workspace.forward()
        }
        navigationAction("Reload", symbol: "arrow.clockwise", identifier: "metis.workspaceReload",
                         disabled: workspace.isLoading) {
            workspace.retry()
        }
    }

    private func navigationAction(_ title: LocalizedStringKey, symbol: String,
                                  identifier: String, disabled: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(WorkspaceGlassButtonStyle())
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
    }
}

/// A shared sheet material keeps device settings connected to the workspace.
/// Accessibility preferences always take precedence over translucency.
struct MetisGlassSheetSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if reduceTransparency || contrast == .increased {
            MetisTheme.background
        } else {
            Rectangle()
                .fill(.thinMaterial)
                .overlay(MetisTheme.background.opacity(0.12))
        }
    }
}

/// Liquid Glass belongs to controls. Opaque, high-contrast controls take
/// precedence when accessibility preferences request them.
private struct WorkspaceGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        surface(configuration.label)
            .foregroundStyle(MetisTheme.ink)
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
            .contentShape(Capsule())
    }

    @ViewBuilder
    private func surface(_ label: Configuration.Label) -> some View {
        if reduceTransparency || contrast == .increased {
            label
                .background(MetisTheme.secondary, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(contrast == .increased ? MetisTheme.ink : MetisTheme.border,
                                           lineWidth: 1)
                }
        } else if #available(iOS 26.0, *) {
            label.glassEffect(.regular.interactive(isEnabled && !reduceMotion), in: Capsule())
        } else {
            label
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(MetisTheme.border, lineWidth: 1) }
        }
    }
}

/// Presentation-only additions for the trusted, first-party web workspace.
/// Anchors come from its existing accessible sidebar, header and composer.
/// This never reads credentials, chat contents or provider/model state.
enum MetisAppWebPresentation {
    static let userScript = #"""
    (() => {
      if (window.top !== window || !window.webkit?.messageHandlers?.metisAppControls) return;
      if (document.getElementById('metis-native-app-style')) return;

      const style = document.createElement('style');
      style.id = 'metis-native-app-style';
      style.textContent = `
        html[data-metis-native-app="ios"] {
          --metis-app-glass: color-mix(in oklch, var(--background) 88%, transparent);
          --metis-app-sidebar-glass: color-mix(in oklch, var(--popover) 84%, transparent);
          --metis-app-settings-glass: color-mix(in oklch, var(--popover) 74%, transparent);
          --metis-app-edge: color-mix(in oklch, var(--foreground) 13%, transparent);
          --metis-app-highlight: color-mix(in oklch, var(--foreground) 6%, transparent);
          --metis-app-muted-ink: color-mix(in oklch, var(--muted-foreground) 88%, var(--foreground));
          --metis-app-sidebar-gutter: 0.5rem;
        }
        /* The web view fills the screen. In-flow content owns one status-bar
           inset; fixed overlays paint behind it and inset their controls below. */
        html[data-metis-native-app="ios"] .metis-shell {
          box-sizing: border-box;
          padding-top: env(safe-area-inset-top);
        }
        html[data-metis-native-app="ios"] [data-metis-app-header],
        html[data-metis-native-app="ios"] [data-metis-app-composer] {
          background: var(--metis-app-glass);
          -webkit-backdrop-filter: blur(22px) saturate(1.15);
          backdrop-filter: blur(22px) saturate(1.15);
        }
        html[data-metis-native-app="ios"] [data-metis-app-header] {
          border-bottom-color: var(--metis-app-edge);
        }
        html[data-metis-native-app="ios"] [data-metis-app-composer] {
          border-radius: 24px;
          box-shadow: inset 0 0 0 1px var(--metis-app-edge),
                      0 8px 28px color-mix(in oklch, var(--foreground) 5%, transparent);
        }
        html[data-metis-native-app="ios"] aside[aria-label="Chats sidebar"],
        html[data-metis-native-app="ios"] [data-metis-app-account-menu],
        html[data-metis-native-app="ios"] [data-metis-app-settings-surface] {
          --muted-foreground: var(--metis-app-muted-ink);
        }
        html[data-metis-native-app="ios"] aside[aria-label="Chats sidebar"] {
          background: linear-gradient(150deg, var(--metis-app-highlight), transparent 45%),
                      var(--metis-app-sidebar-glass);
          -webkit-backdrop-filter: blur(26px) saturate(1.15);
          backdrop-filter: blur(26px) saturate(1.15);
          border-radius: 0 24px 24px 0;
          box-shadow: inset -1px 0 0 var(--metis-app-edge);
          box-sizing: border-box;
          padding-top: env(safe-area-inset-top);
        }
        /* Match the content gutters inside the system-safe area. */
        html[data-metis-native-app="ios"] aside[aria-label="Chats sidebar"] [aria-label="Metis"]:not([role="img"]) {
          padding-top: var(--metis-app-sidebar-gutter);
          padding-bottom: var(--metis-app-sidebar-gutter);
        }
        html[data-metis-native-app="ios"] [data-metis-app-sidebar-footer] {
          padding-bottom: calc(var(--metis-app-sidebar-gutter) + env(safe-area-inset-bottom));
        }
        html[data-metis-native-app="ios"] [data-metis-app-account-menu],
        html[data-metis-native-app="ios"] [data-metis-app-settings-surface] {
          background: linear-gradient(150deg, var(--metis-app-highlight), transparent 45%),
                      var(--metis-app-settings-glass);
          -webkit-backdrop-filter: blur(28px) saturate(1.15);
          backdrop-filter: blur(28px) saturate(1.15);
          border-radius: 24px;
          box-shadow: inset 0 0 0 1px var(--metis-app-edge);
        }
        html[data-metis-native-app="ios"] [data-metis-app-settings-page] {
          margin: 8px;
          overflow: hidden;
        }
        /* The live composer is 15px. A readable minimum prevents WebKit's
           focus zoom without constraining deliberate pinch or text scaling. */
        html[data-metis-native-app="ios"] .composer-input-area,
        html[data-metis-native-app="ios"] .composer-input-area textarea,
        html[data-metis-native-app="ios"] .composer-input-area [contenteditable="true"] {
          font-size: max(16px, 1rem);
        }
        /* UIKit already removes the keyboard from the web viewport. The
           server's transient visualViewport bottom offset must not remove it twice. */
        html[data-metis-native-app="ios"] [data-metis-app-composer-dock]:focus-within {
          bottom: 0 !important;
        }
        html[data-metis-native-app="ios"] aside.workspace-surface {
          box-sizing: border-box;
          padding-bottom: env(safe-area-inset-bottom);
        }
        html[data-metis-native-app="ios"] [data-metis-app-workspace-overlay] {
          padding-top: env(safe-area-inset-top);
        }
        html[data-metis-native-app="ios"] [data-metis-app-controls] {
          display: flex;
          align-items: center;
          gap: 10px;
          width: 100%;
          min-height: 48px;
          margin-bottom: 8px;
          padding: 10px 12px;
          border: 1px solid var(--metis-app-edge);
          border-radius: 18px;
          background: color-mix(in oklch, var(--background) 78%, transparent);
          color: var(--foreground);
          font: 500 0.875rem/1.4 -apple-system, BlinkMacSystemFont, sans-serif;
          text-align: left;
          cursor: pointer;
          touch-action: manipulation;
          transition: background-color 120ms ease;
        }
        html[data-metis-native-app="ios"] [data-metis-app-controls] svg {
          width: 20px;
          height: 20px;
          flex-shrink: 0;
        }
        html[data-metis-native-app="ios"] [data-metis-app-controls] span {
          min-width: 0;
          flex: 1;
        }
        html[data-metis-native-app="ios"] [data-metis-app-controls]:active {
          background: var(--muted);
        }
        html[data-metis-native-app="ios"] [data-metis-app-controls]:focus-visible {
          outline: 2px solid var(--foreground);
          outline-offset: 2px;
        }
        @media (prefers-reduced-transparency: reduce), (prefers-contrast: more) {
          html[data-metis-native-app="ios"] [data-metis-app-header],
          html[data-metis-native-app="ios"] [data-metis-app-composer],
          html[data-metis-native-app="ios"] aside[aria-label="Chats sidebar"],
          html[data-metis-native-app="ios"] [data-metis-app-account-menu],
          html[data-metis-native-app="ios"] [data-metis-app-settings-surface],
          html[data-metis-native-app="ios"] [data-metis-app-controls] {
            background: var(--background);
            -webkit-backdrop-filter: none;
            backdrop-filter: none;
            border-color: var(--foreground);
          }
          html[data-metis-native-app="ios"] [data-metis-app-composer],
          html[data-metis-native-app="ios"] aside[aria-label="Chats sidebar"],
          html[data-metis-native-app="ios"] [data-metis-app-account-menu],
          html[data-metis-native-app="ios"] [data-metis-app-settings-surface] {
            box-shadow: inset 0 0 0 1px var(--foreground);
          }
        }
        @media (prefers-reduced-motion: reduce) {
          html[data-metis-native-app="ios"] [data-metis-app-controls] {
            transition: none;
          }
        }
      `;
      document.head.append(style);

      let lastAvailability = null;
      const announceAvailability = available => {
        if (lastAvailability === available) return;
        lastAvailability = available;
        window.webkit.messageHandlers.metisAppControls.postMessage(
          available ? 'controls-available' : 'controls-unavailable');
      };
      const decorate = () => {
        const accountButtons = document.querySelectorAll('aside button[aria-label="Open account menu"]');
        if (!accountButtons.length) {
          delete document.documentElement.dataset.metisNativeApp;
          announceAvailability(false);
          return;
        }
        document.documentElement.dataset.metisNativeApp = 'ios';
        for (const account of accountButtons) {
          const menu = document.getElementById(account.getAttribute('aria-controls') || '');
          if (menu?.matches('[role="menu"]') && !menu.hasAttribute('data-metis-app-account-menu')) {
            menu.dataset.metisAppAccountMenu = '';
          }
          const sidebar = account.closest('aside');
          const footer = account.parentElement;
          if (!sidebar || !footer) continue;
          if (!footer.hasAttribute('data-metis-app-sidebar-footer')) footer.dataset.metisAppSidebarFooter = '';
          if (footer.querySelector('[data-metis-app-controls]')) continue;
          const button = document.createElement('button');
          button.type = 'button';
          button.id = sidebar.getAttribute('aria-label') === 'Chats sidebar'
            ? 'metis-app-controls' : 'metis-app-controls-desktop';
          button.dataset.metisAppControls = '';
          button.setAttribute('aria-label', metisAppControlsLabel);
          button.setAttribute('aria-haspopup', 'dialog');
          button.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="6" y="2" width="12" height="20" rx="3"/><path d="M10 18h4"/></svg><span></span><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
          button.querySelector('span').textContent = metisAppControlsLabel;
          footer.insertBefore(button, account);
        }
        for (const toggle of document.querySelectorAll('header button[aria-label="Open sidebar"], header button[aria-label="Show sidebar"], header button[aria-label="Hide sidebar"]')) {
          const header = toggle.closest('header');
          if (header && !header.hasAttribute('data-metis-app-header')) header.dataset.metisAppHeader = '';
        }
        for (const input of document.querySelectorAll('.composer-input-area')) {
          const form = input.closest('form');
          if (form && !form.hasAttribute('data-metis-app-composer')) form.dataset.metisAppComposer = '';
          const dock = form?.closest('[class~="pointer-events-none"][class~="z-20"][class~="w-full"]');
          if (dock && !dock.hasAttribute('data-metis-app-composer-dock')) dock.dataset.metisAppComposerDock = '';
        }
        for (const panel of document.querySelectorAll('aside.workspace-surface')) {
          const position = getComputedStyle(panel).position;
          if (position === 'fixed' || position === 'absolute') {
            if (!panel.hasAttribute('data-metis-app-workspace-overlay')) panel.dataset.metisAppWorkspaceOverlay = '';
          } else {
            delete panel.dataset.metisAppWorkspaceOverlay;
          }
        }
        // Settings can be a full account page on phones or a dialog on wider
        // layouts. Decorate only their existing semantic surface, never all dialogs.
        for (const surface of document.querySelectorAll('[data-metis-app-settings-surface]')) {
          if (!surface.querySelector('section[aria-labelledby="settings-page-title"]')) {
            delete surface.dataset.metisAppSettingsSurface;
            delete surface.dataset.metisAppSettingsPage;
          }
        }
        for (const section of document.querySelectorAll('section[aria-labelledby="settings-page-title"]')) {
          const dialog = section.closest('[data-slot="dialog-content"]');
          const page = section.closest('main[aria-label="Settings"]')?.parentElement;
          const surface = dialog || page;
          if (!surface) continue;
          if (!surface.hasAttribute('data-metis-app-settings-surface')) surface.dataset.metisAppSettingsSurface = '';
          if (!dialog && !surface.hasAttribute('data-metis-app-settings-page')) surface.dataset.metisAppSettingsPage = '';
        }
        announceAvailability(Boolean(document.querySelector('[data-metis-app-controls]')));
      };

      document.addEventListener('click', event => {
        const target = event.target instanceof Element
          ? event.target.closest('[data-metis-app-controls]') : null;
        if (!target || !event.isTrusted) return;
        event.preventDefault();
        window.webkit.messageHandlers.metisAppControls.postMessage('menu');
      });

      let scheduled = false;
      const scheduleDecoration = () => {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(() => {
          scheduled = false;
          decorate();
        });
      };
      const observer = new MutationObserver(scheduleDecoration);
      observer.observe(document.body, { childList: true, subtree: true });
      window.addEventListener('resize', scheduleDecoration);
      window.addEventListener('pageshow', () => {
        lastAvailability = null;
        decorate();
      });
      decorate();
    })();
    """#
}

private struct WorkspacePresentation: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

@MainActor
private struct WorkspaceWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        WorkspaceWebContainer(webView: webView)
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// UIKit determines the usable viewport, while WebKit receives its settled
/// geometry without inheriting the keyboard's animation on the entire page.
@MainActor
private final class WorkspaceWebContainer: UIView {
    private let webView: WKWebView
    private let viewportGuide = UILayoutGuide()
    private var viewportScrollObservations: [NSKeyValueObservation] = []
    private var viewportFocusScrollPending = false
    private var correctingViewportFocusScroll = false
    private var viewportFocusScrollLink: CADisplayLink?
    private var viewportFocusScrollFrames = 0


    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        // Keep tracking the full input surface, including an accessory retained
        // during rotation. The page alone clears the closed home indicator.
        keyboardLayoutGuide.usesBottomSafeArea = false
        addLayoutGuide(viewportGuide)
        NSLayoutConstraint.activate([
            viewportGuide.topAnchor.constraint(equalTo: topAnchor),
            viewportGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            viewportGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            viewportGuide.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])
        webView.accessibilityIdentifier = "metis.webWorkspace"
        addSubview(webView)
        // UIKit/WebKit view geometry changes occur on the main thread. Observe
        // the web process's later content-size/offset update, not just our frame.
        viewportScrollObservations = [
            webView.scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reconcileViewportFocusScroll() }
            },
            webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reconcileViewportFocusScroll() }
            },
        ]
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let viewport = viewportGuide.layoutFrame
        guard webView.frame != viewport else {
            reconcileViewportFocusScroll()
            return
        }
        if abs(webView.frame.width - viewport.width) > 0.5 {
            finishViewportFocusScroll()
        } else if viewport.height < webView.frame.height - 0.5,
                  keyboardLayoutGuide.layoutFrame.height > 0 {
            viewportFocusScrollPending = true
        }
        // Only the viewport resize is immediate. Keyboard motion, web scrolling
        // and all unrelated app/web animations retain their normal behavior.
        UIView.performWithoutAnimation {
            webView.frame = viewport
            webView.layoutIfNeeded()
        }
        reconcileViewportFocusScroll()
    }

    private func reconcileViewportFocusScroll() {
        guard viewportFocusScrollPending, !correctingViewportFocusScroll else { return }
        let scroll = webView.scrollView
        let pinch = scroll.pinchGestureRecognizer?.state
        guard !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating,
              pinch != .began, pinch != .changed,
              abs(scroll.zoomScale - 1) < 0.001 else {
            finishViewportFocusScroll()
            return
        }
        // A fitted app viewport has no legitimate root scroll range. Longer
        // documents, custom insets, and deliberate zoom retain WebKit behavior.
        guard scroll.contentInset == .zero, scroll.adjustedContentInset == .zero,
              scroll.contentSize.width <= scroll.bounds.width + 0.5,
              scroll.contentSize.height <= scroll.bounds.height + 0.5 else { return }
        correctingViewportFocusScroll = true
        UIView.performWithoutAnimation {
            if scroll.contentOffset != .zero {
                scroll.setContentOffset(.zero, animated: false)
            }
            // WebKit can clamp the model offset after resizing while a previous
            // focus-scroll bounds animation still presents a negative origin.
            for key in scroll.layer.animationKeys() ?? [] {
                guard let animation = scroll.layer.animation(forKey: key) as? CAPropertyAnimation,
                      let path = animation.keyPath,
                      path == "bounds" || path == "bounds.origin" ||
                        path == "bounds.origin.x" || path == "bounds.origin.y" else { continue }
                scroll.layer.removeAnimation(forKey: key)
            }
        }
        correctingViewportFocusScroll = false
        if viewportFocusScrollLink == nil {
            viewportFocusScrollFrames = 2
            let link = CADisplayLink(target: self, selector: #selector(finishViewportFocusScrollFrame(_:)))
            viewportFocusScrollLink = link
            link.add(to: .main, forMode: .common)
        }
    }

    @objc private func finishViewportFocusScrollFrame(_ link: CADisplayLink) {
        reconcileViewportFocusScroll()
        viewportFocusScrollFrames -= 1
        if viewportFocusScrollFrames <= 0 { finishViewportFocusScroll() }
    }

    private func finishViewportFocusScroll() {
        viewportFocusScrollLink?.invalidate()
        viewportFocusScrollLink = nil
        viewportFocusScrollPending = false
    }


}

@MainActor
private struct WorkspaceExternalPage: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.view.accessibilityIdentifier = "metis.externalBrowser"
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

@MainActor
private struct WorkspaceShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onComplete: @MainActor @Sendable () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.view.accessibilityIdentifier = "metis.downloadShare"
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in onComplete() }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
