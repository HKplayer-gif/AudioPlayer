#include "AudioPlayerSignalsmithBridge.h"
#include "signalsmith-stretch.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

struct APSSignalsmith {
    uint32_t channels = 0;
    float speed = 1.0f;
    double outputRemainder = 0.0;
    bool finished = false;
    signalsmith::stretch::SignalsmithStretch<float> processor;
    std::vector<std::vector<float>> inputChannels;
    std::vector<std::vector<float>> outputChannels;
    std::vector<float *> inputPointers;
    std::vector<float *> outputPointers;

    APSSignalsmith(uint32_t sampleRate, uint32_t channelCount, float playbackSpeed, float pitch)
        : channels(channelCount), speed(playbackSpeed),
          inputChannels(channelCount), outputChannels(channelCount),
          inputPointers(channelCount), outputPointers(channelCount) {
        processor.presetDefault(static_cast<int>(channels), static_cast<float>(sampleRate), true);
        processor.setTransposeSemitones(pitch);
    }

    int32_t process(const float *input, uint32_t inputFrames, float *output, uint32_t outputCapacityFrames) {
        if (!input || !output || inputFrames == 0 || finished) return 0;
        const double exactOutput = static_cast<double>(inputFrames) / std::max(0.1f, speed) + outputRemainder;
        const uint32_t outputFrames = static_cast<uint32_t>(std::max(1.0, std::floor(exactOutput)));
        outputRemainder = exactOutput - outputFrames;
        if (outputFrames > outputCapacityFrames) return -1;

        for (uint32_t channel = 0; channel < channels; ++channel) {
            inputChannels[channel].resize(inputFrames);
            outputChannels[channel].resize(outputFrames);
            for (uint32_t frame = 0; frame < inputFrames; ++frame) {
                inputChannels[channel][frame] = input[frame * channels + channel];
            }
            inputPointers[channel] = inputChannels[channel].data();
            outputPointers[channel] = outputChannels[channel].data();
        }

        processor.process(inputPointers.data(), static_cast<int>(inputFrames),
                          outputPointers.data(), static_cast<int>(outputFrames));

        for (uint32_t frame = 0; frame < outputFrames; ++frame) {
            for (uint32_t channel = 0; channel < channels; ++channel) {
                output[frame * channels + channel] = outputChannels[channel][frame];
            }
        }
        return static_cast<int32_t>(outputFrames);
    }
};

extern "C" APSSignalsmith *apss_create(uint32_t sampleRate, uint32_t channels, float speed, float pitchSemitones) {
    if (sampleRate == 0 || channels == 0 || channels > 8 || !std::isfinite(speed) || !std::isfinite(pitchSemitones)) return nullptr;
    try {
        return new APSSignalsmith(sampleRate, channels, std::max(0.1f, std::min(speed, 3.0f)), pitchSemitones);
    } catch (...) {
        return nullptr;
    }
}

extern "C" void apss_destroy(APSSignalsmith *instance) {
    delete instance;
}

extern "C" int32_t apss_set_parameters(APSSignalsmith *instance, float speed, float pitchSemitones) {
    if (!instance || instance->finished || !std::isfinite(speed) || !std::isfinite(pitchSemitones)) return -1;
    instance->speed = std::max(0.1f, std::min(speed, 3.0f));
    instance->processor.setTransposeSemitones(pitchSemitones);
    return 0;
}

extern "C" int32_t apss_seek_length(APSSignalsmith *instance) {
    return instance ? instance->processor.seekLength() : 0;
}

extern "C" int32_t apss_initial_trim_frames(APSSignalsmith *instance) {
    if (!instance) return 0;
    const double leadingLatency = std::ceil(
        instance->processor.inputLatency() / static_cast<double>(instance->speed)
    );
    return static_cast<int32_t>(leadingLatency) + instance->processor.outputLatency();
}

extern "C" int32_t apss_seek(APSSignalsmith *instance, const float *interleaved, uint32_t frames, float speed) {
    if (!instance || (frames > 0 && !interleaved) || !std::isfinite(speed)) return -1;
    const uint32_t channels = instance->channels;
    const int32_t seekLength = instance->processor.seekLength();
    for (uint32_t channel = 0; channel < channels; ++channel) {
        instance->inputChannels[channel].assign(static_cast<size_t>(seekLength), 0.0f);
        const uint32_t available = std::min<uint32_t>(frames, static_cast<uint32_t>(seekLength));
        const uint32_t start = frames - available;
        const uint32_t pad = static_cast<uint32_t>(seekLength) - available;
        for (uint32_t frame = 0; frame < available; ++frame) {
            instance->inputChannels[channel][pad + frame] = interleaved[(start + frame) * channels + channel];
        }
        instance->inputPointers[channel] = instance->inputChannels[channel].data();
    }
    instance->processor.seek(instance->inputPointers.data(), seekLength, std::max(0.1, std::min(static_cast<double>(speed), 3.0)));
    instance->speed = std::max(0.1f, std::min(speed, 3.0f));
    return 0;
}

extern "C" int32_t apss_process(APSSignalsmith *instance, const float *input, uint32_t inputFrames, float *output, uint32_t outputCapacityFrames) {
    if (!instance) return -1;
    return instance->process(input, inputFrames, output, outputCapacityFrames);
}

extern "C" int32_t apss_finish(APSSignalsmith *instance, float *output, uint32_t outputCapacityFrames) {
    if (!instance || !output || instance->finished) return 0;
    const uint32_t channels = instance->channels;
    const int32_t inputLatency = instance->processor.inputLatency();
    const int32_t outputLatency = instance->processor.outputLatency();
    const uint32_t silenceOutputFrames = static_cast<uint32_t>(std::max(1.0, std::ceil(inputLatency / static_cast<double>(instance->speed))));
    const uint32_t totalFrames = silenceOutputFrames + static_cast<uint32_t>(outputLatency);
    if (totalFrames > outputCapacityFrames) return -1;

    std::vector<std::vector<float>> silenceInput(channels, std::vector<float>(static_cast<size_t>(inputLatency), 0.0f));
    std::vector<std::vector<float>> finishOutput(channels, std::vector<float>(totalFrames, 0.0f));
    std::vector<float *> inPointers(channels), outPointers(channels);
    for (uint32_t channel = 0; channel < channels; ++channel) {
        inPointers[channel] = silenceInput[channel].data();
        outPointers[channel] = finishOutput[channel].data();
    }
    instance->processor.process(inPointers.data(), inputLatency, outPointers.data(), static_cast<int>(silenceOutputFrames));

    std::vector<float *> tailPointers(channels);
    for (uint32_t channel = 0; channel < channels; ++channel) {
        tailPointers[channel] = finishOutput[channel].data() + silenceOutputFrames;
    }
    instance->processor.flush(tailPointers.data(), outputLatency, instance->speed);

    for (uint32_t frame = 0; frame < totalFrames; ++frame) {
        for (uint32_t channel = 0; channel < channels; ++channel) {
            output[frame * channels + channel] = finishOutput[channel][frame];
        }
    }
    instance->finished = true;
    return static_cast<int32_t>(totalFrames);
}
