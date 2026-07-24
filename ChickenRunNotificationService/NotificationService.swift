import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler

        guard let bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }

        self.bestAttemptContent = bestAttemptContent

        guard let imageURL = Self.imageURL(from: request.content.userInfo) else {
            contentHandler(bestAttemptContent)
            return
        }

        URLSession.shared.downloadTask(with: imageURL) { [weak self] location, _, _ in
            defer {
                contentHandler(bestAttemptContent)
            }

            guard
                let self,
                let location,
                let attachment = self.attachment(from: location, sourceURL: imageURL)
            else {
                return
            }

            bestAttemptContent.attachments = [attachment]
        }
        .resume()
    }

    override func serviceExtensionTimeWillExpire() {
        guard let contentHandler, let bestAttemptContent else { return }
        contentHandler(bestAttemptContent)
    }

    private func attachment(from location: URL, sourceURL: URL) -> UNNotificationAttachment? {
        let fileManager = FileManager.default
        let fileExtension = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let temporaryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        do {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try fileManager.removeItem(at: temporaryURL)
            }
            try fileManager.moveItem(at: location, to: temporaryURL)
            return try UNNotificationAttachment(identifier: "push-image", url: temporaryURL)
        } catch {
            return nil
        }
    }

    private static func imageURL(from userInfo: [AnyHashable: Any]) -> URL? {
        let imageKeys = ["image", "image_url", "picture", "attachment-url", "media-url"]
        for key in imageKeys {
            if
                let urlString = userInfo[key] as? String,
                let url = URL(string: urlString),
                !urlString.isEmpty
            {
                return url
            }
        }

        if
            let fcmOptions = userInfo["fcm_options"] as? [AnyHashable: Any],
            let url = imageURL(from: fcmOptions)
        {
            return url
        }

        if
            let data = userInfo["data"] as? [AnyHashable: Any],
            let url = imageURL(from: data)
        {
            return url
        }

        return nil
    }
}
