#ifndef AUDIOPLAYER_ESSENTIA_BRIDGE_H
#define AUDIOPLAYER_ESSENTIA_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct APAnalysisResult APAnalysisResult;

// Essentia RhythmExtractor2013 requires 44.1 kHz mono input.
// The caller owns the returned result and must release it.
APAnalysisResult *ap_essentia_analyze_mono_44100(
    const float *samples,
    size_t sample_count,
    const char *rhythm_method
);

const char *ap_essentia_result_key(const APAnalysisResult *result);
const char *ap_essentia_result_scale(const APAnalysisResult *result);
const char *ap_essentia_result_error(const APAnalysisResult *result);
float ap_essentia_result_key_strength(const APAnalysisResult *result);
float ap_essentia_result_bpm(const APAnalysisResult *result);
float ap_essentia_result_bpm_confidence(const APAnalysisResult *result);
size_t ap_essentia_result_beat_count(const APAnalysisResult *result);
size_t ap_essentia_result_copy_beats(
    const APAnalysisResult *result,
    double *destination,
    size_t capacity
);
void ap_essentia_result_destroy(APAnalysisResult *result);

#ifdef __cplusplus
}
#endif

#endif
