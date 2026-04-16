import AVFoundation

enum NoiseType: CaseIterable {
    case white, pink, brown, grey
}

enum NoiseGenerator {

    // MARK: - Generators

    static func makeWhite(count: Int) -> [Float] {
        (0..<count).map { _ in Float.random(in: -1...1) }
    }

    static func makePink(count: Int) -> [Float] {
        // Paul Kellet's 7-accumulator 1/f approximation
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0
        var b4: Float = 0, b5: Float = 0, b6: Float = 0
        // Warm up: the slowest pole (0.99886) has τ ≈ 877 samples; run 5× that
        // so the accumulators reach steady state before the audible buffer starts
        for _ in 0..<4096 {
            let w = Float.random(in: -1...1)
            b0 = 0.99886 * b0 + w * 0.0555179
            b1 = 0.99332 * b1 + w * 0.0750759
            b2 = 0.96900 * b2 + w * 0.1538520
            b3 = 0.86650 * b3 + w * 0.3104856
            b4 = 0.55000 * b4 + w * 0.5329522
            b5 = -0.7616 * b5 - w * 0.0168980
            b6 = w * 0.115926
        }
        return (0..<count).map { _ in
            let w = Float.random(in: -1...1)
            b0 = 0.99886 * b0 + w * 0.0555179
            b1 = 0.99332 * b1 + w * 0.0750759
            b2 = 0.96900 * b2 + w * 0.1538520
            b3 = 0.86650 * b3 + w * 0.3104856
            b4 = 0.55000 * b4 + w * 0.5329522
            b5 = -0.7616 * b5 - w * 0.0168980
            let out = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11
            b6 = w * 0.115926
            return out
        }
    }

    static func makeBrown(count: Int) -> [Float] {
        // Random walk (1/f² spectrum) with edge fading to prevent loop clicks
        var last: Float = 0
        var samples = (0..<count).map { _ -> Float in
            last = (last + 0.02 * Float.random(in: -1...1)) / 1.02
            return last * 3.5
        }
        // ~10ms fade at each edge
        let fade = min(441, count / 2)
        for i in 0..<fade {
            let t = Float(i) / Float(fade)
            samples[i] *= t
            samples[count - 1 - i] *= t
        }
        return samples
    }

    static func makeGrey(count: Int) -> [Float] {
        // A gentler equal-loudness-inspired tilt:
        // blend white with a higher cutoff low-passed signal so it stays
        // fuller than pink without reading as overwhelmingly bass-heavy.
        let a: Float = 0.9144  // exp(-2π · 625 / 44100)
        var lp: Float = 0
        return (0..<count).map { _ in
            let w = Float.random(in: -1...1)
            lp = a * lp + (1 - a) * w
            return (w * 0.72 + lp * 1.18) * 0.34
        }
    }

    // MARK: - Buffer creation

    static func makeBuffer(type: NoiseType, seconds: Float, sampleRate: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * Double(seconds))

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = frameCount

        let samples: [Float] = switch type {
        case .white: makeWhite(count: Int(frameCount))
        case .pink:  makePink(count: Int(frameCount))
        case .brown: makeBrown(count: Int(frameCount))
        case .grey:  makeGrey(count: Int(frameCount))
        }
        channelData[0].update(from: samples, count: Int(frameCount))

        return buffer
    }
}
 