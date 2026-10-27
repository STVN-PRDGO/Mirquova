# Source from bash or zsh. Existing installed SDKs remain usable on other hosts.
mirquova_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
if [ -x "$mirquova_root/.toolchains/flutter/bin/flutter" ]; then
  export FLUTTER_ROOT="$mirquova_root/.toolchains/flutter"
  export PUB_CACHE="$mirquova_root/.toolchains/pub-cache"
  export PATH="$FLUTTER_ROOT/bin:$PATH"
fi
if [ -x "$mirquova_root/.toolchains/cargo/bin/cargo" ]; then
  export CARGO_HOME="$mirquova_root/.toolchains/cargo"
  export RUSTUP_HOME="$mirquova_root/.toolchains/rustup"
  export PATH="$CARGO_HOME/bin:$PATH"
fi
if [ -z "${ANDROID_HOME:-}" ] && [ -d "$HOME/Library/Android/sdk" ]; then
  export ANDROID_HOME="$HOME/Library/Android/sdk"
fi
if [ -n "${ANDROID_HOME:-}" ]; then
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/28.2.13676358}"
  export PATH="$ANDROID_HOME/platform-tools:$PATH"
fi
if [ -z "${JAVA_HOME:-}" ] && [ -d '/Applications/Android Studio.app/Contents/jbr/Contents/Home' ]; then
  export JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
  export PATH="$JAVA_HOME/bin:$PATH"
fi
unset mirquova_root
