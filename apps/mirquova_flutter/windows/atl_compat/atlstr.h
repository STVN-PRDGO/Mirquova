#pragma once

// The local Visual Studio Build Tools install has no ATL headers.
// flutter_secure_storage_windows only needs these two converters.
#include <windows.h>

#include <string>
#include <vector>

class CA2W {
 public:
  explicit CA2W(const char* source) : m_psz(nullptr) {
    if (source == nullptr) {
      buffer_.push_back(0);
    } else {
      const int count =
          MultiByteToWideChar(CP_UTF8, 0, source, -1, nullptr, 0);
      buffer_.assign(count > 0 ? count : 1, 0);
      if (count > 0) {
        MultiByteToWideChar(CP_UTF8, 0, source, -1, buffer_.data(), count);
      }
    }
    m_psz = buffer_.data();
  }

  operator const wchar_t*() const { return m_psz; }
  operator wchar_t*() const { return m_psz; }

  wchar_t* m_psz;

 private:
  std::vector<wchar_t> buffer_;
};

class CW2A {
 public:
  explicit CW2A(const wchar_t* source) {
    if (source == nullptr) {
      buffer_.push_back(0);
      return;
    }
    const int count = WideCharToMultiByte(
        CP_UTF8, 0, source, -1, nullptr, 0, nullptr, nullptr);
    buffer_.assign(count > 0 ? count : 1, 0);
    if (count > 0) {
      WideCharToMultiByte(
          CP_UTF8, 0, source, -1, buffer_.data(), count, nullptr, nullptr);
    }
  }

  operator const char*() const { return buffer_.data(); }

 private:
  std::vector<char> buffer_;
};
