import AVFoundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor final class SubmissionScreen: ListScreen, PHPickerViewControllerDelegate {
    private let videoTitle = Theme.field("Video title")
    private let selection = Theme.label("Choose a table tennis video from Photos.", color: Theme.secondary)
    private var source: URL?
    private var consent = false
    private var saving = false
    private var preparing = false
    private var attemptID = UUID()

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Add a video"
        draw()
    }

    deinit {
        if let source { try? FileManager.default.removeItem(at: source) }
    }

    private func draw() {
        let rights = Theme.button(
            consent ? "Permission confirmed" : "I have permission to use this video", primary: consent
        ) { [weak self] in
            guard let self, !self.saving else { return }
            self.consent.toggle()
            self.draw()
        }
        let choose = Theme.button(preparing ? "Preparing video…" : "Choose video") { [weak self] in self?.pick()
        }
        choose.isEnabled = !preparing && !saving
        let submit = Theme.button(saving ? "Saving…" : "Save video", primary: true) {
            [weak self] in self?.saveVideo()
        }
        submit.isEnabled = !saving && !preparing && consent && source != nil
        videoTitle.isEnabled = !saving
        render([
            Theme.label("Save a table tennis clip up to three minutes long on this device."),
            videoTitle, selection, choose, rights, submit,
        ])
    }

    private func pick() {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        preparing = true
        draw()
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
            let copy: Result<URL, Error> = Result {
                guard let url else { throw error ?? AppFailure("The selected video could not be opened.") }
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString + "." + ext)
                try FileManager.default.copyItem(at: url, to: temporary)
                return temporary
            }
            Task { @MainActor in
                guard let self else {
                    if let url = try? copy.get() { try? FileManager.default.removeItem(at: url) }
                    return
                }
                defer {
                    self.preparing = false
                    self.draw()
                }
                do {
                    let url = try copy.get()
                    if let old = self.source { try? FileManager.default.removeItem(at: old) }
                    self.source = url
                    self.attemptID = UUID()
                    self.selection.text = "Video selected"
                } catch {
                    self.show("Video unavailable", message: error.localizedDescription)
                }
            }
        }
    }

    private func saveVideo() {
        let title = videoTitle.text?.trimmed ?? ""
        guard let source, !saving, consent else { return }
        guard (1...80).contains(title.count) else {
            show("Add a title", message: "Use 1–80 characters.")
            return
        }
        saving = true
        draw()
        let id = attemptID
        perform {
            defer {
                self.saving = false
                self.draw()
            }
            let ready = try await self.prepare(source)
            defer { try? FileManager.default.removeItem(at: ready) }
            try self.context.library.addVideo(from: ready, id: id, title: title)
            self.navigationController?.popViewController(animated: true)
        }
    }

    private func prepare(_ file: URL) async throws -> URL {
        let asset = AVURLAsset(url: file)
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, (0.01...180).contains(duration.seconds) else {
            throw AppFailure("Choose a video no longer than three minutes.")
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + ".mp4")
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset960x540) else {
            throw AppFailure("This video format could not be prepared.")
        }
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
                    continuation.resume(
                        throwing: AppFailure("The video could not be prepared within the file size limit."))
                }
            }
        }
    }
}
