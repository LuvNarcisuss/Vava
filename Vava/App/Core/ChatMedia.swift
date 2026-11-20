import AVFoundation
import CoreImage
import ImageIO
import UIKit

@MainActor final class ChatMedia {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    private let camera = ChatCamera()
    private let sendAudio: (Data) -> Void
    private let sendVideo: (Data) -> Void
    private let renderVideo: (UIImage) -> Void
    private let interrupted: () -> Void
    private var interruptionObserver: NSObjectProtocol?
    private var tapInstalled = false
    private var running = false
    private var queued = 0
    var muted = false

    init(
        sendAudio: @escaping (Data) -> Void, sendVideo: @escaping (Data) -> Void,
        renderVideo: @escaping (UIImage) -> Void, interrupted: @escaping () -> Void
    ) {
        self.sendAudio = sendAudio
        self.sendVideo = sendVideo
        self.renderVideo = renderVideo
        self.interrupted = interrupted
    }

    func start(video: Bool) async throws {
        let audioSession = AVAudioSession.sharedInstance()
        let microphoneAllowed = await Self.requestMicrophoneAccess()
        guard microphoneAllowed else { throw AppFailure("Allow microphone access to join the call.") }
        if video, !(await AVCaptureDevice.requestAccess(for: .video)) {
            throw AppFailure("Allow camera access to join the video call.")
        }
        try Task.checkCancellation()
        try audioSession.setCategory(
            .playAndRecord, mode: video ? .videoChat : .voiceChat, options: [.defaultToSpeaker])
        try audioSession.setActive(true)
        do {
            let input = engine.inputNode
            try input.setVoiceProcessingEnabled(true)
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
                let encoder = AVAudioConverter(from: inputFormat, to: format)
            else { throw AppFailure("The microphone is unavailable.") }

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            let packetFormat = format
            input.installTap(onBus: 0, bufferSize: 960, format: inputFormat) { [weak self] buffer, _ in
                let ratio = packetFormat.sampleRate / buffer.format.sampleRate
                let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
                guard let converted = AVAudioPCMBuffer(pcmFormat: packetFormat, frameCapacity: capacity)
                else { return }
                var supplied = false
                var error: NSError?
                let result = encoder.convert(to: converted, error: &error) { _, status in
                    status.pointee = supplied ? .noDataNow : .haveData
                    defer { supplied = true }
                    return supplied ? nil : buffer
                }
                guard error == nil, result != .error, let samples = converted.floatChannelData?[0],
                    (1...4096).contains(converted.frameLength)
                else { return }
                let count = Int(converted.frameLength)
                var pcm = [Int16](repeating: 0, count: count)
                for index in 0..<count {
                    let sample = samples[index]
                    if sample.isFinite { pcm[index] = Int16(max(-1, min(1, sample)) * Float(Int16.max)) }
                }
                let data = pcm.withUnsafeBytes { Data($0) }
                Task { @MainActor [weak self] in
                    guard let self, self.running, !self.muted else { return }
                    self.sendAudio(data)
                }
            }
            tapInstalled = true
            try engine.start()
            player.play()
            running = true
            if video {
                try await camera.start { [weak self] frame in
                    Task { @MainActor [weak self] in
                        guard let self, self.running else { return }
                        self.sendVideo(frame)
                    }
                }
                try Task.checkCancellation()
            }
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: audioSession, queue: .main
            ) { [weak self] note in
                guard
                    note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                        == AVAudioSession.InterruptionType.began.rawValue
                else { return }
                Task { @MainActor [weak self] in self?.interrupted() }
            }
        } catch {
            stop()
            throw error
        }
    }

    static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    func play(_ data: Data) {
        guard running, queued < 6, data.count.isMultiple(of: 2), (2...8192).contains(data.count)
        else { return }
        let count = AVAudioFrameCount(data.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
            let samples = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = count
        data.withUnsafeBytes { bytes in
            for index in 0..<Int(count) {
                samples[index] =
                    Float(bytes.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                    / Float(Int16.max)
            }
        }
        queued += 1
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                if let self { self.queued = max(0, self.queued - 1) }
            }
        }
    }

    func showFrame(_ data: Data) {
        guard running, data.count <= 42_000,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            (1...360).contains(width), (1...360).contains(height),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return }
        renderVideo(UIImage(cgImage: image))
    }

    func stop() {
        running = false
        camera.stop()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        player.stop()
        engine.stop()
        queued = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor final class LocalCallPreview {
    private var camera: ChatCamera?
    private var stopped = false

    func start(video: Bool, onFrame: @escaping (Data) -> Void) async throws -> String {
        let microphoneAllowed = await ChatMedia.requestMicrophoneAccess()
        try checkActive()
        let microphoneStatus = microphoneAllowed
            ? "Microphone access granted."
            : "Microphone access denied. You can enable it in Settings."
        guard video else { return microphoneStatus }

        let cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
        try checkActive()
        let cameraStatus: String
        if ChatCamera.frontDevice == nil {
            cameraStatus = cameraAllowed
                ? "Camera access granted. The front camera is unavailable on this device."
                : "The front camera is unavailable on this device."
        } else if !cameraAllowed {
            cameraStatus = "Camera access denied. You can enable it in Settings."
        } else {
            let camera = ChatCamera()
            self.camera = camera
            do {
                try await camera.start { [weak self] frame in
                    Task { @MainActor [weak self] in
                        guard let self, !self.stopped else { return }
                        onFrame(frame)
                    }
                }
                cameraStatus = "Camera access granted."
            } catch {
                camera.stop()
                self.camera = nil
                cameraStatus = "The camera could not start."
            }
            try checkActive()
        }
        return microphoneStatus + " " + cameraStatus
    }

    func stop() {
        stopped = true
        camera?.stop()
        camera = nil
    }

    private func checkActive() throws {
        if stopped { throw CancellationError() }
    }
}

private final class ChatCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static var frontDevice: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }
    private let queue = DispatchQueue(label: "com.vava.pingpong.chat-camera")
    private let session = AVCaptureSession()
    private let imageContext = CIContext()
    private var send: ((Data) -> Void)?
    private var lastFrame = CMTime.zero

    func start(send: @escaping (Data) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    self.send = send
                    try self.configure()
                    self.session.startRunning()
                    guard self.session.isRunning else { throw AppFailure("The camera could not start.") }
                    continuation.resume()
                } catch {
                    self.send = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configure() throws {
        guard let device = Self.frontDevice else {
            throw AppFailure("A front camera is required for video calls.")
        }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.low) { session.sessionPreset = .low }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw AppFailure("The camera is unavailable.")
        }
        session.addInput(input)
        session.addOutput(output)
        if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    func stop() {
        queue.async {
            self.send = nil
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let time = sampleBuffer.presentationTimeStamp
        guard let send, time.seconds - lastFrame.seconds >= 0.125,
            let pixels = sampleBuffer.imageBuffer
        else { return }
        lastFrame = time
        let image = CIImage(cvPixelBuffer: pixels)
        let scale = 320 / max(image.extent.width, image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let quality = CIImageRepresentationOption(
            rawValue: kCGImageDestinationLossyCompressionQuality as String)
        if let data = imageContext.jpegRepresentation(
            of: scaled, colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [quality: 0.55]), data.count <= 42_000
        {
            send(data)
        }
    }
}
