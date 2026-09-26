#include "../ggml/src/ggml-time.h"

#include <cstdint>

int main() {
    constexpr int64_t frequency = 10000000; // hAIlo's Windows QPC frequency
    constexpr int64_t seconds_11_days = 11 * 24 * 60 * 60;
    constexpr int64_t ticks_11_days = seconds_11_days * frequency;

    // The former ticks * 1000000 expression overflowed before this point.
    if (ggml_time_ticks_to_units(ticks_11_days, frequency, 1000000) != seconds_11_days * 1000000) return 1;
    if (ggml_time_ticks_to_units(ticks_11_days, frequency, 1000) != seconds_11_days * 1000) return 1;
    if (ggml_time_ticks_to_units(ticks_11_days + frequency / 2, frequency, 1000000) != seconds_11_days * 1000000 + 500000) return 1;
    if (ggml_time_ticks_to_units(ticks_11_days + frequency / 2, frequency, 1000) != seconds_11_days * 1000 + 500) return 1;

    // Preserve fractional conversion for clocks whose frequency is not a
    // multiple of the output scale.
    if (ggml_time_ticks_to_units(3579545 + 1789772, 3579545, 1000000) != 1499999) return 1;
    return 0;
}
