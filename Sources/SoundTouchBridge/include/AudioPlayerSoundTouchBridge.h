#ifndef AudioPlayerSoundTouchBridge_h
#define AudioPlayerSoundTouchBridge_h
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct APSTSoundTouch APSTSoundTouch;
APSTSoundTouch *apst_soundtouch_create(uint32_t sampleRate, uint32_t channels);
void apst_soundtouch_destroy(APSTSoundTouch *instance);
void apst_soundtouch_set_tempo(APSTSoundTouch *instance, float percent);
void apst_soundtouch_set_pitch_semitones(APSTSoundTouch *instance, float semitones);
void apst_soundtouch_put_samples(APSTSoundTouch *instance, const float *samples, uint32_t frames);
uint32_t apst_soundtouch_receive_samples(APSTSoundTouch *instance, float *samples, uint32_t maxFrames);
void apst_soundtouch_flush(APSTSoundTouch *instance);
uint32_t apst_soundtouch_num_samples(APSTSoundTouch *instance);
#ifdef __cplusplus
}
#endif
#endif
