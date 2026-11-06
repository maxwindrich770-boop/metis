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
    @State private var keyboardVisible = false
    @State private var confirmExternalNavigation = false

    var body: some View {
        ZStack {
            MetisTheme.background

            WorkspaceWebView(webView: workspace.webView)
                .accessibilityIdentifier("metis.webWorkspace")
                .accessibilityHidden(!hasLoadedWorkspace || workspace.errorMessage != nil)
                .allowsHitTesting(hasLoadedWorkspace && workspace.errorMessage == nil)

            if let error = workspace.errorMessage {
                connectionFailure(error)
            } else if !hasLoadedWorkspace {
                openingWorkspace
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if workspace.isLoading && hasLoadedWorkspace && workspace.errorMessage == nil {
                ProgressView(value: workspace.progress)
                    .progressViewStyle(.linear)
                    .tint(MetisTheme.ink)
                    .frame(height: 2)
                    .accessibilityLabel("Loading workspace")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                appMenu
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .background(MetisTheme.background)
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
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

    private var appMenu: some View {
        Menu {
            Button("iPhone settings", systemImage: "iphone") {
                showConnectionSettings()
            }

            Divider()

            Button("Reload workspace", systemImage: "arrow.clockwise") {
                workspace.retry()
            }
            .disabled(workspace.isLoading)

            Button("Back", systemImage: "chevron.left") {
                workspace.back()
            }
            .disabled(!workspace.canGoBack)

            Button("Forward", systemImage: "chevron.right") {
                workspace.forward()
            }
            .disabled(!workspace.canGoForward)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis")
                    .accessibilityHidden(true)
                Text("App")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(MetisTheme.muted)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(MetisTheme.secondary, in: Capsule())
            .frame(minWidth: 80, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(MetisIconButtonStyle())
        .accessibilityLabel("App controls")
        .accessibilityIdentifier("metis.appMenu")
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

private struct WorkspacePresentation: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

@MainActor
private struct WorkspaceWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
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
