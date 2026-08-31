#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.38.5}"
CACHE_ROOT="${NETLIFY_CACHE_DIR:-.netlify-cache}"
FLUTTER_DIR="$CACHE_ROOT/flutter-$FLUTTER_VERSION"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  mkdir -p "$CACHE_ROOT"
  rm -rf "$FLUTTER_DIR"
  git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
flutter config --enable-web
flutter pub get

: "${SUPABASE_URL:=}"
: "${SUPABASE_PUBLISHABLE_KEY:=}"

DART_DEFINES=(--dart-define=SUPABASE_URL="$SUPABASE_URL")
if [ -n "$SUPABASE_PUBLISHABLE_KEY" ]; then
  DART_DEFINES+=(--dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY")
fi

flutter build web --release "${DART_DEFINES[@]}"
