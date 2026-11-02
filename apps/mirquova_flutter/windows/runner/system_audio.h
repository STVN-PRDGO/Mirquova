#ifndef RUNNER_SYSTEM_AUDIO_H_
#define RUNNER_SYSTEM_AUDIO_H_

#include <cstdint>
#include <vector>

// Loopback of the default speakers, converted to 48 kHz stereo 16-bit PCM.
// This does not open the microphone.
void StartSystemAudio();
std::vector<uint8_t> CaptureSystemAudio();
void PlaySystemAudio(const uint8_t* pcm, size_t length, uint32_t sample_rate,
                     uint16_t channels);
// Plays the Rust jitter buffer on the default speakers. False when the core
// library is not loaded yet.
bool StartClockedPlayback();
void StopSystemAudioCapture();
void StopSystemAudioPlayback();

#endif  // RUNNER_SYSTEM_AUDIO_H_
