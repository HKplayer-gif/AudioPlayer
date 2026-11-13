import AVFAudio
import Foundation
import XCTest
@testable import AudioPlayer

final class BPMKeyAnalysisServiceTests: XCTestCase {
    func testAnalyzesSyntheticCMajorAt120BPMAndCachesResult() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioPlayer-Essentia-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let audioURL = temporaryDirectory.appendingPathComponent("synthetic-c-major.wav")
        try Self.writeSyntheticAudio(to: audioURL)

        let service = BPMKeyAnalysisService(
            cacheDirectoryURL: temporaryDirectory.appendingPathComponent("cache", isDirectory: true)
        )

        let firstResult = try await service.analyze(fileURL: audioURL)
        let secondResult = try await service.analyze(fileURL: audioURL)

        XCTAssertEqual(firstResult.key, "C")
        XCTAssertEqual(firstResult.scale.lowercased(), "major")
        XCTAssertEqual(firstResult.bpm, 120.0, accuracy: 2.0)
        XCTAssertGreaterThan(firstResult.beatTimes.count, 20)
        XCTAssertEqual(secondResult, firstResult)
    }

    private static func writeSyntheticAudio(to url: URL) throws {
        let sampleRate = 44_100.0
        let duration = 30.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            throw NSError(
                domain: "AudioPlayerTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not allocate test PCM buffer."]
            )
        }

        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?.pointee else {
            throw NSError(
                domain: "AudioPlayerTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not access test PCM samples."]
            )
        }

        let frequencies = [261.6256, 329.6276, 391.9954]
        for index in 0..<Int(frameCount) {
            let time = Double(index) / sampleRate
            let chord = frequencies.reduce(0.0) { partial, frequency in
                partial + sin(2.0 * Double.pi * frequency * time) / 3.0
            }
            let beatPhase = time.truncatingRemainder(dividingBy: 0.5)
            let transient = beatPhase < 0.025
                ? 0.8 * exp(-beatPhase * 180.0)
                : 0.0
            samples[index] = Float(0.10 * chord + transient)
        }

        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try audioFile.write(from: buffer)
    }
}
