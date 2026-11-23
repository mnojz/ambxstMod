#!/usr/bin/env python3
"""Send normalized playback spectrum frames to the lock screen.

The FFT band weighting, automatic sensitivity and falloff are adapted from
CAVA 1.0.0 (https://github.com/karlstav/cava/blob/1.0.0/cavacore.c).

Copyright (c) 2015, 2022 Karl Stavestrand <karl@stavestrand.no>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

from array import array
from bisect import bisect_left
import ctypes as ct
import math
import sys


SAMPLE_RATE = 48_000
FRAME_SAMPLES = 800
CHANNELS = 2
BANDS_PER_CHANNEL = 96
SPECTRUM_MINIMUM = 50
BASS_SPLIT = 100
CENTER_BASS_LIMIT = 180
KICK_DISPLAY_WIDTH = 0.16
MAX_FREQUENCY = 20_000
BASS_WINDOW = 8_192
MAIN_WINDOW = 4_096
NOISE_REDUCTION = 0.77
PULSE_RECORD = 2
PULSE_SIGNED_16 = 3 if sys.byteorder == "little" else 4
FFTW_ESTIMATE = 1 << 6


class SampleSpec(ct.Structure):
    _fields_ = [("format", ct.c_int), ("rate", ct.c_uint32), ("channels", ct.c_uint8)]


class BufferAttributes(ct.Structure):
    _fields_ = [(name, ct.c_uint32) for name in ("maxlength", "tlength", "prebuf", "minreq", "fragsize")]


class PlaybackMonitor:
    def __init__(self):
        self.pulse = ct.CDLL("libpulse-simple.so.0")
        self.pulse.pa_simple_new.argtypes = [
            ct.c_char_p, ct.c_char_p, ct.c_int, ct.c_char_p, ct.c_char_p,
            ct.POINTER(SampleSpec), ct.c_void_p, ct.POINTER(BufferAttributes), ct.POINTER(ct.c_int),
        ]
        self.pulse.pa_simple_new.restype = ct.c_void_p
        self.pulse.pa_simple_read.argtypes = [ct.c_void_p, ct.c_void_p, ct.c_size_t, ct.POINTER(ct.c_int)]
        self.pulse.pa_simple_read.restype = ct.c_int
        self.pulse.pa_simple_free.argtypes = [ct.c_void_p]
        self.pulse.pa_simple_free.restype = None

        self.buffer = ct.create_string_buffer(FRAME_SAMPLES * CHANNELS * ct.sizeof(ct.c_int16))
        self.error = ct.c_int()
        spec = SampleSpec(PULSE_SIGNED_16, SAMPLE_RATE, CHANNELS)
        default = ct.c_uint32(-1).value
        attributes = BufferAttributes(default, default, default, default, len(self.buffer))
        self.stream = self.pulse.pa_simple_new(
            None, b"Ambxst Lock Screen", PULSE_RECORD, b"@DEFAULT_MONITOR@", b"Audio visualizer",
            ct.byref(spec), None, ct.byref(attributes), ct.byref(self.error),
        )
        if not self.stream:
            raise OSError(f"Could not open the default playback monitor (PulseAudio error {self.error.value})")

    def read(self):
        if self.pulse.pa_simple_read(self.stream, self.buffer, len(self.buffer), ct.byref(self.error)) < 0:
            raise OSError(f"Playback monitor read failed (PulseAudio error {self.error.value})")
        return array("h", self.buffer.raw)

    def close(self):
        self.pulse.pa_simple_free(self.stream)


class FrequencyWindow:
    def __init__(self, fftw, size):
        self.fftw = fftw
        self.size = size
        self.bin_width = SAMPLE_RATE / size
        self.input = (ct.c_float * size)()
        self.output = (ct.c_float * (size + 2))()
        self.plan = fftw.fftwf_plan_dft_r2c_1d(size, self.input, self.output, FFTW_ESTIMATE)
        if not self.plan:
            raise RuntimeError(f"Could not create a {size}-sample FFT plan")

        self.window = [0.5 * (1 - math.cos(math.tau * index / (size - 1))) for index in range(size)]

    def update(self, samples):
        self.input[:] = [sample * coefficient for sample, coefficient in zip(samples, self.window)]
        self.fftw.fftwf_execute(self.plan)

    def band(self, first, last):
        return sum(self.magnitude(index) for index in range(first, last + 1))

    def magnitude(self, index):
        return math.hypot(self.output[2 * index], self.output[2 * index + 1])

    def close(self):
        self.fftw.fftwf_destroy_plan(self.plan)


class Spectrum:
    def __init__(self):
        fftw = ct.CDLL("libfftw3f.so.3")
        fftw.fftwf_plan_dft_r2c_1d.argtypes = [ct.c_int, ct.c_void_p, ct.c_void_p, ct.c_uint]
        fftw.fftwf_plan_dft_r2c_1d.restype = ct.c_void_p
        for function in (fftw.fftwf_execute, fftw.fftwf_destroy_plan):
            function.argtypes = [ct.c_void_p]
            function.restype = None

        self.bass = FrequencyWindow(fftw, BASS_WINDOW)
        self.main = FrequencyWindow(fftw, MAIN_WINDOW)
        self.history = [array("h", [0]) * BASS_WINDOW for _ in range(CHANNELS)]
        self.bands = self.make_bands()
        frequencies = [first * window.bin_width for window, first, _, _ in self.bands]
        self.center_band_count = bisect_left(frequencies, CENTER_BASS_LIMIT)
        self.display_bins = self.make_display_bins(frequencies)
        # Two extra envelopes represent sub-bass below CAVA's lowest band.
        size = BANDS_PER_CHANNEL * CHANNELS + CHANNELS
        self.previous = [0.0] * size
        self.peaks = [0.0] * size
        self.fall_frames = [0] * size
        self.levels = [0.0] * size
        self.sensitivity = 1.0
        self.calibrating = True
        self.frame_rate = 75.0

    def make_bands(self):
        lows = []
        highs = []
        windows = []
        cutoffs = []
        ratio = MAX_FREQUENCY / SPECTRUM_MINIMUM
        for index in range(BANDS_PER_CHANNEL + 1):
            frequency = ct.c_float(SPECTRUM_MINIMUM * ratio ** (index / BANDS_PER_CHANNEL)).value
            if cutoffs and frequency <= cutoffs[-1]:
                frequency = cutoffs[-1] + int(self.bass.bin_width)
            window = self.bass if frequency < BASS_SPLIT else self.main
            value = frequency / window.bin_width
            first = int(value) if window is self.bass else math.ceil(value)
            first = min(window.size // 2, first)
            if windows:
                previous_window = windows[-1]
                if previous_window is window:
                    if first <= lows[-1] < window.size // 2:
                        first = lows[-1] + 1
                    highs.append(first - 1)
                else:
                    highs.append(max(lows[-1] + 1, int(frequency / previous_window.bin_width - 1)))
            lows.append(first)
            windows.append(window)
            cutoffs.append(ct.c_float(first * window.bin_width).value)

        bands = []
        for index, last in enumerate(highs):
            window = windows[index]
            first = lows[index]
            width = last - first + 1
            eq = cutoffs[index + 1] ** 0.85 / (2**28 * math.log2(window.size) * width)
            bands.append((window, first, last, eq))
        return bands

    def make_display_bins(self, frequencies):
        # Positions are measured outward from the center on each half.
        # Give the upper frequencies more space than the analysis bands do.
        anchors = [
            (0.0, 0),
            (KICK_DISPLAY_WIDTH, self.center_band_count),
            (0.32, bisect_left(frequencies, 600)),
            (0.55, bisect_left(frequencies, 2_500)),
            (0.72, bisect_left(frequencies, 6_000)),
            (1.0, BANDS_PER_CHANNEL - 1),
        ]

        def source_position(position):
            for (left, first), (right, last) in zip(anchors, anchors[1:]):
                if position <= right:
                    return first + (last - first) * (position - left) / (right - left)
            return anchors[-1][1]

        bins = []
        for index in range(BANDS_PER_CHANNEL):
            position = index / (BANDS_PER_CHANNEL - 1)
            half_step = 0.5 / (BANDS_PER_CHANNEL - 1)
            source = source_position(position)
            first = math.ceil(source_position(max(0.0, position - half_step)))
            end = math.floor(source_position(min(1.0, position + half_step))) + 1
            shoulder = 0.0
            if position < KICK_DISPLAY_WIDTH:
                shoulder = 0.5 * (1 + math.cos(math.pi * position / KICK_DISPLAY_WIDTH))
            bins.append((source, first, end, shoulder))
        return bins

    def display_half(self, levels, sub_bass):
        kick = min(1.0, max(sub_bass, *levels[:self.center_band_count]))
        kick = 1 - (1 - kick) ** 1.55
        result = []
        for source, first, end, shoulder in self.display_bins:
            left = int(source)
            right = min(BANDS_PER_CHANNEL - 1, left + 1)
            mix = levels[left] + (levels[right] - levels[left]) * (source - left)
            # Preserve a narrow peak if several source bands fit into one pixel region.
            peak = max(levels[first:end], default=0.0)
            result.append(round(min(1.0, max(mix, peak, kick * shoulder)) * 1000))
        return result

    def channel_magnitudes(self, channel, samples):
        history = self.history[channel][len(samples):] + samples
        self.history[channel] = history
        self.bass.update(history)
        self.main.update(history[-MAIN_WINDOW:])
        bands = [window.band(first, last) * eq for window, first, last, eq in self.bands]
        # Keep the lowest bass frequencies in the display and exclude static DC.
        end = self.bands[0][1] - 1
        sub_bass_eq = SPECTRUM_MINIMUM ** 0.85 / (2**28 * math.log2(self.bass.size))
        sub_bass = max(self.bass.magnitude(index) for index in range(1, end + 1)) * sub_bass_eq
        return bands, sub_bass

    def update(self, samples):
        left, sub_left = self.channel_magnitudes(0, samples[::CHANNELS])
        right, sub_right = self.channel_magnitudes(1, samples[1::CHANNELS])
        magnitudes = left + right + [sub_left, sub_right]
        self.frame_rate += (SAMPLE_RATE * CHANNELS / len(samples) - self.frame_rate) / 64
        rate_factor = 66 / self.frame_rate
        gravity = 2 * rate_factor ** 2.5 / NOISE_REDUCTION
        memory_weight = NOISE_REDUCTION / rate_factor ** 0.1

        overshoot = False
        for index, magnitude in enumerate(magnitudes):
            level = magnitude * self.sensitivity
            if level < self.previous[index]:
                age = 0.028 * self.fall_frames[index]
                level = self.peaks[index] * max(0.0, 1.0 - gravity * age * age)
                self.fall_frames[index] += 1
            else:
                self.peaks[index] = level
                self.fall_frames[index] = 0
            self.previous[index] = level

            self.levels[index] = level + self.levels[index] * memory_weight
            if index < BANDS_PER_CHANNEL * CHANNELS and self.levels[index] > 1:
                overshoot = True

        if overshoot:
            self.sensitivity *= 1 - 0.02 * rate_factor
            self.calibrating = False
        elif any(samples):
            self.sensitivity *= 1 + 0.001 * rate_factor
            if self.calibrating:
                self.sensitivity *= 1 + 0.1 * rate_factor
            self.sensitivity = min(self.sensitivity, 100_000)

        # Shape each side independently after gain and decay.
        left = self.display_half(self.levels[:BANDS_PER_CHANNEL], self.levels[-2])
        right = self.display_half(self.levels[BANDS_PER_CHANNEL:BANDS_PER_CHANNEL * CHANNELS], self.levels[-1])
        return left[::-1] + right

    def close(self):
        self.main.close()
        self.bass.close()


def main():
    try:
        monitor = PlaybackMonitor()
        try:
            spectrum = Spectrum()
            try:
                while True:
                    frame = spectrum.update(monitor.read())
                    print(";".join(map(str, frame)), flush=True)
            finally:
                spectrum.close()
        finally:
            monitor.close()
    except BrokenPipeError:
        return 0
    except (OSError, RuntimeError) as error:
        print(f"Lock screen visualizer: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
