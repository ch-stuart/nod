import AVFoundation
import MediaPlayer
import QuartzCore
import Observation

@Observable
final class GridEngine {

    private(set) var isRunning = false
    private(set) var position: CGPoint = .init(x: 0.5, y: 0.5)

    // MARK: - Audio graph
    //
    // players[i] → mixers[i] ─┐
    //                          ├→ sumMixer → hpEQ → lpEQ → mainMixer
    // (all four feed in)      ─┘

    private let engine = AVAudioEngine()
    private let mixers: [AVAudioMixerNode] = (0..<4).map { _ in AVAudioMixerNode() }
    private let players: [AVAudioPlayerNode] = (0..<4).map { _ in AVAudioPlayerNode() }
    private let sumMixer = AVAudioMixerNode()
    private let hpEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let lpEQ = AVAudioUnitEQ(numberOfBands: 1)
    private var isGraphSetup = false
    private var hardwareSampleRate: Double = 0
    private var cachedBuffers: [AVAudioPCMBuffer] = []

    // MARK: - Smooth parameter state (updated by CADisplayLink)

    private var targetGains: [Float] = [1, 0, 0, 0]
    private var currentGains: [Float] = [1, 0, 0, 0]
    private var targetHPFreq: Float = 20
    private var currentHPFreq: Float = 20
    private var targetLPFreq: Float = 22050
    private var currentLPFreq: Float = 22050

    private var displayLink: CADisplayLink?
    private var startupFadeFrames = 0
    private let startupFadeFrameCount = 3  // ~50ms linear fade-in at 60fps

    // MARK: - Bookmarks

    private(set) var bookmarks: [CGPoint] = []
    private var dwellPosition: CGPoint? = nil
    private var dwellStart: Date? = nil
    private let dwellDistance: Double = 0.04
    private let dwellDuration: TimeInterval = 10
    var bookmarkProximity: Double = 0.05
    private let maxBookmarks = 5

    // MARK: - Init

    init() {
        loadBookmarks()
        setupRemoteCommands()
    }

    // MARK: - Toggle (debounced, for tap gestures)

    private var pendingAudioTask: Task<Void, Never>?

    func toggle() {
        isRunning.toggle()
        let target = isRunning
        pendingAudioTask?.cancel()
        pendingAudioTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            if target { self.startAudio() } else { self.stopAudio() }
        }
    }

    // MARK: - Start / Stop

    private func startAudio() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session failed:", error)
        }

        if hardwareSampleRate == 0 {
            hardwareSampleRate = AVAudioSession.sharedInstance().sampleRate
        }

        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: hardwareSampleRate, channels: 1) else {
            print("Failed to create audio format")
            isRunning = false
            return
        }

        setupGraph(format: monoFormat)

        do {
            try engine.start()
        } catch {
            print("GridEngine failed to start:", error)
            isRunning = false
            return
        }

        // Snap all parameters to the current position so there's no audible onset ramp
        setPosition(x: Float(position.x), y: Float(position.y))
        currentGains = targetGains
        for i in 0..<4 { mixers[i].outputVolume = currentGains[i] }
        currentHPFreq = targetHPFreq
        currentLPFreq = targetLPFreq
        hpEQ.bands[0].frequency = currentHPFreq
        lpEQ.bands[0].frequency = currentLPFreq

        // Fade in from silence to hide any engine/filter startup transients
        engine.mainMixerNode.outputVolume = 0
        startupFadeFrames = 0

        if cachedBuffers.isEmpty {
            let rate = hardwareSampleRate
            Task.detached(priority: .userInitiated) {
                let types: [NoiseType] = [.white, .grey, .pink, .brown]
                let buffers = types.compactMap { NoiseGenerator.makeBuffer(type: $0, seconds: 5, sampleRate: rate) }
                await MainActor.run {
                    guard self.isRunning else { return }
                    self.cachedBuffers = buffers
                    for (i, buffer) in buffers.enumerated() {
                        self.players[i].scheduleBuffer(buffer, at: nil, options: .loops)
                        self.players[i].play()
                    }
                }
            }
        } else {
            for (i, buffer) in cachedBuffers.enumerated() {
                players[i].scheduleBuffer(buffer, at: nil, options: .loops)
                players[i].play()
            }
        }

        startDisplayLink()
        updateNowPlaying()
    }

    private func setupGraph(format: AVAudioFormat) {
        guard !isGraphSetup else { return }
        isGraphSetup = true

        hpEQ.bands[0].filterType = .highPass
        hpEQ.bands[0].frequency = 20
        hpEQ.bands[0].bandwidth = 1.0
        hpEQ.bands[0].bypass = false

        lpEQ.bands[0].filterType = .lowPass
        lpEQ.bands[0].frequency = 22050
        lpEQ.bands[0].bandwidth = 1.0
        lpEQ.bands[0].bypass = false

        engine.attach(sumMixer)
        engine.attach(hpEQ)
        engine.attach(lpEQ)

        for i in 0..<4 {
            engine.attach(players[i])
            engine.attach(mixers[i])
            engine.connect(players[i], to: mixers[i], format: format)
            engine.connect(mixers[i], to: sumMixer, format: format)
        }

        engine.connect(sumMixer, to: hpEQ, format: format)
        engine.connect(hpEQ, to: lpEQ, format: format)
        engine.connect(lpEQ, to: engine.mainMixerNode, format: format)
    }

    private func stopAudio() {
        displayLink?.invalidate()
        displayLink = nil
        players.forEach { $0.stop() }
        engine.stop()
        dwellStart = nil
        dwellPosition = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Position

    func setPosition(x: Float, y: Float) {
        let newPos = CGPoint(x: Double(x), y: Double(y))
        position = newPos

        if let last = dwellPosition,
           hypot(newPos.x - last.x, newPos.y - last.y) < dwellDistance {
            // still in the same spot — keep the existing timer
        } else {
            dwellPosition = newPos
            dwellStart = Date()
        }

        // Y: triangle basis crossfade — biased curve gives more grid space to brown (bottom)
        let yBiased = pow(y, 0.65)
        let centers: [Float] = [0, 1/3, 2/3, 1]
        for i in 0..<4 {
            targetGains[i] = max(0, 1 - abs(yBiased - centers[i]) * 3)
        }

        // X: log-interpolated HP/LP sweep
        targetHPFreq = x < 0.2 ? logInterp(150, 20, x / 0.2) : 20
        targetLPFreq = x > 0.2 ? logInterp(22050, 350, (x - 0.2) / 0.8) : 22050
    }

    // MARK: - Display link (smooth parameter changes at ~60fps)

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        if startupFadeFrames < startupFadeFrameCount {
            startupFadeFrames += 1
            engine.mainMixerNode.outputVolume = Float(startupFadeFrames) / Float(startupFadeFrameCount)
        }

        let alpha: Float = 0.08  // ≈ 60ms smoothing

        for i in 0..<4 {
            currentGains[i] += (targetGains[i] - currentGains[i]) * alpha
            mixers[i].outputVolume = currentGains[i]
        }

        currentHPFreq += (targetHPFreq - currentHPFreq) * alpha
        currentLPFreq += (targetLPFreq - currentLPFreq) * alpha

        hpEQ.bands[0].frequency = currentHPFreq
        lpEQ.bands[0].frequency = currentLPFreq

        if let start = dwellStart, let pos = dwellPosition,
           Date().timeIntervalSince(start) >= dwellDuration {
            addBookmark(pos)
            dwellStart = nil  // won't trigger again until they move and return
        }
    }

    // MARK: - Now Playing

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self, !isRunning else { return .commandFailed }
            DispatchQueue.main.async {
                self.isRunning = true
                self.startAudio()
            }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, isRunning else { return .commandFailed }
            DispatchQueue.main.async {
                self.isRunning = false
                self.stopAudio()
            }
            return .success
        }

        center.stopCommand.addTarget { [weak self] _ in
            guard let self, isRunning else { return .commandFailed }
            DispatchQueue.main.async {
                self.isRunning = false
                self.stopAudio()
            }
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            DispatchQueue.main.async {
                self.toggle()
            }
            return .success
        }
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Nod",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }

    // MARK: - Helpers

    private func logInterp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        exp(log(a) * (1 - t) + log(b) * t)
    }

    private func addBookmark(_ point: CGPoint) {
        for b in bookmarks where hypot(point.x - b.x, point.y - b.y) < bookmarkProximity { return }
        if bookmarks.count >= maxBookmarks { bookmarks.removeFirst() }
        bookmarks.append(point)
        saveBookmarks()
    }

    private func saveBookmarks() {
        let data = bookmarks.map { ["x": $0.x, "y": $0.y] }
        UserDefaults.standard.set(data, forKey: "gridBookmarks")
    }

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.array(forKey: "gridBookmarks") as? [[String: Double]] else { return }
        bookmarks = data.compactMap { dict in
            guard let x = dict["x"], let y = dict["y"] else { return nil }
            return CGPoint(x: x, y: y)
        }
    }
}
