import Foundation

/// Bounded PCM16 WAV data and an energy envelope for approximate, playback-clock jaw motion.
nonisolated struct SpeechAudio: Sendable {
    static let maximumBytes = 12 * 1_024 * 1_024
    let data: Data
    let duration: TimeInterval
    private let envelope: [Float]
    private let envelopeInterval: TimeInterval

    init(wav data: Data) throws {
        guard data.count >= 44, data.count <= Self.maximumBytes else { throw SpeechFailure.invalidAudio }
        let bytes = [UInt8](data)
        func integer(_ i: Int, _ count: Int) -> Int {
            (0..<count).reduce(0) { $0 | Int(bytes[i + $1]) << ($1 * 8) }
        }
        func tag(_ i: Int) -> String { String(decoding: bytes[i..<i+4], as: UTF8.self) }
        guard tag(0) == "RIFF", tag(8) == "WAVE", integer(4, 4) + 8 == data.count else {
            throw SpeechFailure.invalidAudio
        }
        var offset = 12, format: (Int, Int)?, sampleRange: Range<Int>?
        while offset + 8 <= bytes.count {
            let length = integer(offset + 4, 4), start = offset + 8
            guard length <= bytes.count - start else { throw SpeechFailure.invalidAudio }
            switch tag(offset) {
            case "fmt ":
                guard format == nil, length >= 16, integer(start, 2) == 1,
                      (1...2).contains(integer(start + 2, 2)), (8_000...48_000).contains(integer(start + 4, 4)),
                      integer(start + 14, 2) == 16 else { throw SpeechFailure.invalidAudio }
                let channels = integer(start + 2, 2), rate = integer(start + 4, 4)
                guard integer(start + 12, 2) == channels * 2, integer(start + 8, 4) == rate * channels * 2 else {
                    throw SpeechFailure.invalidAudio
                }
                format = (channels, rate)
            case "data":
                guard sampleRange == nil else { throw SpeechFailure.invalidAudio }
                sampleRange = start..<start+length
            default: break
            }
            offset = start + length + length % 2
        }
        guard offset == bytes.count, let (channels, rate) = format, let range = sampleRange,
              !range.isEmpty, range.count % (channels * 2) == 0 else { throw SpeechFailure.invalidAudio }
        let duration = Double(range.count) / Double(rate * channels * 2)
        guard duration >= 0.05, duration <= 120 else { throw SpeechFailure.invalidAudio }
        let strideBytes = max(1, rate / 50) * channels * 2
        var envelope: [Float] = []
        for start in stride(from: range.lowerBound, to: range.upperBound, by: strideBytes) {
            let end = min(start + strideBytes, range.upperBound)
            var energy: Float = 0
            for index in stride(from: start, to: end, by: 2) {
                let sample = Float(Int16(bitPattern: UInt16(integer(index, 2)))) / 32_768
                energy += sample * sample
            }
            let rms = sqrt(energy / Float((end - start) / 2))
            envelope.append(min(0.35, max(0, (rms - 0.008) * 3)))
        }
        self.data = data
        self.duration = duration
        self.envelope = envelope
        envelopeInterval = Double(max(1, rate / 50)) / Double(rate)
    }

    func mouthOpenness(at time: TimeInterval) -> Float {
        guard time.isFinite, time >= 0, time < duration else { return 0 }
        return envelope[min(envelope.count - 1, Int(time / envelopeInterval))]
    }
}
