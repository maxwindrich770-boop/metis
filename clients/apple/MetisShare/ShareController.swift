import SwiftUI
import UniformTypeIdentifiers

final class ShareController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let provider = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] }
            .first { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) ||
                $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
        let host = UIHostingController(rootView: SharePreview(provider: provider) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        view.addSubview(host.view)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: self)
    }
}

private struct SharePreview: View {
    let provider: NSItemProvider?
    let finish: () -> Void
    @State private var text = ""
    @State private var status: String?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                if !text.isEmpty {
                    Section("Shared text") { Text(verbatim: text) }
                }
                if let status { Text(status) }
                if !text.isEmpty && !saved {
                    Button("Save draft in Metis") {
                        do {
                            try SharedPrompt.save(text)
                            saved = true
                            status = "Open Metis to choose a chat and send."
                        } catch { status = error.localizedDescription }
                    }
                }
            }
            .navigationTitle("Share to Metis")
            .toolbar { Button(saved ? "Done" : "Close", action: finish) }
            .task { await load() }
        }
    }

    private func load() async {
        guard let provider else { status = "Choose one link or a piece of text."; return }
        let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url : UTType.plainText
        do {
            let result: String? = try await withCheckedThrowingContinuation { continuation in
                provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                    if let error { continuation.resume(throwing: error); return }
                    if let url = item as? URL, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(returning: item as? String)
                    }
                }
            }
            guard let result = result?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !result.isEmpty, result.count <= 16_000, result.utf8.count <= 64_000 else {
                status = "Choose a web link or up to 16,000 characters of text."
                return
            }
            text = result
        } catch { status = "The share could not be read." }
    }
}
