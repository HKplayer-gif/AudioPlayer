import AVFAudio
import Foundation
import SoundTouchBridge

enum SoundTouchStreamError: Error {
    case unsupportedFormat
    case processorCreationFailed
    case invalidOutputFormat
}

public final class SoundTouchStreamSession: @unchecked Sendable {
    private let file: AVAudioFile
    private let sampleRate: Double
    private let channels: Int
    private let sourceFrameLimit: AVAudioFramePosition
    private let inputChunkFrames: AVAudioFrameCount = 4096
    private let outputChunkFrames: Int = 4096
    private let processor: OpaquePointer
    private let queue = DispatchQueue(
        label: "com.audioplayer.soundtouch.processing",
        qos: .userInitiated
    )

    private var nextSourceFrame: AVAudioFramePosition
    private var didFlush = false
    private var didReachEnd = false

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
            throw SoundTouchStreamError.unsupportedFormat
        }

        self.file = file
        sampleRate = format.sampleRate
        channels = Int(format.channelCount)
        sourceFrameLimit = file.length

        let clampedPosition = min(
            max(startPosition, 0.0),
            max(Double(file.length) / format.sampleRate, 0.0)
        )
        nextSourceFrame = AVAudioFramePosition(
            clampedPosition * format.sampleRate
        )

        guard let processor = apst_soundtouch_create(
            UInt32(format.sampleRate),
            UInt32(format.channelCount)
        ) else {
            throw SoundTouchStreamError.processorCreationFailed
        }

        self.processor = processor

        apst_soundtouch_set_tempo(
            processor,
            Float((min(max(speed, 0.1), 3.0) - 1.0) * 100.0)
        )
        apst_soundtouch_set_pitch_semitones(
            processor,
            Float(pitchSemitones)
        )

        file.framePosition = nextSourceFrame
    }

    deinit {
        apst_soundtouch_destroy(processor)
    }

    public func updateParameters(speed: Double, pitchSemitones: Double) {
        let clampedSpeed = min(max(speed, 0.1), 3.0)
        let clampedPitch = min(max(pitchSemitones, -12.0), 12.0)
        queue.async { [weak self] in
            guard let self, !self.didFlush else { return }
            apst_soundtouch_set_tempo(
                self.processor,
                Float((clampedSpeed - 1.0) * 100.0)
            )
            apst_soundtouch_set_pitch_semitones(
                self.processor,
                Float(clampedPitch)
            )
        }
    }

    /// Stops queued processing before another session can reuse the shared AVAudioFile.
    /// The serial queue is drained before this method returns.
    public func cancelAndWait() {
        queue.sync {
            didFlush = true
            didReachEnd = true
        }
    }

    public func requestBuffer(
        completion: @escaping @Sendable (AVAudioPCMBuffer?, Bool) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async {
                    completion(nil, true)
                }
                return
            }

            do {
                let result = try self.makeNextBuffer()
                DispatchQueue.main.async {
                    completion(result.buffer, result.isEnd)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil, true)
                }
            }
        }
    }

    private struct BufferResult {
        let buffer: AVAudioPCMBuffer?
        let isEnd: Bool
    }

    private func makeNextBuffer() throws -> BufferResult {
        while true {
            let available = Int(apst_soundtouch_num_samples(processor))

            if available > 0 {
                return try receiveBuffer(
                    frameCount: min(available, outputChunkFrames)
                )
            }

            if !didFlush {
                if nextSourceFrame < sourceFrameLimit {
                    let remaining = sourceFrameLimit - nextSourceFrame
                    let count = min(
                        AVAudioFrameCount(remaining),
                        inputChunkFrames
                    )

                    let input = AVAudioPCMBuffer(
                        pcmFormat: file.processingFormat,
                        frameCapacity: count
                    )

                    guard let input else {
                        throw SoundTouchStreamError.invalidOutputFormat
                    }

                    file.framePosition = nextSourceFrame
                    try file.read(into: input)

                    let framesRead = input.frameLength
                    guard framesRead > 0 else {
                        nextSourceFrame = sourceFrameLimit
                        continue
                    }

                    try feed(input)
                    nextSourceFrame += AVAudioFramePosition(framesRead)
                    continue
                }

                apst_soundtouch_flush(processor)
                didFlush = true
                continue
            }

            didReachEnd = true
            return BufferResult(buffer: nil, isEnd: true)
        }
    }

    private func feed(_ buffer: AVAudioPCMBuffer) throws {
        let frameCount = Int(buffer.frameLength)
        var interleaved = [Float](
            repeating: 0,
            count: frameCount * channels
        )

        if let channelData = buffer.floatChannelData {
            for frame in 0..<frameCount {
                for channel in 0..<channels {
                    interleaved[frame * channels + channel] =
                        channelData[channel][frame]
                }
            }
        } else if buffer.format.isInterleaved,
                  let audioBuffer = buffer.audioBufferList.pointee.mBuffers.mData {
            let samples = audioBuffer.assumingMemoryBound(to: Float.self)
            interleaved.withUnsafeMutableBufferPointer { destination in
                destination.baseAddress?.update(
                    from: samples,
                    count: frameCount * channels
                )
            }
        } else {
            throw SoundTouchStreamError.unsupportedFormat
        }

        interleaved.withUnsafeBufferPointer { source in
            apst_soundtouch_put_samples(
                processor,
                source.baseAddress,
                UInt32(frameCount)
            )
        }
    }

    private func receiveBuffer(frameCount: Int) throws -> BufferResult {
        let outputFormat = file.processingFormat

        guard outputFormat.commonFormat == .pcmFormatFloat32,
              let output = AVAudioPCMBuffer(
                  pcmFormat: outputFormat,
                  frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            throw SoundTouchStreamError.invalidOutputFormat
        }

        var interleaved = [Float](
            repeating: 0,
            count: frameCount * channels
        )

        let received = interleaved.withUnsafeMutableBufferPointer { destination in
            apst_soundtouch_receive_samples(
                processor,
                destination.baseAddress,
                UInt32(frameCount)
            )
        }

        guard received > 0 else {
            return BufferResult(buffer: nil, isEnd: didReachEnd)
        }

        if output.format.isInterleaved,
           let audioBuffer = output.mutableAudioBufferList.pointee.mBuffers.mData {
            let samples = audioBuffer.assumingMemoryBound(to: Float.self)
            interleaved.withUnsafeBufferPointer { source in
                samples.update(
                    from: source.baseAddress!,
                    count: Int(received) * channels
                )
            }
        } else if let channelData = output.floatChannelData {
            for frame in 0..<Int(received) {
                for channel in 0..<channels {
                    channelData[channel][frame] =
                        interleaved[frame * channels + channel]
                }
            }
        } else {
            throw SoundTouchStreamError.invalidOutputFormat
        }

        output.frameLength = AVAudioFrameCount(received)
        return BufferResult(buffer: output, isEnd: false)
    }
}
