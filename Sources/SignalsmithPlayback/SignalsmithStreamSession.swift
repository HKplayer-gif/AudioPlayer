import AVFAudio
import Foundation
import SignalsmithBridge

enum SignalsmithStreamError: Error {
    case unsupportedFormat
    case processorCreationFailed
    case invalidOutputFormat
    case processingFailed
}

public final class SignalsmithStreamSession: @unchecked Sendable {
    private let file: AVAudioFile
    private let sampleRate: Double
    private let channels: Int
    private var playbackSpeed: Double
    private let sourceFrameLimit: AVAudioFramePosition
    private let inputChunkFrames: AVAudioFrameCount = 2048
    private let processor: OpaquePointer
    private let queue = DispatchQueue(
        label: "com.audioplayer.signalsmith.processing",
        qos: .userInitiated
    )

    private var nextSourceFrame: AVAudioFramePosition
    private var initialFramesToDiscard: Int
    private var didFlush = false

    public init(
        file: AVAudioFile,
        startPosition: TimeInterval,
        speed: Double,
        pitchSemitones: Double
    ) throws {
        let format = file.processingFormat
        guard format.sampleRate > 0,
              format.channelCount > 0,
              format.commonFormat == .pcmFormatFloat32 else {
            throw SignalsmithStreamError.unsupportedFormat
        }

        self.file = file
        sampleRate = format.sampleRate
        channels = Int(format.channelCount)
        playbackSpeed = min(max(speed, 0.1), 3.0)
        sourceFrameLimit = file.length

        let clampedPosition = min(
            max(startPosition, 0.0),
            max(Double(file.length) / format.sampleRate, 0.0)
        )
        nextSourceFrame = AVAudioFramePosition(
            clampedPosition * format.sampleRate
        )

        guard let processor = apss_create(
            UInt32(format.sampleRate),
            UInt32(format.channelCount),
            Float(min(max(speed, 0.1), 3.0)),
            Float(pitchSemitones)
        ) else {
            throw SignalsmithStreamError.processorCreationFailed
        }
        self.processor = processor
        initialFramesToDiscard = max(Int(apss_initial_trim_frames(processor)), 0)

        let seekLength = max(Int(apss_seek_length(processor)), 0)
        let prerollStart = max(nextSourceFrame - AVAudioFramePosition(seekLength), 0)
        let prerollCount = AVAudioFrameCount(nextSourceFrame - prerollStart)

        if prerollCount > 0 {
            guard let preroll = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: prerollCount
            ) else {
                apss_destroy(processor)
                throw SignalsmithStreamError.invalidOutputFormat
            }
            file.framePosition = prerollStart
            try file.read(into: preroll)
            let interleaved = try Self.interleave(preroll, channels: channels)
            let result = interleaved.withUnsafeBufferPointer { source in
                apss_seek(
                    processor,
                    source.baseAddress,
                    UInt32(preroll.frameLength),
                    Float(min(max(speed, 0.1), 3.0))
                )
            }
            guard result >= 0 else {
                apss_destroy(processor)
                throw SignalsmithStreamError.processingFailed
            }
        } else {
            let result = apss_seek(processor, nil, 0, Float(min(max(speed, 0.1), 3.0)))
            guard result >= 0 else {
                apss_destroy(processor)
                throw SignalsmithStreamError.processingFailed
            }
        }

        file.framePosition = nextSourceFrame
    }

    deinit {
        apss_destroy(processor)
    }

    public func updateParameters(speed: Double, pitchSemitones: Double) {
        let clampedSpeed = min(max(speed, 0.1), 3.0)
        let clampedPitch = min(max(pitchSemitones, -12.0), 12.0)
        queue.async { [weak self] in
            guard let self, !self.didFlush else { return }
            let result = apss_set_parameters(
                self.processor,
                Float(clampedSpeed),
                Float(clampedPitch)
            )
            guard result >= 0 else { return }
            self.playbackSpeed = clampedSpeed
        }
    }

    /// Stops queued processing before another session can reuse the shared AVAudioFile.
    /// The serial queue is drained before this method returns.
    public func cancelAndWait() {
        queue.sync {
            didFlush = true
        }
    }

    public func requestBuffer(
        completion: @escaping @Sendable (AVAudioPCMBuffer?, Bool) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil, true) }
                return
            }

            do {
                let result = try self.makeNextBuffer()
                DispatchQueue.main.async {
                    completion(result.buffer, result.isEnd)
                }
            } catch {
                DispatchQueue.main.async { completion(nil, true) }
            }
        }
    }

    private struct BufferResult {
        let buffer: AVAudioPCMBuffer?
        let isEnd: Bool
    }

    private func makeNextBuffer() throws -> BufferResult {
        if nextSourceFrame < sourceFrameLimit {
            let remaining = sourceFrameLimit - nextSourceFrame
            let count = min(AVAudioFrameCount(remaining), inputChunkFrames)
            guard let input = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: count
            ) else {
                throw SignalsmithStreamError.invalidOutputFormat
            }

            file.framePosition = nextSourceFrame
            try file.read(into: input)
            let framesRead = input.frameLength
            guard framesRead > 0 else {
                nextSourceFrame = sourceFrameLimit
                return try makeNextBuffer()
            }

            let interleavedInput = try Self.interleave(input, channels: channels)
            // Signalsmith output length scales with 1 / playback speed.
            // Allocate for the active speed instead of reserving the 0.1x worst
            // case on every chunk, which caused avoidable allocation pressure
            // during ordinary-speed playback.
            let outputCapacity = max(
                Int(ceil(Double(framesRead) / playbackSpeed)) + 16,
                64
            )
            var interleavedOutput = [Float](
                repeating: 0,
                count: outputCapacity * channels
            )
            let outputFrames = interleavedInput.withUnsafeBufferPointer { source in
                interleavedOutput.withUnsafeMutableBufferPointer { destination in
                    apss_process(
                        processor,
                        source.baseAddress,
                        UInt32(framesRead),
                        destination.baseAddress,
                        UInt32(outputCapacity)
                    )
                }
            }
            guard outputFrames > 0 else {
                throw SignalsmithStreamError.processingFailed
            }
            nextSourceFrame += AVAudioFramePosition(framesRead)
            let trimmed = trimInitialLatency(
                interleavedOutput,
                frames: Int(outputFrames)
            )
            guard trimmed.frames > 0 else {
                return try makeNextBuffer()
            }
            return BufferResult(
                buffer: try Self.makeBuffer(
                    trimmed.samples,
                    frames: trimmed.frames,
                    format: file.processingFormat,
                    channels: channels
                ),
                isEnd: false
            )
        }

        if !didFlush {
            didFlush = true
            var interleavedOutput = [Float](repeating: 0, count: 65_536 * channels)
            let outputFrames = interleavedOutput.withUnsafeMutableBufferPointer { destination in
                apss_finish(processor, destination.baseAddress, 65_536)
            }
            guard outputFrames >= 0 else {
                throw SignalsmithStreamError.processingFailed
            }
            guard outputFrames > 0 else {
                return BufferResult(buffer: nil, isEnd: true)
            }
            let trimmed = trimInitialLatency(
                interleavedOutput,
                frames: Int(outputFrames)
            )
            guard trimmed.frames > 0 else {
                return BufferResult(buffer: nil, isEnd: true)
            }
            return BufferResult(
                buffer: try Self.makeBuffer(
                    trimmed.samples,
                    frames: trimmed.frames,
                    format: file.processingFormat,
                    channels: channels
                ),
                isEnd: false
            )
        }

        return BufferResult(buffer: nil, isEnd: true)
    }

    private func trimInitialLatency(
        _ samples: [Float],
        frames: Int
    ) -> (samples: [Float], frames: Int) {
        let discardedFrames = min(initialFramesToDiscard, frames)
        initialFramesToDiscard -= discardedFrames
        let remainingFrames = frames - discardedFrames
        guard remainingFrames > 0 else {
            return ([], 0)
        }
        let start = discardedFrames * channels
        let end = frames * channels
        return (Array(samples[start..<end]), remainingFrames)
    }

    private static func interleave(
        _ buffer: AVAudioPCMBuffer,
        channels: Int
    ) throws -> [Float] {
        let frames = Int(buffer.frameLength)
        var interleaved = [Float](repeating: 0, count: frames * channels)
        if let channelData = buffer.floatChannelData {
            for frame in 0..<frames {
                for channel in 0..<channels {
                    interleaved[frame * channels + channel] = channelData[channel][frame]
                }
            }
        } else if buffer.format.isInterleaved,
                  let data = buffer.audioBufferList.pointee.mBuffers.mData {
            let samples = data.assumingMemoryBound(to: Float.self)
            interleaved.withUnsafeMutableBufferPointer { destination in
                destination.baseAddress?.update(from: samples, count: frames * channels)
            }
        } else {
            throw SignalsmithStreamError.unsupportedFormat
        }
        return interleaved
    }

    private static func makeBuffer(
        _ interleaved: [Float],
        frames: Int,
        format: AVAudioFormat,
        channels: Int
    ) throws -> AVAudioPCMBuffer {
        guard format.commonFormat == .pcmFormatFloat32,
              let output = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frames)
              ) else {
            throw SignalsmithStreamError.invalidOutputFormat
        }

        if format.isInterleaved,
           let data = output.mutableAudioBufferList.pointee.mBuffers.mData {
            let samples = data.assumingMemoryBound(to: Float.self)
            interleaved.withUnsafeBufferPointer { source in
                samples.update(from: source.baseAddress!, count: frames * channels)
            }
        } else if let channelData = output.floatChannelData {
            for frame in 0..<frames {
                for channel in 0..<channels {
                    channelData[channel][frame] = interleaved[frame * channels + channel]
                }
            }
        } else {
            throw SignalsmithStreamError.invalidOutputFormat
        }
        output.frameLength = AVAudioFrameCount(frames)
        return output
    }
}
