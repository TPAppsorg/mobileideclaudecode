import SwiftUI
import UIKit
import LinkPresentation

struct ShareItem: Identifiable {
    var id: String { url.absoluteString }
    let url: URL
}

class LinkMetadataProvider: NSObject, UIActivityItemSource {
    let url: URL
    let title: String
    let subtitle: String

    init(url: URL, title: String, subtitle: String) {
        self.url = url
        self.title = title
        self.subtitle = subtitle
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return url.absoluteString
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return url.absoluteString
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title
        // Subtitle is often derived from the URL or handled by the system,
        // but we can try to influence it or just set a clear title.
        return metadata
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    let title: String
    let subtitle: String
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let provider = LinkMetadataProvider(url: url, title: title, subtitle: subtitle)
        let controller = UIActivityViewController(
            activityItems: [provider],
            applicationActivities: applicationActivities
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
