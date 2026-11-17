import AVFoundation
import React
import UIKit

@objc(VavaVideoManager) final class VavaVideoManager: RCTViewManager {
    override static func requiresMainQueueSetup() -> Bool { true }
    override func view() -> UIView! { VavaVideoView(frame: .zero) }
}

final class VavaVideoView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var player: AVPlayer?
    private var progress: Any?
    private var status: NSKeyValueObservation?
    private var ending: NSObjectProtocol?
    @objc var onProgress: RCTDirectEventBlock?
    @objc var onError: RCTDirectEventBlock?
    @objc var seekFraction: Double = 0 {
        didSet {
            guard seekFraction != oldValue, seekFraction.isFinite,
                  let duration = player?.currentItem?.duration.seconds,
                  duration.isFinite, duration > 0 else { return }
            player?.seek(to: CMTime(seconds: duration * min(1, max(0, seekFraction)), preferredTimescale: 600))
        }
    }
    private var background: NSObjectProtocol?
    private var foreground: NSObjectProtocol?
    private var active = true
    @objc var paused = true { didSet { syncPlayback() } }
    @objc var uri: String = "" {
        didSet {
            guard uri != oldValue else { return }
            loadVideo()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
        background = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
            [weak self] _ in self?.active = false; self?.syncPlayback()
        }
        foreground = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) {
            [weak self] _ in self?.active = true; self?.syncPlayback()
        }
    }
    required init?(coder: NSCoder) { nil }
    deinit {
        player?.pause()
        if let progress { player?.removeTimeObserver(progress) }
        for token in [ending, background, foreground].compactMap({ $0 }) { NotificationCenter.default.removeObserver(token) }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncPlayback()
    }
    private func loadVideo() {
        player?.pause()
        status = nil
        if let progress { player?.removeTimeObserver(progress) }
        progress = nil
        if let ending { NotificationCenter.default.removeObserver(ending) }
        ending = nil
        guard let url = URL(string: uri) else { playerLayer.player = nil; player = nil; return }
        let player = AVPlayer(url: url)
        self.player = player
        playerLayer.player = player
        progress = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self, let duration = self.player?.currentItem?.duration.seconds,
                  duration.isFinite, time.seconds.isFinite else { return }
            self.onProgress?(["currentTime": time.seconds, "duration": duration])
        }
        status = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed {
                DispatchQueue.main.async { self?.onError?(["message": "This video could not be played."]) }
            }
        }
        ending = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) {
            [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.syncPlayback()
        }
        syncPlayback()
    }
    private func syncPlayback() {
        if !paused, active, window != nil { player?.play() }
        else { player?.pause() }
    }
}

@objc(VavaCallVideoManager) final class VavaCallVideoManager: RCTViewManager {
    override static func requiresMainQueueSetup() -> Bool { true }
    override func view() -> UIView! { VavaCallVideoView(frame: .zero) }
}

final class VavaCallVideoView: UIImageView {
    private var observer: NSObjectProtocol?
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFit
        backgroundColor = .black
        observer = NotificationCenter.default.addObserver(forName: Notification.Name("Vava.ReactNative.CallFrame"), object: nil, queue: .main) {
            [weak self] note in self?.image = note.object as? UIImage
        }
    }
    required init?(coder: NSCoder) { nil }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
