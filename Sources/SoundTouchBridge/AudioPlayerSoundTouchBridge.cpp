#include "AudioPlayerSoundTouchBridge.h"
#include "SoundTouch.h"

struct APSTSoundTouch {
    soundtouch::SoundTouch processor;
};

extern "C" APSTSoundTouch *apst_soundtouch_create(uint32_t sampleRate, uint32_t channels) {
    if (sampleRate == 0 || channels == 0) return nullptr;
    auto *instance = new APSTSoundTouch();
    instance->processor.setSampleRate(sampleRate);
    instance->processor.setChannels(channels);
    return instance;
}

extern "C" void apst_soundtouch_destroy(APSTSoundTouch *instance) {
    delete instance;
}

extern "C" void apst_soundtouch_set_tempo(APSTSoundTouch *instance, float percent) {
    if (instance) instance->processor.setTempoChange(percent);
}

extern "C" void apst_soundtouch_set_pitch_semitones(APSTSoundTouch *instance, float semitones) {
    if (instance) instance->processor.setPitchSemiTones(semitones);
}

extern "C" void apst_soundtouch_put_samples(APSTSoundTouch *instance, const float *samples, uint32_t frames) {
    if (instance && samples && frames > 0) instance->processor.putSamples(samples, frames);
}

extern "C" uint32_t apst_soundtouch_receive_samples(APSTSoundTouch *instance, float *samples, uint32_t maxFrames) {
    if (!instance || !samples || maxFrames == 0) return 0;
    return instance->processor.receiveSamples(samples, maxFrames);
}

extern "C" void apst_soundtouch_flush(APSTSoundTouch *instance) {
    if (instance) instance->processor.flush();
}

extern "C" uint32_t apst_soundtouch_num_samples(APSTSoundTouch *instance) {
    return instance ? instance->processor.numSamples() : 0;
}
