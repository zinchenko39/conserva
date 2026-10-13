import AVFoundation

/// What the shelf can sound like. Each one is synthesised when it happens, from what makes the real
/// sound: a glass jar rings in the bending modes of its wall, the swing-top's steel wire clicks
/// high and dies at once, rubber parting from glass is a short, low, breathy thup.
enum Sound {
    /// Two jars knocking: `strength` 0…1 from how hard; each jar rings at its own `pitches`.
    case clink(strength: Float, pitches: (Float, Float))
    /// The lever flips out and lets the lid's wire go.
    case leverRelease
    /// The rubber ring lets go of the rim; the lid, free, rings faintly.
    case sealPop
    /// The lid swings back against its hinge.
    case lidRest
    /// The glass lid comes down on its rubber ring, muffled.
    case lidLand(pitch: Float)
    /// The lever snaps over and clamps the lid; the jar answers with a faint ring.
    case leverClamp(pitch: Float)
}

/// Plays sounds through a small pool of voices, each panned to where on the screen it happened.
/// The engine runs only while something is playing, so an idle shelf keeps the audio hardware asleep.
@MainActor
final class SoundBoard {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.rate, channels: 1)!
    private var voices: [AVAudioPlayerNode] = []
    private var next = 0
    private var stopWork: DispatchWorkItem?

    init() {
        for _ in 0..<8 {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }
    }

    /// `pan` from -1 (left edge of the screen) to 1 (right edge).
    func play(_ sound: Sound, volume: Float, pan: Float) {
        let samples = Synth.render(sound)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        if !engine.isRunning {
            do { try engine.start() } catch { NSLog("Conserva: no sound: \(error)"); return }
        }
        let voice = voices[next]
        next = (next + 1) % voices.count
        voice.stop()
        voice.volume = volume
        voice.pan = max(-1, min(1, pan))
        voice.scheduleBuffer(buffer)
        voice.play()

        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.engine.stop() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(samples.count) / Synth.rate + 1, execute: work)
    }

    /// Every sound once, as 16-bit WAV files in `folder`, so they can be listened to outside the app.
    static func writeSamples(to folder: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: Synth.rate, channels: 1)!
        let all: [(String, Sound)] = [
            ("clink-soft", .clink(strength: 0.2, pitches: (760, 790))), ("clink-hard", .clink(strength: 1, pitches: (760, 790))),
            ("lever-release", .leverRelease), ("seal-pop", .sealPop), ("lid-rest", .lidRest),
            ("lid-land", .lidLand(pitch: 760)), ("lever-clamp", .leverClamp(pitch: 760)),
        ]
        for (name, sound) in all {
            let samples = Synth.render(sound)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buffer.frameLength = buffer.frameCapacity
            samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Synth.rate,
                                           AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16]
            let file = try AVAudioFile(forWriting: folder.appendingPathComponent("\(name).wav"), settings: settings)
            try file.write(from: buffer)
        }
    }
}

/// Damped sines and filtered noise: enough for glass, rubber and wire.
enum Synth {
    static let rate: Double = 44_100

    /// The bending modes of a glass cylinder's wall, over the lowest: n(n²−1)/√(n²+1) for n = 2…5,
    /// the same law a wine glass rings by.
    static let wallModes: [Float] = [1, 2.83, 5.42, 8.77]
    /// A glass disc, the lid.
    static let discModes: [Float] = [1, 2.1, 3.6]

    static func render(_ sound: Sound) -> [Float] {
        var out: [Float]
        switch sound {
        case .clink(let strength, let pitches):
            out = silence(2.2)
            // A harder knock reaches the higher modes; a soft one is mostly the low note.
            let bright = 0.3 + 0.7 * strength
            ring(&out, pitch: pitches.0, modes: wallModes, amps: [1, 0.55, 0.3, 0.16], bright: bright, tau: 0.55)
            ring(&out, pitch: pitches.1, modes: wallModes, amps: [0.85, 0.5, 0.26, 0.14], bright: bright, tau: 0.5, at: 0.002)
            noise(&out, centre: 3500, q: 0.8, amp: 0.35 * strength, tau: 0.003)
            tone(&out, freq: 170, amp: 0.25 * strength, tau: 0.035)
        case .leverRelease:
            out = silence(0.35)
            metal(&out, freqs: [2900, 4700, 7300], amp: 0.5, tau: 0.025)
            noise(&out, centre: 5000, q: 1, amp: 0.4, tau: 0.0015)
            tone(&out, freq: 340, amp: 0.12, tau: 0.06)
        case .sealPop:
            out = silence(0.6)
            noise(&out, centre: 700, q: 1.2, amp: 0.5, tau: 0.025)
            sweep(&out, from: 260, to: 150, amp: 0.6, tau: 0.03)
            ring(&out, pitch: 1900, modes: discModes, amps: [0.12, 0.06, 0.03], bright: 1, tau: 0.25, at: 0.01)
        case .lidRest:
            out = silence(1)
            metal(&out, freqs: [3200, 5100], amp: 0.3, tau: 0.01)
            ring(&out, pitch: 1900, modes: discModes, amps: [0.08, 0.04, 0.02], bright: 1, tau: 0.3)
        case .lidLand(let pitch):
            out = silence(0.4)
            tone(&out, freq: 210, amp: 0.6, tau: 0.045)
            noise(&out, centre: 500, q: 0.7, amp: 0.4, tau: 0.015)
            // The rubber damps the glass: only a short, dull trace of either ring.
            ring(&out, pitch: 1900, modes: discModes, amps: [0.05, 0.02, 0.01], bright: 1, tau: 0.08)
            ring(&out, pitch: pitch, modes: wallModes, amps: [0.04, 0.02, 0, 0], bright: 1, tau: 0.12)
        case .leverClamp(let pitch):
            out = silence(0.8)
            metal(&out, freqs: [2500, 4100, 6600], amp: 0.55, tau: 0.03)
            noise(&out, centre: 4500, q: 1, amp: 0.6, tau: 0.001)
            ring(&out, pitch: pitch, modes: wallModes, amps: [0.06, 0.03, 0.015, 0], bright: 1, tau: 0.4, at: 0.003)
        }
        normalize(&out, peak: 0.9)
        return out
    }

    private static func silence(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * rate)) }

    private static func jitter(_ x: Float, _ amount: Float) -> Float { x * Float.random(in: 1 - amount...1 + amount) }

    /// Modes of one body struck once. Each glass mode is really a pair a hair apart, from the glass not
    /// being perfectly round, and the pair beats: that slow shimmer is much of what makes glass sound like glass.
    private static func ring(_ out: inout [Float], pitch: Float, modes: [Float], amps: [Float], bright: Float, tau: Float, at start: Double = 0) {
        for (k, ratio) in modes.enumerated() where amps[k] > 0 {
            let f = jitter(pitch * ratio, 0.003)
            let a = jitter(amps[k] * pow(bright, Float(k)), 0.1)
            // Higher modes lose their energy faster.
            let t = tau / pow(ratio, 0.8)
            partial(&out, freq: f, amp: a * 0.62, tau: t, start: start)
            partial(&out, freq: f * (1 + 0.0018 * Float(k + 1)), amp: a * 0.38, tau: t, start: start)
        }
    }

    /// Steel wire and its spring: a few high, inharmonic partials that are gone within tens of milliseconds.
    private static func metal(_ out: inout [Float], freqs: [Float], amp: Float, tau: Float) {
        for (k, f) in freqs.enumerated() {
            partial(&out, freq: jitter(f, 0.02), amp: jitter(amp / Float(k + 1), 0.15), tau: tau / Float(k + 1).squareRoot(), start: 0)
        }
    }

    private static func tone(_ out: inout [Float], freq: Float, amp: Float, tau: Float) {
        partial(&out, freq: jitter(freq, 0.03), amp: amp, tau: tau, start: 0)
    }

    /// A low thump whose pitch falls as it dies: the air behind the rubber.
    private static func sweep(_ out: inout [Float], from f0: Float, to f1: Float, amp: Float, tau: Float) {
        var phase: Float = 0
        let n = min(out.count, Int(Double(tau) * 8 * rate))
        for i in 0..<n {
            let t = Float(Double(i) / rate)
            let f = f1 + (f0 - f1) * exp(-t / tau)
            phase += 2 * .pi * f / Float(rate)
            out[i] += amp * attack(i) * exp(-t / tau) * sin(phase)
        }
    }

    private static func partial(_ out: inout [Float], freq: Float, amp: Float, tau: Float, start: Double) {
        let first = Int(start * rate)
        let n = min(out.count - first, Int(Double(tau) * 9 * rate))
        guard n > 0 else { return }
        let w = 2 * Float.pi * freq / Float(rate), phase = Float.random(in: 0..<(2 * .pi))
        let decay = exp(-1 / (tau * Float(rate)))
        var env: Float = 1
        for i in 0..<n {
            out[first + i] += amp * attack(i) * env * sin(w * Float(i) + phase)
            env *= decay
        }
    }

    /// White noise through a band-pass, dying away: the contact itself.
    private static func noise(_ out: inout [Float], centre: Float, q: Float, amp: Float, tau: Float) {
        guard amp > 0 else { return }
        var filter = BandPass(centre: centre, q: q)
        let n = min(out.count, Int(Double(tau) * 9 * rate))
        let decay = exp(-1 / (tau * Float(rate)))
        var env: Float = 1
        for i in 0..<n {
            out[i] += amp * 3 * env * filter.process(Float.random(in: -1...1))
            env *= decay
        }
    }

    /// A fraction of a millisecond of fade-in, so no partial starts with a click of its own.
    private static func attack(_ i: Int) -> Float { min(1, Float(i) / 12) }

    private static func normalize(_ out: inout [Float], peak: Float) {
        let top = out.reduce(0) { max($0, abs($1)) }
        guard top > 0 else { return }
        let g = peak / top
        for i in out.indices { out[i] *= g }
        // The last few milliseconds fade out, so a cut-off tail does not click.
        let fade = min(out.count, Int(0.01 * rate))
        for i in 0..<fade { out[out.count - 1 - i] *= Float(i) / Float(fade) }
    }

    /// The audio cookbook's constant-peak band-pass biquad.
    private struct BandPass {
        let b0, b2, a1, a2: Float
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

        init(centre: Float, q: Float) {
            let w = 2 * Float.pi * centre / Float(Synth.rate), alpha = sin(w) / (2 * q), a0 = 1 + alpha
            b0 = alpha / a0; b2 = -alpha / a0; a1 = -2 * cos(w) / a0; a2 = (1 - alpha) / a0
        }

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }
}
