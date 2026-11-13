import AVFAudio
import CryptoKit
import EssentiaBridge
import Foundation

struct BPMKeyAnalysisResult: Codable, Equatable, Sendable {
    let key: String
    let scale: String
    let keyStrength: Float
    let bpm: Double
    let bpmConfidence: Float
    let beatTimes: [TimeInterval]
}

enum BPMKeyAnalysisStatus: Equatable, Sendable {
    case idle
    case analyzing
    case ready
    case failed(String)

    var displayMessage: String {
        switch self {
        case .idle:
            return "Not analyzed"
        case .analyzing:
            return "Analyzing…"
        case .ready:
            return "Ready"
        case .failed:
            return "Unavailable"
        }
    }
}

actor BPMKeyAnalysisService {
    private final class AudioConverterInputProvider: @unchecked Sendable {
        private let buffer: AVAudioPCMBuffer
        private var hasProvidedInput = false

        init(buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func nextInput(
            status: UnsafeMutablePointer<AVAudioConverterInputStatus>
        ) -> AVAudioBuffer? {
            guard !hasProvidedInput else {
                status.pointee = .endOfStream
                return nil
            }

            hasProvidedInput = true
            status.pointee = .haveData
            return buffer
        }
    }

    private let cacheDirectoryURL: URL

    init(
        cacheDirectoryURL: URL = StateStore.userDataDirectoryURL
            .appendingPathComponent("Analysis Cache", isDirectory: true)
    ) {
        self.cacheDirectoryURL = cacheDirectoryURL
    }

    private struct FileIdentity: Equatable {
        let path: String
        let size: UInt64
        let modificationDate: Date
    }

    private struct CacheRecord: Codable {
        let sourcePath: String
        let fileSize: UInt64
        let modificationDate: Date
        let result: BPMKeyAnalysisResult
    }

    func analyze(fileURL: URL) async throws -> BPMKeyAnalysisResult {
        let identity = try Self.fileIdentity(for: fileURL)
        let cacheURL = cacheURL(for: identity.path)

        if let cached = Self.readCache(at: cacheURL),
           cached.sourcePath == identity.path,
           cached.fileSize == identity.size,
           cached.modificationDate == identity.modificationDate {
            return cached.result
        }

        let analysisTask = Task.detached(priority: .utility) {
            try Task<Never, Never>.checkCancellation()
            let result = try Self.performAnalysis(
                fileURL: fileURL,
                rhythmMethod: "multifeature"
            )
            try Task<Never, Never>.checkCancellation()
            return result
        }

        let result = try await withTaskCancellationHandler {
            try await analysisTask.value
        } onCancel: {
            analysisTask.cancel()
        }

        let identityAfterAnalysis = try Self.fileIdentity(for: fileURL)
        guard identityAfterAnalysis == identity else {
            throw AnalysisError.sourceChangedDuringAnalysis
        }

        let record = CacheRecord(
            sourcePath: identity.path,
            fileSize: identity.size,
            modificationDate: identity.modificationDate,
            result: result
        )

        try Self.writeCache(record, to: cacheURL)
        return result
    }

    private static func fileIdentity(for url: URL) throws -> FileIdentity {
        let standardizedPath = url.standardizedFileURL.path
        let attributes = try FileManager.default.attributesOfItem(
            atPath: standardizedPath
        )

        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date
            ?? .distantPast

        return FileIdentity(
            path: standardizedPath,
            size: size,
            modificationDate: modificationDate
        )
    }

    private func cacheURL(for sourcePath: String) -> URL {
        let digest = SHA256.hash(data: Data(sourcePath.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        return cacheDirectoryURL
            .appendingPathComponent("\(digest).json")
    }

    private static func readCache(at url: URL) -> CacheRecord? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(CacheRecord.self, from: data)
    }

    private static func writeCache(
        _ record: CacheRecord,
        to url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: url, options: .atomic)
    }

    private static func performAnalysis(
        fileURL: URL,
        rhythmMethod: String
    ) throws -> BPMKeyAnalysisResult {
        let monoSamples = try decodeMono44100(fileURL: fileURL)
        try Task<Never, Never>.checkCancellation()

        let nativeResult = monoSamples.withUnsafeBufferPointer { samples in
            ap_essentia_analyze_mono_44100(
                samples.baseAddress,
                samples.count,
                rhythmMethod
            )
        }

        guard let nativeResult else {
            throw AnalysisError.essentiaReturnedNoResult
        }
        defer {
            ap_essentia_result_destroy(nativeResult)
        }
        try Task<Never, Never>.checkCancellation()

        let nativeError = String(
            cString: ap_essentia_result_error(nativeResult)
        )
        guard nativeError.isEmpty else {
            throw AnalysisError.essentia(nativeError)
        }

        let key = String(cString: ap_essentia_result_key(nativeResult))
        let scale = String(cString: ap_essentia_result_scale(nativeResult))
        let keyStrength = ap_essentia_result_key_strength(nativeResult)
        let bpm = ap_essentia_result_bpm(nativeResult)
        let bpmConfidence = ap_essentia_result_bpm_confidence(nativeResult)

        let beatCount = ap_essentia_result_beat_count(nativeResult)
        var beatTimes = [Double](repeating: 0.0, count: beatCount)
        let copiedBeatCount = beatTimes.withUnsafeMutableBufferPointer { buffer in
            ap_essentia_result_copy_beats(
                nativeResult,
                buffer.baseAddress,
                buffer.count
            )
        }
        if copiedBeatCount < beatTimes.count {
            beatTimes = Array(beatTimes.prefix(copiedBeatCount))
        }

        guard !key.isEmpty,
              !scale.isEmpty,
              bpm.isFinite,
              bpm > 0,
              !beatTimes.isEmpty else {
            throw AnalysisError.invalidAnalysisOutput
        }

        return BPMKeyAnalysisResult(
            key: key,
            scale: scale,
            keyStrength: keyStrength,
            bpm: Double(bpm),
            bpmConfidence: bpmConfidence,
            beatTimes: beatTimes
        )
    }

    private static func decodeMono44100(fileURL: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: fileURL)
        let inputFormat = file.processingFormat

        guard file.length > 0,
              file.length <= AVAudioFramePosition(UInt32.max),
              inputFormat.sampleRate > 0 else {
            throw AnalysisError.invalidAudioFile
        }

        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AnalysisError.bufferAllocationFailed
        }

        try file.read(into: inputBuffer)
        guard inputBuffer.frameLength > 0 else {
            throw AnalysisError.invalidAudioFile
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100.0,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(
            from: inputFormat,
            to: outputFormat
        ) else {
            throw AnalysisError.converterUnavailable
        }

        let ratio = 44_100.0 / inputFormat.sampleRate
        let requiredCapacity = ceil(
            Double(inputBuffer.frameLength) * ratio
        ) + 4096

        guard requiredCapacity <= Double(UInt32.max),
              let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(requiredCapacity)
              ) else {
            throw AnalysisError.bufferAllocationFailed
        }

        let inputProvider = AudioConverterInputProvider(buffer: inputBuffer)
        var conversionError: NSError?
        let conversionStatus = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, inputStatus in
            inputProvider.nextInput(status: inputStatus)
        }

        if let conversionError {
            throw conversionError
        }
        guard conversionStatus != .error,
              outputBuffer.frameLength > 0,
              let channelData = outputBuffer.floatChannelData?.pointee else {
            throw AnalysisError.audioConversionFailed
        }

        return Array(
            UnsafeBufferPointer(
                start: channelData,
                count: Int(outputBuffer.frameLength)
            )
        )
    }

    private enum AnalysisError: LocalizedError {
        case sourceChangedDuringAnalysis
        case essentiaReturnedNoResult
        case essentia(String)
        case invalidAnalysisOutput
        case invalidAudioFile
        case bufferAllocationFailed
        case converterUnavailable
        case audioConversionFailed

        var errorDescription: String? {
            switch self {
            case .sourceChangedDuringAnalysis:
                return "The audio file changed while it was being analyzed."
            case .essentiaReturnedNoResult:
                return "Essentia did not return an analysis result."
            case .essentia(let message):
                return message
            case .invalidAnalysisOutput:
                return "Essentia returned incomplete BPM or key data."
            case .invalidAudioFile:
                return "The audio file is empty or has an unsupported format."
            case .bufferAllocationFailed:
                return "Audio analysis could not allocate its PCM buffer."
            case .converterUnavailable:
                return "The audio format could not be converted for analysis."
            case .audioConversionFailed:
                return "Audio conversion to 44.1 kHz mono failed."
            }
        }
    }
}
