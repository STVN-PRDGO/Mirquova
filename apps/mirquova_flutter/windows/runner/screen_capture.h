#ifndef RUNNER_SCREEN_CAPTURE_H_
#define RUNNER_SCREEN_CAPTURE_H_

#include <cstdint>
#include <vector>

// Captures the virtual desktop as a JPEG scaled to at most 1280x720.
// Returns an empty vector when GDI capture is unavailable.
std::vector<uint8_t> CaptureScreenJpeg();

#endif  // RUNNER_SCREEN_CAPTURE_H_
