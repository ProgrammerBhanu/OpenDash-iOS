import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await importSharedItems() }
    }

    private func importSharedItems() async {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let value = await load(provider: provider, type: UTType.url.identifier),
               let url = value as? URL {
                openOpenDash(with: url.absoluteString)
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let value = await load(provider: provider, type: UTType.plainText.identifier),
               let text = value as? String {
                openOpenDash(with: text)
                return
            }
        }

        finish()
    }

    private func load(provider: NSItemProvider, type: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                continuation.resume(returning: item as? NSSecureCoding)
            }
        }
    }

    private func openOpenDash(with text: String) {
        var components = URLComponents()
        components.scheme = "opendash"
        components.host = "import"
        components.queryItems = [
            URLQueryItem(name: "text", value: text)
        ]
        guard let url = components.url else {
            finish()
            return
        }
        extensionContext?.open(url) { [weak self] _ in
            self?.finish()
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
