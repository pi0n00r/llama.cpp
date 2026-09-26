#pragma once

#include <stdint.h>

// Convert elapsed performance-counter ticks without multiplying the entire
// counter by the output scale. At 10 MHz, ticks * 1000000 overflows int64_t
// after 10.7 days even though the elapsed time in microseconds still fits.
static inline int64_t ggml_time_ticks_to_units(int64_t elapsed_ticks, int64_t ticks_per_second, int64_t units_per_second) {
    const int64_t whole_seconds = elapsed_ticks / ticks_per_second;
    const int64_t remaining_ticks = elapsed_ticks % ticks_per_second;
    return whole_seconds * units_per_second + remaining_ticks * units_per_second / ticks_per_second;
}
