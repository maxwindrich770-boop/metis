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
            WorkspaceAppControls(workspace: workspace) {
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

                Text("iPhone controls")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

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
        html[data-metis-native-app="ios"]:has([data-metis-app-composer-dock]),
        html[data-metis-native-app="ios"]:has([data-metis-app-composer-dock]) body,
        html[data-metis-native-app="ios"]:has(aside[aria-label="Chats sidebar"].visible:not([hidden])),
        html[data-metis-native-app="ios"]:has(aside[aria-label="Chats sidebar"].visible:not([hidden])) body {
          height: 100%;
          overflow: clip;
        }
        /* Sonner is fixed to the window, outside the shell's status-bar inset.
           Retain its own gap and add the live cutout inset only in the app. */
        html:has(#metis-native-app-style) [data-sonner-toaster][data-y-position="top"] {
          top: calc(env(safe-area-inset-top, 0px) + var(--offset-top, 32px)) !important;
        }
        @media (max-width: 600px) {
          html:has(#metis-native-app-style) [data-sonner-toaster][data-y-position="top"] {
            top: calc(env(safe-area-inset-top, 0px) + var(--mobile-offset-top, 16px)) !important;
          }
        }
        html[data-metis-native-app="ios"] .metis-shell {
          box-sizing: border-box;
          padding-top: env(safe-area-inset-top);
        }
        html[data-metis-native-app="ios"] .metis-shell:has([data-metis-app-composer-dock]) {
          height: var(--metis-app-window-height, 100dvh) !important;
        }
        @media (max-width: 639px) {
          html[data-metis-native-app="ios"] .metis-shell [class~="pb-[10svh]"] {
            padding-bottom: calc(var(--metis-app-window-height, 100svh) * 0.1) !important;
          }
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
          height: var(--metis-app-window-height, 100dvh);
          bottom: auto;
        }
        /* The canonical drawer toggles visibility with its translate class.
           Delay hiding until that slide ends; reopening is visible immediately.
           Tailwind's duration token keeps both transitions in sync. */
        @media (max-width: 767px) {
          html[data-metis-native-app="ios"] aside[aria-label="Chats sidebar"] {
            transition-property: transform, translate, visibility;
            transition-duration: var(--tw-duration, 200ms), var(--tw-duration, 200ms), 0s;
            transition-delay: 0s, 0s, var(--tw-duration, 200ms);
          }
          html[data-metis-native-app="ios"] aside[aria-label="Chats sidebar"].visible {
            transition-delay: 0s;
          }
          html[data-metis-native-app="ios"] aside[aria-label="Chats sidebar"].invisible {
            pointer-events: none;
          }
        }
        /* Each quota window owns its value; omit the repeated header summary. */
        html[data-metis-native-app="ios"] [data-metis-app-usage] > div > .items-start > span {
          display: none;
        }
        /* Keep heading-to-window and window-to-window spacing equally readable. */
        html[data-metis-native-app="ios"] [data-metis-app-usage] > div > :not(:first-child) {
          margin-block-start: 12px;
        }
        /* Preserve Radix's 8-point collision gutter; landscape stays compact. */
        @media (orientation: portrait) and (max-width: 767px) {
          html[data-metis-native-app="ios"] [data-metis-app-usage] {
            width: calc(100vw - 16px);
            max-width: calc(100vw - 16px);
            box-sizing: border-box;
            text-align: center;
            justify-content: center;
          }
          html[data-metis-native-app="ios"] [data-metis-app-usage] > div {
            width: 100%;
          }
          html[data-metis-native-app="ios"] [data-metis-app-usage] .flex {
            justify-content: center;
            gap: 0.5rem;
          }
          html[data-metis-native-app="ios"] [data-metis-app-usage] .items-start {
            flex-direction: column;
            align-items: center;
          }
        }
        /* Match the content gutters inside the system-safe area. */
        html[data-metis-native-app="ios"] aside[aria-label="Chats sidebar"] [aria-label="Metis"]:not([role="img"]) {
          padding-top: var(--metis-app-sidebar-gutter);
          padding-bottom: var(--metis-app-sidebar-gutter);
        }
        html[data-metis-native-app="ios"] [data-metis-app-sidebar-footer] {
          padding-bottom: calc(var(--metis-app-sidebar-gutter) + var(--metis-app-home-inset, env(safe-area-inset-bottom)));
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
        html[data-metis-native-app="ios"] input[role="combobox"][aria-controls="palette-results"] {
          font-size: max(16px, 1rem);
        }
        @media (max-width: 639px) {
          html[data-metis-native-app="ios"] [data-slot="dialog-content"]:has(input[aria-controls="palette-results"]) {
            top: calc(var(--metis-app-window-height, 100dvh) * 0.14) !important;
          }
          html[data-metis-native-app="ios"] [data-slot="dialog-content"]:has(input[aria-controls="palette-results"]) #palette-results {
            max-height: max(0px, min(60dvh, 420px, calc(100dvh - var(--metis-app-window-height, 100dvh) * 0.14 - 4rem)));
          }
        }
        /* A readable minimum prevents WebKit's focus zoom without
           constraining deliberate pinch or text scaling. */
        html[data-metis-native-app="ios"] .composer-input-area,
        html[data-metis-native-app="ios"] .composer-input-area textarea,
        html[data-metis-native-app="ios"] .composer-input-area [contenteditable="true"] {
          font-size: max(16px, 1rem);
        }
        /* Inline editing owns the keyboard and the visible transcript.
           Hide (don't unmount) the dock so the separate unsent draft survives. */
        html[data-metis-native-app="ios"] .metis-shell article textarea[aria-label="Edit message"] {
          font-size: max(16px, 1rem);
          min-width: 0;
          max-width: 100%;
        }
        html[data-metis-native-app="ios"] .metis-shell:has(article textarea[aria-label="Edit message"]) [data-metis-app-composer-dock] {
          visibility: hidden;
        }
        /* Add scroll range below the messages without resizing the transcript.
           Resizing it can move an editor that the keyboard never covered. */
        html[data-metis-native-app="ios"] .metis-shell [class~="overflow-y-auto"]:has(article textarea[aria-label="Edit message"])::after {
          content: "";
          display: block;
          flex: none;
          height: var(--metis-app-edit-scroll-space, 0px);
          pointer-events: none;
        }
        /* UIKit already removes the keyboard from the web viewport. The
           server's transient visualViewport bottom offset must not remove it twice. */
        html[data-metis-native-app="ios"] [data-metis-app-composer-dock] {
          bottom: 0 !important;
          transform: translateY(var(--metis-app-composer-shift, 0px));
        }
        html[data-metis-native-app="ios"] [data-metis-app-empty-greeting] {
          transform: translateY(var(--metis-app-greeting-shift, 0px));
        }
        /* Keep the same footprint and pane alignment through focus/blur.
           The empty greeting follows its editor; message transcripts stay put. */
        html[data-metis-native-app="ios"] [data-metis-app-empty-dock] {
          position: relative !important;
          top: auto !important;
          left: auto !important;
          right: auto !important;
        }
        html[data-metis-native-app="ios"] [data-metis-app-composer-dock]:not([data-metis-app-empty-dock]) {
          position: absolute !important;
        }
        html[data-metis-native-app="ios"] [data-metis-app-keyboard-spacer] {
          flex: none;
          height: max(0px, max(0.25rem, var(--metis-app-home-inset, env(safe-area-inset-bottom))) - max(0.25rem, env(safe-area-inset-bottom)));
          pointer-events: none;
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
          html[data-metis-native-app="ios"] aside[aria-label="Chats sidebar"],
          html[data-metis-native-app="ios"] [data-metis-app-controls] {
            transition: none;
          }
        }
      `;
      document.head.append(style);

      const dockGreetings = new WeakMap();
      const clearGreetingShift = dock => {
        const greeting = dockGreetings.get(dock);
        if (greeting) {
          delete greeting.dataset.metisAppEmptyGreeting;
          greeting.style.removeProperty('--metis-app-greeting-shift');
          dockGreetings.delete(dock);
        }
      };
      const updateGreetingShift = (dock, shift) => {
        const candidate = dock.hasAttribute('data-metis-app-empty-dock') ? dock.previousElementSibling : null;
        const greeting = candidate && (candidate.matches('h2') || candidate.querySelector(':scope > h2'))
          ? candidate : null;
        if (dockGreetings.get(dock) !== greeting) {
          clearGreetingShift(dock);
          if (greeting) dockGreetings.set(dock, greeting);
        }
        if (greeting) {
          greeting.dataset.metisAppEmptyGreeting = '';
          greeting.style.setProperty('--metis-app-greeting-shift', shift + 'px');
        }
      };
      const inlineEditorSelector = '.metis-shell article textarea[aria-label="Edit message"]';
      let inlineEditLayout = null;
      const updateInlineEditLayout = (keyboardInset, refocus = false) => {
        const editor = document.querySelector(inlineEditorSelector);
        const transcript = editor?.closest('[class~="overflow-y-auto"]');
        if (inlineEditLayout && inlineEditLayout.transcript !== transcript) {
          inlineEditLayout.transcript.style.removeProperty('--metis-app-edit-scroll-space');
          inlineEditLayout = null;
        }
        if (!transcript) return;
        if (!refocus && inlineEditLayout?.editor === editor && inlineEditLayout.keyboardInset === keyboardInset &&
            inlineEditLayout.width === innerWidth && inlineEditLayout.height === innerHeight) return;

        inlineEditLayout = { editor, transcript, keyboardInset, width: innerWidth, height: innerHeight };
        const viewport = transcript.getBoundingClientRect();
        const bottom = Math.min(viewport.bottom, innerHeight);
        const scrollSpace = keyboardInset > 0 ? Math.max(0, viewport.bottom - bottom) : 0;
        if (scrollSpace > 0) {
          transcript.style.setProperty('--metis-app-edit-scroll-space', scrollSpace + 'px');
        } else {
          transcript.style.removeProperty('--metis-app-edit-scroll-space');
        }

        // If the keyboard clears the editor, preserve the exact position.
        // Otherwise scroll just enough to reveal the editor and its actions.
        const panel = editor.parentElement.getBoundingClientRect();
        const top = viewport.top;
        if (bottom <= top || !panel.height || (panel.top >= top && panel.bottom <= bottom)) return;
        const shift = panel.height > bottom - top || panel.top < top
          ? panel.top - top : panel.bottom - bottom;
        if (Math.abs(shift) > 1) transcript.scrollTop += shift;
      };
      // Keep the empty welcome group together when a full keyboard occludes
      // its editor. Message transcripts retain their full-height layout.
      // This measures geometry only; no heading text or chat values are read.
      const updateComposerLayout = () => {
        const fullHeight = parseFloat(getComputedStyle(document.documentElement)
          .getPropertyValue('--metis-app-window-height')) || innerHeight;
        const keyboardVisible = fullHeight > innerHeight + 1;
        updateInlineEditLayout(keyboardVisible ? fullHeight - innerHeight : 0);
        for (const dock of document.querySelectorAll('[data-metis-app-composer-dock]')) {
          const previous = parseFloat(dock.style.getPropertyValue('--metis-app-composer-shift')) || 0;
          const reservedInset = dockSpacers.get(dock)?.getBoundingClientRect().height || 0;
          const bottomInFlow = dock.getBoundingClientRect().bottom - previous - reservedInset;
          const next = keyboardVisible ? Math.min(0, innerHeight - bottomInFlow) : 0;
          const applied = Math.abs(next - previous) > 0.25 ? next : previous;
          if (applied !== previous) dock.style.setProperty('--metis-app-composer-shift', applied + 'px');
          updateGreetingShift(dock, applied);
        }
      };
      const composerResizeObserver = new ResizeObserver(updateComposerLayout);
      const observedDocks = new Set();
      const dockSpacers = new WeakMap();
      window.addEventListener('resize', updateComposerLayout);
      window.visualViewport?.addEventListener('resize', updateComposerLayout);
      document.addEventListener('metis-native-layout', updateComposerLayout);
      document.addEventListener('focusin', event => {
        if (!event.target.matches?.(inlineEditorSelector)) return;
        requestAnimationFrame(() => {
          if (document.activeElement !== event.target) return;
          const fullHeight = parseFloat(getComputedStyle(document.documentElement)
            .getPropertyValue('--metis-app-window-height')) || innerHeight;
          updateInlineEditLayout(Math.max(0, fullHeight - innerHeight), true);
        });
      });

      let lastUpdatePending = null;
      const announceUpdate = () => {
        let pending = Boolean(document.querySelector('[data-metis-installer-maintenance]'));
        try { pending ||= Boolean(localStorage.getItem('metis-update-job')); } catch {}
        if (pending === lastUpdatePending) return;
        lastUpdatePending = pending;
        window.webkit?.messageHandlers?.metisAppControls?.postMessage(pending ? 'update-active' : 'update-inactive');
      };
      window.addEventListener('metis:installer-maintenance', () => {
        lastUpdatePending = true;
        window.webkit?.messageHandlers?.metisAppControls?.postMessage('update-active');
      });
      new MutationObserver(announceUpdate).observe(document.documentElement, { childList: true, subtree: true });
      announceUpdate();

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
        // Follow the accessible tooltip relationship, independent of provider
        // name and quota values. Context and unrelated tips stay untouched.
        for (const trigger of document.querySelectorAll('button[aria-describedby]')) {
          const label = trigger.getAttribute('aria-label') || '';
          if (!label.includes(' usage:') && !label.endsWith(' usage unavailable')) continue;
          for (const id of trigger.getAttribute('aria-describedby').split(/\s+/)) {
            const surface = document.getElementById(id)?.closest('[data-slot="tooltip-content"]');
            if (surface && !surface.hasAttribute('data-metis-app-usage')) surface.dataset.metisAppUsage = '';
          }
        }
        for (const input of document.querySelectorAll('.composer-input-area')) {
          const form = input.closest('form');
          if (form && !form.hasAttribute('data-metis-app-composer')) form.dataset.metisAppComposer = '';
          const dock = form?.closest('[class~="pointer-events-none"][class~="z-20"][class~="w-full"]');
          if (dock && !dock.hasAttribute('data-metis-app-composer-dock')) {
            dock.dataset.metisAppComposerDock = '';
            composerResizeObserver.observe(dock);
            observedDocks.add(dock);
          }
          if (dock) {
            let spacer = dockSpacers.get(dock);
            if (!spacer?.isConnected) {
              spacer = document.createElement('div');
              spacer.dataset.metisAppKeyboardSpacer = '';
              spacer.setAttribute('aria-hidden', 'true');
              dockSpacers.set(dock, spacer);
            }
            // Keep the measured dock height unchanged when WebKit removes its
            // Home inset. The translated, clipped spacer is not a visible gap.
            if (dock.lastElementChild !== spacer) dock.append(spacer);
            if (dock.classList.contains('relative')) {
              dock.dataset.metisAppEmptyDock = '';
            } else if (dock.hasAttribute('data-metis-app-empty-dock')) {
              delete dock.dataset.metisAppEmptyDock;
              dock.style.removeProperty('--metis-app-composer-shift');
            }
          }
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
        for (const dock of observedDocks) {
          if (!dock.isConnected) {
            clearGreetingShift(dock);
            composerResizeObserver.unobserve(dock);
            observedDocks.delete(dock);
            dockSpacers.get(dock)?.remove();
            dockSpacers.delete(dock);
          }
        }
        updateComposerLayout();
        announceAvailability(Boolean(document.querySelector('[data-metis-app-controls]')));
      };

      // Project note buttons select a note without updating older servers' route.
      // Keep that selection while leaving the project route before React handles
      // the click; otherwise its route effect immediately restores the project.
      document.addEventListener('click', event => {
        if (!event.isTrusted || event.defaultPrevented || !(event.target instanceof Element)) return;
        const button = event.target.closest('[data-slot="project-home-notes"] button');
        if (!button || button.matches(':disabled, [aria-disabled="true"]')) return;
        const destination = new URL(window.location.href);
        if (destination.searchParams.get('c') === 'notes') return;
        destination.searchParams.set('c', 'notes');
        destination.searchParams.delete('view');
        history.pushState(history.state, '', destination);
        window.dispatchEvent(new PopStateEvent('popstate', { state: history.state }));
      }, true);

      const mobileSidebarClose = sidebar => {
        if (!sidebar?.isConnected || !matchMedia('(max-width: 767px)').matches) return null;
        const close = Array.from(sidebar.parentElement?.children || [])
          .find(element => element.matches('button[aria-label="Close sidebar"]'));
        return close && close.tabIndex >= 0 ? close : null;
      };
      document.addEventListener('click', event => {
        if (!event.isTrusted || !(event.target instanceof Element)) return;
        const button = event.target.closest('button, a[href]');
        const sidebar = button?.closest('aside[aria-label="Chats sidebar"]');
        if (!sidebar || button.matches(':disabled, [aria-disabled="true"]')) return;
        const navigation = sidebar.querySelector('.metis-sidebar-scroll')?.previousElementSibling;
        const label = button.getAttribute('aria-label');
        // Expanders, filters and action menus retain their intermediate state.
        // Search keeps the drawer until a result is selected; creation dialogs close it.
        const destination = (button.parentElement === navigation && !button.querySelector('kbd')) ||
          button.matches('a[href], button[title]:not([aria-haspopup]):not([aria-expanded])') ||
          Boolean(button.closest('section[aria-label="Project agents"]') && button.classList.contains('flex-1')) ||
          ['New project', 'New chat', 'New chat in project', 'New agent'].includes(label);
        if (!destination) return;
        // Let the original action select its content before closing its drawer.
        setTimeout(() => {
          if (!event.defaultPrevented) mobileSidebarClose(sidebar)?.click();
        }, 0);
      }, true);

      // Accept swipes over chat buttons as well as empty drawer space and its
      // backdrop. Main-pane gestures and editable/menu controls stay untouched.
      let drawerSwipe = null;
      const selectedText = () => {
        const selection = window.getSelection();
        return selection && !selection.isCollapsed && selection.toString().trim();
      };
      document.addEventListener('touchstart', event => {
        drawerSwipe = null;
        if (!event.isTrusted || event.touches.length !== 1 ||
            !(event.target instanceof Element) || selectedText()) return;
        const sidebar = document.querySelector('aside[aria-label="Chats sidebar"]');
        const close = mobileSidebarClose(sidebar);
        if (!close || (!sidebar.contains(event.target) && !close.contains(event.target)) ||
            event.target.closest('input, textarea, select, [contenteditable="true"], [data-swipe-ignore], [role="slider"], [role="menu"], [role="dialog"]')) return;
        const touch = event.touches[0];
        drawerSwipe = { sidebar, id: touch.identifier, x: touch.clientX, y: touch.clientY };
      }, { capture: true, passive: true });
      document.addEventListener('touchmove', event => {
        if (!drawerSwipe) return;
        const touch = Array.from(event.touches).find(item => item.identifier === drawerSwipe.id);
        if (event.touches.length !== 1 || !touch ||
            (Math.abs(touch.clientY - drawerSwipe.y) > 12 &&
             Math.abs(touch.clientY - drawerSwipe.y) > Math.abs(touch.clientX - drawerSwipe.x))) drawerSwipe = null;
      }, { capture: true, passive: true });
      document.addEventListener('touchcancel', () => { drawerSwipe = null; }, { passive: true });
      document.addEventListener('touchend', event => {
        const start = drawerSwipe;
        drawerSwipe = null;
        if (!event.isTrusted || !start || event.touches.length || selectedText()) return;
        const touch = Array.from(event.changedTouches).find(item => item.identifier === start.id);
        if (!touch) return;
        const dx = touch.clientX - start.x, dy = touch.clientY - start.y;
        const close = mobileSidebarClose(start.sidebar);
        if (!close || dx > -64 || Math.abs(dx) < Math.abs(dy) * 1.35) return;
        event.preventDefault();
        event.stopPropagation();
        close.click();
      }, { capture: true, passive: false });

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
      observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['aria-describedby'] });
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
    private var keyboardTransitionUntil: CFTimeInterval = 0
    private var publishedWindowSize: CGSize = .zero
    private var nativeFullWindowLayoutActive = false
    #if DEBUG && targetEnvironment(simulator)
    private let syntheticInputOcclusion: UILabel? = {
        guard ProcessInfo.processInfo.arguments.contains("-metis.synthetic-input-occlusion") else { return nil }
        let panel = UILabel()
        panel.accessibilityIdentifier = "metis.syntheticInputOcclusion"
        panel.text = "Synthetic input occlusion — not the system keyboard"
        panel.font = .preferredFont(forTextStyle: .caption1)
        panel.textAlignment = .center
        panel.numberOfLines = 0
        panel.backgroundColor = .secondarySystemBackground
        panel.isAccessibilityElement = true
        panel.isUserInteractionEnabled = false
        panel.isHidden = true
        return panel
    }()
    #endif


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
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        webView.accessibilityIdentifier = "metis.webWorkspace"
        addSubview(webView)
        #if DEBUG && targetEnvironment(simulator)
        if let panel = syntheticInputOcclusion { addSubview(panel) }
        #endif
        // UIKit/WebKit view geometry changes occur on the main thread. Observe
        // the web process's later content-size/offset update, not just our frame.
        viewportScrollObservations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated {
                    if view.isLoading { self?.nativeFullWindowLayoutActive = false }
                    else { self?.publishWindowGeometry(force: true) }
                }
            },
            webView.scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reconcileViewportFocusScroll() }
            },
            webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reconcileViewportFocusScroll() }
            },
        ]
    }

    required init?(coder: NSCoder) { return nil }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard window != nil else { return }
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
        keyboardTransitionUntil = CACurrentMediaTime() + max(0, duration)
        viewportFocusScrollPending = true
        publishWindowGeometry(force: true)
        reconcileViewportFocusScroll()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { finishViewportFocusScroll() }
        else { publishWindowGeometry(force: true) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var viewport = viewportGuide.layoutFrame
        #if DEBUG && targetEnvironment(simulator)
        // A public, explicitly synthetic test surface exercises a full-sized
        // occlusion even when Simulator exposes only the system accessory.
        if let panel = syntheticInputOcclusion, let window {
            let fullWindow = convert(window.bounds, from: window)
            let inputVisible = viewport.maxY < fullWindow.maxY - 1
            let height: CGFloat = inputVisible ? min(360, fullWindow.height) : 0
            panel.frame = CGRect(x: viewport.minX, y: fullWindow.maxY - height,
                                 width: viewport.width, height: height)
            panel.isHidden = !inputVisible
            if inputVisible { viewport.size.height = max(0, min(viewport.maxY, panel.frame.minY) - viewport.minY) }
        }
        #endif
        publishWindowGeometry()
        guard webView.frame != viewport else {
            reconcileViewportFocusScroll()
            return
        }
        if abs(webView.frame.width - viewport.width) > 0.5 {
            finishViewportFocusScroll()
        } else if webView.frame.height > 0,
                  abs(viewport.height - webView.frame.height) > 0.5 {
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

    private func publishWindowGeometry(force: Bool = false) {
        guard let window else { return }
        let fullWindow = convert(window.bounds, from: window)
        guard fullWindow.width > 0, fullWindow.height > 0,
              force || fullWindow.size != publishedWindowSize else { return }
        publishedWindowSize = fullWindow.size
        // Numeric presentation geometry only. The stylesheet is scoped to the
        // decorated first-party shell, and is refreshed after each navigation.
        let height = Double(fullWindow.height)
        let homeInset = Double(window.safeAreaInsets.bottom)
        let page = webView.url
        webView.evaluateJavaScript("""
          document.documentElement?.style.setProperty('--metis-app-window-height', '\(height)px');
          document.documentElement?.style.setProperty('--metis-app-home-inset', '\(homeInset)px');
          document.dispatchEvent(new Event('metis-native-layout'));
          (() => {
            if (document.querySelector('html[data-metis-native-app="ios"] .metis-shell [data-metis-app-composer-dock]')) return true;
            const sidebar = document.querySelector('html[data-metis-native-app="ios"] aside[aria-label="Chats sidebar"]');
            if (!sidebar || getComputedStyle(sidebar).visibility === 'hidden') return false;
            const rect = sidebar.getBoundingClientRect();
            return rect.width > 0 && rect.right > 0 && rect.left < innerWidth;
          })();
          """) { [weak self] value, _ in
            guard let self, self.webView.url == page, !self.webView.isLoading else { return }
            self.nativeFullWindowLayoutActive = value as? Bool == true
            self.reconcileViewportFocusScroll()
        }
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
        // A clipped chat shell or visible mobile drawer retains the full window
        // height while its visible viewport is shorter, with no legitimate root scroll
        // range. Other pages must fit the visible viewport; longer documents,
        // custom insets, and deliberate zoom retain WebKit behavior.
        guard scroll.contentInset == .zero, scroll.adjustedContentInset == .zero,
              scroll.contentSize.width <= scroll.bounds.width + 0.5,
              scroll.contentSize.height <= (nativeFullWindowLayoutActive ? publishedWindowSize.height : scroll.bounds.height) + 0.5 else { return }
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
        // A dismissal can outlast WebKit's initial offset clamp. Continue
        // through the keyboard's reported transition in either direction,
        // then allow two display frames for the web process to settle.
        if CACurrentMediaTime() < keyboardTransitionUntil {
            viewportFocusScrollFrames = 2
        } else {
            viewportFocusScrollFrames -= 1
            if viewportFocusScrollFrames <= 0 { finishViewportFocusScroll() }
        }
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
