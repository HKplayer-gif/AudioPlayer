#ifndef AudioPlayerSignalsmithBridge_h
#define AudioPlayerSignalsmithBridge_h
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct APSSignalsmith APSSignalsmith;
APSSignalsmith *apss_create(uint32_t sampleRate, uint32_t channels, float speed, float pitchSemitones);
void apss_destroy(APSSignalsmith *instance);
int32_t apss_set_parameters(APSSignalsmith *instance, float speed, float pitchSemitones);
int32_t apss_seek_length(APSSignalsmith *instance);
int32_t apss_initial_trim_frames(APSSignalsmith *instance);
int32_t apss_seek(APSSignalsmith *instance, const float *interleaved, uint32_t frames, float speed);
int32_t apss_process(APSSignalsmith *instance, const float *input, uint32_t inputFrames, float *output, uint32_t outputCapacityFrames);
int32_t apss_finish(APSSignalsmith *instance, float *output, uint32_t outputCapacityFrames);
#ifdef __cplusplus
}
#endif
#endif
