#include "system_audio.h"

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <mmsystem.h>
#include <objbase.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr uint32_t kRate = 48000;
constexpr uint16_t kChannels = 2;
constexpr GUID kFloatSubtype = {
    0x00000003,
    0x0000,
    0x0010,
    {0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71}};

struct Loopback {
  IAudioClient* client = nullptr;
  IAudioCaptureClient* capture = nullptr;
  WAVEFORMATEX* format = nullptr;
  bool float32 = false;
  uint32_t source_rate = 0;
  uint16_t source_channels = 0;
  std::vector<float> pending;
  double cursor = 0;
};

Loopback g_loop;
HWAVEOUT g_wave = nullptr;
WAVEHDR g_headers[4]{};
std::vector<uint8_t> g_buffers[4];
int g_next = 0;
uint32_t g_wave_rate = 0;
uint16_t g_wave_channels = 0;
std::mutex g_mutex;
std::atomic<bool> g_clock_run{false};
std::atomic<int> g_clock_ready{0};
std::thread g_clock_thread;
std::mutex g_clock_mutex;

bool IsFloatFormat(const WAVEFORMATEX* format) {
  if (format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) return true;
  if (format->wFormatTag != WAVE_FORMAT_EXTENSIBLE || format->cbSize < 22) {
    return false;
  }
  const auto* extended = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
  return IsEqualGUID(extended->SubFormat, kFloatSubtype) == TRUE;
}

void ReleaseLoopback() {
  if (g_loop.client != nullptr) g_loop.client->Stop();
  if (g_loop.capture != nullptr) {
    g_loop.capture->Release();
    g_loop.capture = nullptr;
  }
  if (g_loop.client != nullptr) {
    g_loop.client->Release();
    g_loop.client = nullptr;
  }
  if (g_loop.format != nullptr) {
    CoTaskMemFree(g_loop.format);
    g_loop.format = nullptr;
  }
  g_loop.pending.clear();
  g_loop.cursor = 0;
}

bool EnsureLoopback() {
  if (g_loop.client != nullptr) return true;
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  IMMDeviceEnumerator* enumerator = nullptr;
  HRESULT result = CoCreateInstance(
      __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
      __uuidof(IMMDeviceEnumerator), reinterpret_cast<void**>(&enumerator));
  if (FAILED(result)) return false;
  IMMDevice* device = nullptr;
  result = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
  enumerator->Release();
  if (FAILED(result)) return false;
  result = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                            reinterpret_cast<void**>(&g_loop.client));
  device->Release();
  if (FAILED(result)) return false;
  result = g_loop.client->GetMixFormat(&g_loop.format);
  if (FAILED(result) || g_loop.format == nullptr) {
    ReleaseLoopback();
    return false;
  }
  result = g_loop.client->Initialize(
      AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 200000, 0,
      g_loop.format, nullptr);
  if (FAILED(result)) {
    ReleaseLoopback();
    return false;
  }
  result = g_loop.client->GetService(
      __uuidof(IAudioCaptureClient), reinterpret_cast<void**>(&g_loop.capture));
  if (FAILED(result)) {
    ReleaseLoopback();
    return false;
  }
  g_loop.float32 = IsFloatFormat(g_loop.format);
  g_loop.source_rate = g_loop.format->nSamplesPerSec;
  g_loop.source_channels = g_loop.format->nChannels;
  if (g_loop.source_rate == 0 || g_loop.source_channels == 0 ||
      (!g_loop.float32 && g_loop.format->wBitsPerSample != 16)) {
    ReleaseLoopback();
    return false;
  }
  if (FAILED(g_loop.client->Start())) {
    ReleaseLoopback();
    return false;
  }
  return true;
}

std::vector<uint8_t> DrainLoopback() {
  UINT32 packet = 0;
  while (SUCCEEDED(g_loop.capture->GetNextPacketSize(&packet)) && packet > 0) {
    BYTE* data = nullptr;
    UINT32 frames = 0;
    DWORD flags = 0;
    if (FAILED(g_loop.capture->GetBuffer(&data, &frames, &flags, nullptr,
                                         nullptr))) {
      break;
    }
    const size_t count =
        static_cast<size_t>(frames) * g_loop.source_channels;
    if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0 || data == nullptr) {
      g_loop.pending.insert(g_loop.pending.end(), count, 0.0f);
    } else if (g_loop.float32) {
      const auto* input = reinterpret_cast<const float*>(data);
      g_loop.pending.insert(g_loop.pending.end(), input, input + count);
    } else {
      const auto* input = reinterpret_cast<const int16_t*>(data);
      for (size_t index = 0; index < count; ++index) {
        g_loop.pending.push_back(input[index] / 32768.0f);
      }
    }
    g_loop.capture->ReleaseBuffer(frames);
  }

  const double step =
      static_cast<double>(g_loop.source_rate) / static_cast<double>(kRate);
  const uint16_t channels = g_loop.source_channels;
  std::vector<int16_t> output;
  size_t available = g_loop.pending.size() / channels;
  while (g_loop.cursor + 1.0 < static_cast<double>(available)) {
    const auto frame = static_cast<size_t>(g_loop.cursor);
    const float fraction =
        static_cast<float>(g_loop.cursor - static_cast<double>(frame));
    for (uint16_t channel = 0; channel < kChannels; ++channel) {
      const uint16_t source = channel < channels ? channel : 0;
      const size_t left = frame * channels + source;
      const size_t right = left + channels;
      const float first = g_loop.pending[left];
      const float second =
          right < g_loop.pending.size() ? g_loop.pending[right] : first;
      const float mixed =
          std::clamp(first + (second - first) * fraction, -1.0f, 1.0f);
      output.push_back(static_cast<int16_t>(mixed * 32767.0f));
    }
    g_loop.cursor += step;
  }
  const auto consumed = static_cast<size_t>(g_loop.cursor);
  if (consumed > 0 && consumed * channels <= g_loop.pending.size()) {
    g_loop.pending.erase(g_loop.pending.begin(),
                         g_loop.pending.begin() + consumed * channels);
    g_loop.cursor -= static_cast<double>(consumed);
  }
  if (output.size() > 64 * 1024 / 2) {
    output.resize(64 * 1024 / 2);
  }
  std::vector<uint8_t> bytes(output.size() * sizeof(int16_t));
  if (!output.empty()) {
    std::memcpy(bytes.data(), output.data(), bytes.size());
  }
  return bytes;
}

void ClosePlayback() {
  if (g_wave == nullptr) return;
  waveOutReset(g_wave);
  for (auto& header : g_headers) {
    if ((header.dwFlags & WHDR_PREPARED) != 0) {
      waveOutUnprepareHeader(g_wave, &header, sizeof(header));
    }
    header = {};
  }
  waveOutClose(g_wave);
  g_wave = nullptr;
  g_wave_rate = 0;
  g_wave_channels = 0;
  g_next = 0;
}

}  // namespace

void StartSystemAudio() {
  std::lock_guard<std::mutex> lock(g_mutex);
  EnsureLoopback();
}

std::vector<uint8_t> CaptureSystemAudio() {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!EnsureLoopback()) return {};
  return DrainLoopback();
}

void PlaySystemAudio(const uint8_t* pcm, size_t length, uint32_t sample_rate,
                     uint16_t channels) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (pcm == nullptr || length < 4 || length > 64 * 1024 ||
      (channels != 1 && channels != 2) || length % (channels * 2) != 0) {
    return;
  }
  if (sample_rate != 8000 && sample_rate != 16000 && sample_rate != 22050 &&
      sample_rate != 44100 && sample_rate != 48000) {
    return;
  }
  if (g_wave != nullptr &&
      (g_wave_rate != sample_rate || g_wave_channels != channels)) {
    ClosePlayback();
  }
  if (g_wave == nullptr) {
    WAVEFORMATEX format{};
    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = channels;
    format.nSamplesPerSec = sample_rate;
    format.wBitsPerSample = 16;
    format.nBlockAlign = channels * 2;
    format.nAvgBytesPerSec = sample_rate * format.nBlockAlign;
    if (waveOutOpen(&g_wave, WAVE_MAPPER, &format, 0, 0, CALLBACK_NULL) !=
        MMSYSERR_NOERROR) {
      g_wave = nullptr;
      return;
    }
    g_wave_rate = sample_rate;
    g_wave_channels = channels;
  }
  WAVEHDR& header = g_headers[g_next];
  if ((header.dwFlags & WHDR_PREPARED) != 0 &&
      (header.dwFlags & WHDR_DONE) == 0) {
    return;
  }
  if ((header.dwFlags & WHDR_PREPARED) != 0) {
    waveOutUnprepareHeader(g_wave, &header, sizeof(header));
  }
  g_buffers[g_next].assign(pcm, pcm + length);
  header = {};
  header.lpData = reinterpret_cast<LPSTR>(g_buffers[g_next].data());
  header.dwBufferLength = static_cast<DWORD>(length);
  if (waveOutPrepareHeader(g_wave, &header, sizeof(header)) !=
      MMSYSERR_NOERROR) {
    return;
  }
  if (waveOutWrite(g_wave, &header, sizeof(header)) != MMSYSERR_NOERROR) {
    waveOutUnprepareHeader(g_wave, &header, sizeof(header));
    return;
  }
  g_next = (g_next + 1) % 4;
}

void StopSystemAudioCapture() {
  std::lock_guard<std::mutex> lock(g_mutex);
  ReleaseLoopback();
}

void StopSystemAudioPlayback() {
  {
    std::lock_guard<std::mutex> clock_lock(g_clock_mutex);
    g_clock_run.store(false);
    if (g_clock_thread.joinable()) g_clock_thread.join();
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  ClosePlayback();
}

using RenderAudio = uint32_t (*)(uint8_t*, uint32_t);

RenderAudio LoadRenderAudio() {
  HMODULE module = GetModuleHandleW(L"mirquova_core.dll");
  if (module == nullptr) {
    wchar_t path[MAX_PATH] = {};
    const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) return nullptr;
    std::wstring directory(path, path + length);
    const auto slash = directory.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return nullptr;
    directory.resize(slash + 1);
    directory += L"mirquova_core.dll";
    module = LoadLibraryW(directory.c_str());
  }
  if (module == nullptr) return nullptr;
  return reinterpret_cast<RenderAudio>(
      GetProcAddress(module, "mq_cast_render_audio"));
}

void ClockedPlayback(RenderAudio render) {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  IMMDeviceEnumerator* enumerator = nullptr;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                              __uuidof(IMMDeviceEnumerator),
                              reinterpret_cast<void**>(&enumerator)))) {
    g_clock_ready.store(-1);
    CoUninitialize();
    return;
  }
  IMMDevice* device = nullptr;
  const HRESULT endpoint =
      enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
  enumerator->Release();
  if (FAILED(endpoint)) {
    g_clock_ready.store(-1);
    CoUninitialize();
    return;
  }
  IAudioClient* client = nullptr;
  const HRESULT activated = device->Activate(
      __uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(&client));
  device->Release();
  if (FAILED(activated)) {
    g_clock_ready.store(-1);
    CoUninitialize();
    return;
  }
  WAVEFORMATEX format{};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = 2;
  format.nSamplesPerSec = 48000;
  format.wBitsPerSample = 16;
  format.nBlockAlign = 4;
  format.nAvgBytesPerSec = 48000 * 4;
  HANDLE event = CreateEvent(nullptr, FALSE, FALSE, nullptr);
  const REFERENCE_TIME buffer = 40 * 10000;
  HRESULT result = client->Initialize(
      AUDCLNT_SHAREMODE_SHARED,
      AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
          AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
      buffer, 0, &format, nullptr);
  if (SUCCEEDED(result)) result = client->SetEventHandle(event);
  IAudioRenderClient* output = nullptr;
  if (SUCCEEDED(result)) {
    result = client->GetService(__uuidof(IAudioRenderClient),
                                reinterpret_cast<void**>(&output));
  }
  UINT32 size = 0;
  if (SUCCEEDED(result)) result = client->GetBufferSize(&size);
  if (SUCCEEDED(result)) result = client->Start();
  g_clock_ready.store(SUCCEEDED(result) ? 1 : -1);
  std::vector<uint8_t> pcm;
  while (SUCCEEDED(result) && g_clock_run.load()) {
    WaitForSingleObject(event, 200);
    UINT32 padding = 0;
    if (FAILED(client->GetCurrentPadding(&padding)) || padding >= size) continue;
    const UINT32 free = size - padding;
    BYTE* buffer_out = nullptr;
    if (FAILED(output->GetBuffer(free, &buffer_out))) break;
    const size_t bytes = static_cast<size_t>(free) * 4;
    pcm.assign(bytes, 0);
    if (render(pcm.data(), static_cast<uint32_t>(bytes)) == 0) {
      std::fill(pcm.begin(), pcm.end(), 0);
    }
    std::memcpy(buffer_out, pcm.data(), bytes);
    if (FAILED(output->ReleaseBuffer(free, 0))) break;
  }
  client->Stop();
  if (output != nullptr) output->Release();
  client->Release();
  if (event != nullptr) CloseHandle(event);
  CoUninitialize();
}

bool StartClockedPlayback() {
  std::lock_guard<std::mutex> clock_lock(g_clock_mutex);
  if (g_clock_thread.joinable()) return g_clock_ready.load() == 1;
  RenderAudio render = LoadRenderAudio();
  if (render == nullptr) return false;
  g_clock_ready.store(0);
  g_clock_run.store(true);
  g_clock_thread = std::thread(ClockedPlayback, render);
  for (int attempt = 0; attempt < 50 && g_clock_ready.load() == 0; ++attempt) {
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  if (g_clock_ready.load() != 1) {
    g_clock_run.store(false);
    if (g_clock_thread.joinable()) g_clock_thread.join();
    return false;
  }
  return true;
}
