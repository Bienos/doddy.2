import DoddyDesignTokens
import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// The expanded paper notification (ADR-343): when the user long-presses a note reminder or a
/// "thought to review" notification, iOS shows this instead of the plain expanded banner: the
/// same title and words on Doddy's paper, with his picture when the notification carries one.
/// The actions come from the notification's category, as before. This extension shows only what
/// is in the notification it was handed: it opens no database, has no App Group, no network and
/// no permissions, and changes nothing. The unexpanded banner is unchanged.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let model = ExpandedNotificationModel()
    private var host: UIHostingController<ExpandedNotificationView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ExpandedNotificationView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
        self.host = host
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        var image: UIImage?
        // The pose picture the app attached (ADR-313), if any; nothing else is read.
        if let attachment = content.attachments.first, attachment.url.startAccessingSecurityScopedResource() {
            defer { attachment.url.stopAccessingSecurityScopedResource() }
            image = UIImage(contentsOfFile: attachment.url.path)
        }
        model.show(eyebrow: Self.eyebrow(for: content.categoryIdentifier), title: content.title, body: content.body, image: image)
        let width = view.bounds.width > 0 ? view.bounds.width : 360
        let fitted = host?.sizeThatFits(in: CGSize(width: width, height: UIView.layoutFittingExpandedSize.height))
        preferredContentSize = CGSize(width: width, height: max(96, fitted?.height ?? 140))
    }

    /// The small label above the title, by the category the app set. Unknown categories (none
    /// are listed for this extension) say only "Doddy".
    static func eyebrow(for category: String) -> String {
        switch category {
        case "DODDY_NOTE_REMINDER": NSLocalizedString("Note reminder", comment: "")
        case "DODDY_NOTE_REPEATING_REMINDER": NSLocalizedString("Repeating reminder", comment: "")
        case "DODDY_NOTE_PLACE_REMINDER": NSLocalizedString("At a place", comment: "")
        case "DODDY_THOUGHT_REVIEW": NSLocalizedString("A thought to review", comment: "")
        default: "Doddy"
        }
    }
}

@MainActor
@Observable
final class ExpandedNotificationModel {
    private(set) var eyebrow = ""
    private(set) var title = ""
    private(set) var body = ""
    private(set) var image: UIImage?

    func show(eyebrow: String, title: String, body: String, image: UIImage?) {
        self.eyebrow = eyebrow
        self.title = title
        self.body = body
        self.image = image
    }
}

/// Doddy's paper card: the colours of the app's own cards, following the iPhone's appearance.
struct ExpandedNotificationView: View {
    let model: ExpandedNotificationModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let image = model.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 88)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(model.eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(paper(.secondaryText))
                Text(model.title)
                    .font(.headline)
                    .foregroundStyle(paper(.readingInk))
                Text(model.body)
                    .font(.body)
                    .foregroundStyle(paper(.readingInk))
                    .fixedSize(horizontal: false, vertical: true)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(paper(.orangeCue))
                    .frame(width: 36, height: 3)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paper(.canvas))
    }

    private func paper(_ role: UploadedColorRole) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = role.hex(traits.userInterfaceStyle == .dark ? .dark : .light)
            return UIColor(red: CGFloat(hex.red) / 255, green: CGFloat(hex.green) / 255, blue: CGFloat(hex.blue) / 255, alpha: 1)
        })
    }
}
