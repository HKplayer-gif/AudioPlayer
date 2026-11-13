#include "EssentiaBridge.h"

#include <algorithm>
#include <cmath>
#include <exception>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include <essentia/essentia.h>
#include <essentia/algorithmfactory.h>

struct APAnalysisResult {
    std::string key;
    std::string scale;
    std::string error;
    float keyStrength = 0.0f;
    float bpm = 0.0f;
    float bpmConfidence = 0.0f;
    std::vector<double> beatTimes;
};

namespace {

std::once_flag gEssentiaInitialization;
std::mutex gAnalysisMutex;

void initializeEssentia() {
    std::call_once(gEssentiaInitialization, [] {
        essentia::init();
    });
}

void setError(APAnalysisResult *result, const char *message) {
    if (result) {
        result->error = message ? message : "Unknown Essentia error";
    }
}

} // namespace

extern "C" APAnalysisResult *ap_essentia_analyze_mono_44100(
    const float *samples,
    size_t sample_count,
    const char *rhythm_method
) {
    std::unique_ptr<APAnalysisResult> result(new APAnalysisResult());

    if (!samples || sample_count < 44100) {
        setError(result.get(), "Audio is empty or shorter than one second.");
        return result.release();
    }

    const char *method = (rhythm_method && rhythm_method[0] != '\0')
        ? rhythm_method
        : "multifeature";

    if (std::string(method) != "multifeature" && std::string(method) != "degara") {
        setError(result.get(), "Unsupported RhythmExtractor2013 method.");
        return result.release();
    }

    try {
        initializeEssentia();
        std::lock_guard<std::mutex> lock(gAnalysisMutex);

        std::vector<essentia::Real> audio;
        audio.reserve(sample_count);
        for (size_t i = 0; i < sample_count; ++i) {
            const float sample = samples[i];
            audio.push_back(std::isfinite(sample) ? sample : 0.0f);
        }

        using essentia::standard::Algorithm;
        using essentia::standard::AlgorithmFactory;

        std::unique_ptr<Algorithm> rhythm(
            AlgorithmFactory::create("RhythmExtractor2013", "method", method)
        );

        std::vector<essentia::Real> ticks;
        std::vector<essentia::Real> estimates;
        std::vector<essentia::Real> intervals;

        rhythm->input("signal").set(audio);
        rhythm->output("bpm").set(result->bpm);
        rhythm->output("ticks").set(ticks);
        rhythm->output("confidence").set(result->bpmConfidence);
        rhythm->output("estimates").set(estimates);
        rhythm->output("bpmIntervals").set(intervals);
        rhythm->compute();

        result->beatTimes.reserve(ticks.size());
        for (const auto tick : ticks) {
            if (std::isfinite(tick) && tick >= 0.0f) {
                result->beatTimes.push_back(static_cast<double>(tick));
            }
        }

        std::unique_ptr<Algorithm> keyExtractor(
            AlgorithmFactory::create("KeyExtractor", "sampleRate", 44100.0)
        );

        keyExtractor->input("audio").set(audio);
        keyExtractor->output("key").set(result->key);
        keyExtractor->output("scale").set(result->scale);
        keyExtractor->output("strength").set(result->keyStrength);
        keyExtractor->compute();

        if (!std::isfinite(result->bpm) || result->bpm <= 0.0f) {
            setError(result.get(), "Essentia did not produce a valid BPM estimate.");
        } else if (result->key.empty() || result->scale.empty()) {
            setError(result.get(), "Essentia did not produce a valid key estimate.");
        }
    } catch (const std::exception &error) {
        setError(result.get(), error.what());
    } catch (...) {
        setError(result.get(), "Unknown exception while running Essentia analysis.");
    }

    return result.release();
}

extern "C" const char *ap_essentia_result_key(const APAnalysisResult *result) {
    return result ? result->key.c_str() : "";
}

extern "C" const char *ap_essentia_result_scale(const APAnalysisResult *result) {
    return result ? result->scale.c_str() : "";
}

extern "C" const char *ap_essentia_result_error(const APAnalysisResult *result) {
    return result ? result->error.c_str() : "Missing Essentia analysis result.";
}

extern "C" float ap_essentia_result_key_strength(const APAnalysisResult *result) {
    return result ? result->keyStrength : 0.0f;
}

extern "C" float ap_essentia_result_bpm(const APAnalysisResult *result) {
    return result ? result->bpm : 0.0f;
}

extern "C" float ap_essentia_result_bpm_confidence(const APAnalysisResult *result) {
    return result ? result->bpmConfidence : 0.0f;
}

extern "C" size_t ap_essentia_result_beat_count(const APAnalysisResult *result) {
    return result ? result->beatTimes.size() : 0;
}

extern "C" size_t ap_essentia_result_copy_beats(
    const APAnalysisResult *result,
    double *destination,
    size_t capacity
) {
    if (!result || !destination) {
        return 0;
    }

    const size_t count = std::min(capacity, result->beatTimes.size());
    std::copy_n(result->beatTimes.begin(), count, destination);
    return count;
}

extern "C" void ap_essentia_result_destroy(APAnalysisResult *result) {
    delete result;
}
