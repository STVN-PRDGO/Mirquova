#include "screen_capture.h"

#include <objidl.h>
#include <windows.h>
#include <wincodec.h>

#include <algorithm>
#include <memory>

namespace {

void ScaledSize(int source_width, int source_height, int* width, int* height) {
  double scale = 1.0;
  if (source_width > 1280) {
    scale = 1280.0 / source_width;
  }
  if (source_height * scale > 720.0) {
    scale = 720.0 / source_height;
  }
  *width = (std::max)(1, static_cast<int>(source_width * scale));
  *height = (std::max)(1, static_cast<int>(source_height * scale));
}

std::vector<uint8_t> EncodeJpeg(HBITMAP bitmap, int width, int height) {
  IWICImagingFactory* factory = nullptr;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
    return {};
  }
  IWICBitmap* source = nullptr;
  HRESULT created = factory->CreateBitmapFromHBITMAP(
      bitmap, nullptr, WICBitmapUseAlpha, &source);
  if (FAILED(created) || source == nullptr) {
    factory->Release();
    return {};
  }
  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
    source->Release();
    factory->Release();
    return {};
  }
  IWICBitmapEncoder* encoder = nullptr;
  if (FAILED(factory->CreateEncoder(GUID_ContainerFormatJpeg, nullptr,
                                    &encoder))) {
    stream->Release();
    source->Release();
    factory->Release();
    return {};
  }
  if (FAILED(encoder->Initialize(stream, WICBitmapEncoderNoCache))) {
    encoder->Release();
    stream->Release();
    source->Release();
    factory->Release();
    return {};
  }
  IWICBitmapFrameEncode* frame = nullptr;
  IPropertyBag2* properties = nullptr;
  if (FAILED(encoder->CreateNewFrame(&frame, &properties))) {
    encoder->Release();
    stream->Release();
    source->Release();
    factory->Release();
    return {};
  }
  PROPBAG2 option{};
  option.pstrName = const_cast<LPOLESTR>(L"ImageQuality");
  VARIANT quality;
  VariantInit(&quality);
  quality.vt = VT_R4;
  quality.fltVal = 0.55f;
  properties->Write(1, &option, &quality);
  VariantClear(&quality);
  if (FAILED(frame->Initialize(properties)) ||
      FAILED(frame->SetSize(static_cast<UINT>(width),
                            static_cast<UINT>(height)))) {
    properties->Release();
    frame->Release();
    encoder->Release();
    stream->Release();
    source->Release();
    factory->Release();
    return {};
  }
  WICPixelFormatGUID format = GUID_WICPixelFormat24bppBGR;
  if (FAILED(frame->SetPixelFormat(&format)) || FAILED(frame->WriteSource(source, nullptr)) ||
      FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
    properties->Release();
    frame->Release();
    encoder->Release();
    stream->Release();
    source->Release();
    factory->Release();
    return {};
  }
  STATSTG stats{};
  if (FAILED(stream->Stat(&stats, STATFLAG_NONAME))) {
    properties->Release();
    frame->Release();
    encoder->Release();
    stream->Release();
    source->Release();
    factory->Release();
    return {};
  }
  const ULONG size = static_cast<ULONG>(stats.cbSize.QuadPart);
  std::vector<uint8_t> jpeg(size);
  LARGE_INTEGER zero{};
  stream->Seek(zero, STREAM_SEEK_SET, nullptr);
  ULONG read = 0;
  stream->Read(jpeg.data(), size, &read);
  jpeg.resize(read);
  properties->Release();
  frame->Release();
  encoder->Release();
  stream->Release();
  source->Release();
  factory->Release();
  return jpeg;
}

}  // namespace

std::vector<uint8_t> CaptureScreenJpeg() {
  const int source_x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int source_y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int source_width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int source_height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (source_width <= 0 || source_height <= 0) {
    return {};
  }
  int target_width = 0;
  int target_height = 0;
  ScaledSize(source_width, source_height, &target_width, &target_height);

  HDC screen = GetDC(nullptr);
  if (screen == nullptr) {
    return {};
  }
  HDC memory = CreateCompatibleDC(screen);
  HBITMAP bitmap = CreateCompatibleBitmap(screen, target_width, target_height);
  if (memory == nullptr || bitmap == nullptr) {
    if (bitmap != nullptr) {
      DeleteObject(bitmap);
    }
    if (memory != nullptr) {
      DeleteDC(memory);
    }
    ReleaseDC(nullptr, screen);
    return {};
  }
  HGDIOBJ previous = SelectObject(memory, bitmap);
  SetStretchBltMode(memory, HALFTONE);
  const BOOL copied = StretchBlt(memory, 0, 0, target_width, target_height, screen,
                                 source_x, source_y, source_width, source_height,
                                 SRCCOPY);
  SelectObject(memory, previous);
  std::vector<uint8_t> jpeg;
  if (copied) {
    const HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    jpeg = EncodeJpeg(bitmap, target_width, target_height);
    if (com == S_OK) {
      CoUninitialize();
    }
  }
  DeleteObject(bitmap);
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  return jpeg;
}
