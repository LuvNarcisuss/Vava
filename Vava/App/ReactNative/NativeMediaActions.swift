import AVFoundation
import PhotosUI
import SafariServices
import UIKit
import UniformTypeIdentifiers

@MainActor final class NativeMediaActions: NSObject, PHPickerViewControllerDelegate {
    private var selection: CheckedContinuation<[PHPickerResult], Error>?
    private var sharing: CheckedContinuation<Bool, Error>?
    private weak var presentedController: UIViewController?
    private var busy = false

    func invalidate() {
        let pendingSelection = selection
        let pendingShare = sharing
        selection = nil
        sharing = nil
        presentedController?.dismiss(animated: false)
        presentedController = nil
        pendingSelection?.resume(throwing: CancellationError())
        pendingShare?.resume(throwing: CancellationError())
    }

    private func presenter() throws -> UIViewController {
        let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        let sceneRoot = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        let applicationRoot = (UIApplication.shared.delegate as? VavaApplication)?.window?.rootViewController
        guard var controller = sceneRoot ?? applicationRoot else {
            throw AppFailure("This action is unavailable right now.")
        }
        while let presented = controller.presentedViewController { controller = presented }
        guard !controller.isBeingDismissed else { throw AppFailure("Please try again.") }
        return controller
    }

    func openURL(_ value: String) throws {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            throw AppFailure("This link is unavailable.")
        }
        try presenter().present(SFSafariViewController(url: url), animated: true)
    }

    private func select(_ filter: PHPickerFilter) async throws -> [PHPickerResult] {
        guard !busy, sharing == nil else { throw AppFailure("Finish choosing your media first.") }
        busy = true
        defer { busy = false }
        let host = try presenter()
        var configuration = PHPickerConfiguration()
        configuration.filter = filter
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        return try await withCheckedThrowingContinuation { continuation in
            selection = continuation
            presentedController = picker
            host.present(picker, animated: true)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let pending = selection
        selection = nil
        presentedController = nil
        picker.dismiss(animated: true) { pending?.resume(returning: results) }
    }

    func pickAvatar() async throws -> Data? {
        guard let provider = try await select(.images).first?.itemProvider else { return nil }
        let image: UIImage = try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, error in
                guard let image = object as? UIImage else {
                    continuation.resume(throwing: error ?? AppFailure("This photo could not be opened."))
                    return
                }
                continuation.resume(returning: image)
            }
        }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { throw AppFailure("This photo could not be opened.") }
        let scale = min(1, 512 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = scaled.jpegData(compressionQuality: 0.82) else {
            throw AppFailure("This photo could not be saved.")
        }
        return data
    }

    func pickVideo() async throws -> URL? {
        guard let provider = try await select(.videos).first?.itemProvider else { return nil }
        let source: URL = try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                do {
                    guard let url else { throw error ?? AppFailure("This video could not be opened.") }
                    let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch { continuation.resume(throwing: error) }
            }
        }
        defer { try? FileManager.default.removeItem(at: source) }
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, (0.01...180).contains(duration.seconds),
              !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw AppFailure("Choose a video no longer than three minutes.")
        }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset960x540) else {
            throw AppFailure("This video format could not be prepared.")
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        export.outputURL = destination
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        return try await withCheckedThrowingContinuation { continuation in
            export.exportAsynchronously {
                let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if export.status == .completed, (1...50_000_000).contains(size) {
                    continuation.resume(returning: destination)
                } else {
                    try? FileManager.default.removeItem(at: destination)
                    continuation.resume(throwing: AppFailure("The video could not be prepared within the file size limit."))
                }
            }
        }
    }

    func share(_ items: [Any]) async throws -> Bool {
        guard !busy, sharing == nil else { throw AppFailure("Finish the current action first.") }
        guard !items.isEmpty else { throw AppFailure("There is nothing to share.") }
        let host = try presenter()
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = host.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1)
        return try await withCheckedThrowingContinuation { continuation in
            sharing = continuation
            presentedController = controller
            controller.completionWithItemsHandler = { [weak self] _, completed, _, error in
                guard let self, let pending = self.sharing else { return }
                self.sharing = nil
                self.presentedController = nil
                if let error { pending.resume(throwing: error) }
                else { pending.resume(returning: completed) }
            }
            host.present(controller, animated: true)
        }
    }
}
