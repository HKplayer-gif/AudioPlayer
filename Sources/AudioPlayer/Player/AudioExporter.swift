import Foundation
import AVFAudio

struct AudioExporter {

    static func export(
        sourceURL: URL,
        destinationURL: URL,
        format: AudioExportFormat,
        algorithm: AudioProcessingAlgorithm,
        pitch: Double,
        speed: Double,
        volume: Double
    ) throws {
        guard algorithm == .systemTimePitch else {
            throw AudioExportError.unsupportedAlgorithm
        }

        let isUnchangedExport =
            pitch == 0
            && speed == 1
            && volume == 1
            && sourceURL.pathExtension.lowercased() ==
                format.fileExtension.lowercased()

        if isUnchangedExport {
            if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
                try FileManager.default.copyItem(
                    at: sourceURL,
                    to: destinationURL
                )
            }
            return
        }

        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let sourceFormat = sourceFile.processingFormat

        guard sourceFormat.sampleRate > 0,
              sourceFormat.channelCount > 0 else {
            throw AudioExportError.invalidAudioFormat
        }

        let renderFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: sourceFormat.channelCount,
            interleaved: false
        )

        guard let renderFormat else {
            throw AudioExportError.invalidAudioFormat
        }

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()

        engine.attach(playerNode)
        engine.attach(timePitch)

        engine.connect(
            playerNode,
            to: timePitch,
            format: sourceFormat
        )
        engine.connect(
            timePitch,
            to: engine.mainMixerNode,
            format: renderFormat
        )
        engine.mainMixerNode.outputVolume = Float(
            min(max(volume, 0.0), 1.0)
        )

        timePitch.pitch = Float(
            min(max(pitch, -12.0), 12.0) * 100.0
        )
        timePitch.rate = Float(
            min(max(speed, 0.1), 3.0)
        )

        let maximumFrameCount: AVAudioFrameCount = 4096

        try engine.enableManualRenderingMode(
            .offline,
            format: renderFormat,
            maximumFrameCount: maximumFrameCount
        )

        playerNode.scheduleFile(
            sourceFile,
            at: nil
        )

        try engine.start()
        playerNode.play()

        let requiresExternalCodec =
            format == .mp3
            || format == .flac
            || format == .ogg
            || format == .aac

        let renderedWAVURL: URL?
        let outputURLForRender: URL

        if requiresExternalCodec {
            renderedWAVURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "AudioPlayerExport-\(UUID().uuidString)"
                )
                .appendingPathExtension("wav")
            outputURLForRender = renderedWAVURL!
        } else {
            renderedWAVURL = nil
            outputURLForRender = destinationURL
        }

        let outputSettings = try outputSettings(
            for: format == .mp3 || format == .flac || format == .ogg || format == .aac
                ? .wav
                : format,
            sourceFormat: renderFormat
        )

        let outputFile = try AVAudioFile(
            forWriting: outputURLForRender,
            settings: outputSettings
        )

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: renderFormat,
            frameCapacity: maximumFrameCount
        ) else {
            throw AudioExportError.renderFailed
        }

        let clampedSpeed = min(max(speed, 0.1), 3.0)
        let targetFrames = AVAudioFramePosition(
            ceil(
                Double(sourceFile.length) / clampedSpeed
            )
        )

        while engine.manualRenderingSampleTime < targetFrames {
            let remainingFrames =
                targetFrames - engine.manualRenderingSampleTime
            let framesToRender = min(
                AVAudioFrameCount(remainingFrames),
                maximumFrameCount
            )

            let status = try engine.renderOffline(
                framesToRender,
                to: buffer
            )

            if buffer.frameLength > 0 {
                try outputFile.write(from: buffer)
            }

            switch status {
            case .success:
                continue
            case .insufficientDataFromInputNode:
                continue
            case .cannotDoInCurrentContext:
                continue
            case .error:
                throw AudioExportError.renderFailed
            @unknown default:
                throw AudioExportError.renderFailed
            }
        }

        playerNode.stop()
        engine.stop()

        if let renderedWAVURL {
            defer {
                try? FileManager.default.removeItem(at: renderedWAVURL)
            }

            try encodeWithFFmpeg(
                inputURL: renderedWAVURL,
                destinationURL: destinationURL,
                format: format
            )
        }
    }

    private static func encodeWithFFmpeg(
        inputURL: URL,
        destinationURL: URL,
        format: AudioExportFormat
    ) throws {
        let bundledExecutable = Bundle.main.url(
            forResource: "ffmpeg",
            withExtension: nil
        )?.path

        guard let executablePath = bundledExecutable,
              FileManager.default.isExecutableFile(atPath: executablePath) else {
            // Release builds must use the FFmpeg executable shipped inside the
            // app bundle; never silently depend on Homebrew or another machine's
            // local installation.
            throw AudioExportError.codecBackendUnavailable
        }

        let codecArguments: [String]
        switch format {
        case .mp3:
            codecArguments = ["-c:a", "libmp3lame", "-b:a", "256k"]
        case .flac:
            codecArguments = ["-c:a", "flac"]
        case .ogg:
            codecArguments = [
                "-c:a", "vorbis",
                "-strict", "-2",
                "-ac", "2",
                "-q:a", "5"
            ]
        case .aac:
            codecArguments = ["-c:a", "aac", "-b:a", "256k"]
        case .wav, .aiff, .m4a:
            throw AudioExportError.unsupportedFormat
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", inputURL.path,
            "-vn"
        ] + codecArguments + [
            destinationURL.path
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw AudioExportError.codecBackendUnavailable
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail =
                String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

            throw AudioExportError.codecEncodingFailed(
                detail ?? "The codec backend failed to encode the export."
            )
        }
    }

    private static func outputSettings(
        for format: AudioExportFormat,
        sourceFormat: AVAudioFormat
    ) throws -> [String: Any] {
        switch format {
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sourceFormat.sampleRate,
                AVNumberOfChannelsKey: sourceFormat.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]

        case .aiff:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sourceFormat.sampleRate,
                AVNumberOfChannelsKey: sourceFormat.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: true,
                AVLinearPCMIsNonInterleaved: false
            ]

        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sourceFormat.sampleRate,
                AVNumberOfChannelsKey: sourceFormat.channelCount,
                AVEncoderBitRateKey: 256_000
            ]

        case .mp3, .flac, .ogg, .aac:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sourceFormat.sampleRate,
                AVNumberOfChannelsKey: sourceFormat.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
    }
}
