import AVFoundation
import Combine
import Foundation

/// Keeps the process running after the screen locks or the app goes to the
/// background by looping a silent audio file. iOS suspends normal apps almost
/// immediately in the background, which kills the tsnet UDP sockets; with an
/// active audio session the process (and the Tailscale connection) survives.
/// This costs battery, so it can be turned off in Settings.
final class BackgroundKeepAlive: ObservableObject {
    private static let defaultsKey = "tailweb.keepAlive"

    @Published private(set) var isPlaying = false

    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: Self.defaultsKey)
            updatePlayback()
        }
    }

    private var player: AVAudioPlayer?
    private var interruptionObserver: NSObjectProtocol?

    init() {
        // Default on: an absent key means the user has not opted out yet.
        if UserDefaults.standard.object(forKey: Self.defaultsKey) == nil {
            enabled = true
        } else {
            enabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
        updatePlayback()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    /// Restarts the silent loop if the system paused it while we were away.
    func ensurePlaying() {
        guard enabled, player?.isPlaying != true else { return }
        updatePlayback()
    }

    private func updatePlayback() {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        if let player {
            if !player.isPlaying {
                player.play()
            }
            isPlaying = player.isPlaying
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.silentWAV())
            player.numberOfLoops = -1
            player.prepareToPlay()
            player.play()
            self.player = player
            isPlaying = player.isPlaying
        } catch {
            isPlaying = false
        }
    }

    private func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func handleInterruption(_ notification: Notification) {
        guard enabled,
              let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else {
            return
        }
        switch type {
        case .began:
            isPlaying = false
        case .ended:
            // The call/Siri session is over; loop the silence again.
            start()
        @unknown default:
            break
        }
    }

    /// One second of 16-bit mono PCM silence wrapped in a RIFF/WAVE header.
    private static func silentWAV() -> Data {
        let sampleRate: UInt32 = 44_100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerFrame = Int(channels) * Int(bitsPerSample / 8)
        let dataSize = Int(sampleRate) * bytesPerFrame

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(channels)
        append(sampleRate)
        append(sampleRate * UInt32(bytesPerFrame))
        append(UInt16(bytesPerFrame))
        append(bitsPerSample)
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }
}
