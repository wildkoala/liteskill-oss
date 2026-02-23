#!/usr/bin/env bash
#
# Builds PostgreSQL 18 from source (Linux) or copies pre-compiled binaries
# (macOS/Windows), then compiles pgvector from source for the given target.
#
# Usage:
#   bash scripts/fetch-postgres.sh <target-triple>
#
# Supported triples:
#   x86_64-unknown-linux-gnu
#   aarch64-apple-darwin
#   x86_64-apple-darwin
#   x86_64-pc-windows-msvc
#
# Output: priv/postgres/<triple>/  (bin/, lib/, share/postgresql/)
set -euo pipefail

PG_MAJOR="${PG_MAJOR:-18}"
PG_VERSION="${PG_VERSION:-18.2}"
PGVECTOR_VERSION="${PGVECTOR_VERSION:-0.8.1}"

TRIPLE="${1:?Usage: $0 <target-triple>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$PROJECT_ROOT/priv/postgres/$TRIPLE"
WORK_DIR="$(mktemp -d)"

trap 'rm -rf "$WORK_DIR"' EXIT

# Binaries we keep (everything else is stripped)
KEEP_BINS=(postgres pg_ctl initdb pg_isready psql createdb)

log() { echo "==> $*"; }

build_pgvector() {
  local pg_config="$1"
  log "Building pgvector $PGVECTOR_VERSION..."

  cd "$WORK_DIR"
  curl -fsSL --retry 3 --retry-delay 5 "https://github.com/pgvector/pgvector/archive/refs/tags/v${PGVECTOR_VERSION}.tar.gz" \
    -o pgvector.tar.gz
  tar xzf pgvector.tar.gz
  cd "pgvector-${PGVECTOR_VERSION}"

  make PG_CONFIG="$pg_config" -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

  # Copy directly from build directory — avoids DESTDIR path nesting issues
  # when pg_config reports relocated (non-prefix) paths.
  cp vector.control "$OUT_DIR/share/postgresql/extension/"
  cp sql/vector--*.sql "$OUT_DIR/share/postgresql/extension/"

  # PostgreSQL hardcodes $libdir to the compiled-in prefix (e.g. /opt/pg/lib).
  # When the binary runs from a Burrito bundle, that absolute path doesn't
  # exist. Strip the $libdir/ prefix so PostgreSQL uses dynamic_library_path
  # (set at startup by PostgresManager) to find vector.so instead.
  sed -i.bak 's|\$libdir/||' "$OUT_DIR/share/postgresql/extension/vector.control"
  rm -f "$OUT_DIR/share/postgresql/extension/vector.control.bak"

  if [ -f vector.so ]; then
    cp vector.so "$OUT_DIR/lib/"
  elif [ -f vector.dylib ]; then
    cp vector.dylib "$OUT_DIR/lib/"
  else
    echo "ERROR: pgvector build did not produce vector.so or vector.dylib" >&2
    ls -la . >&2
    exit 1
  fi

  log "pgvector $PGVECTOR_VERSION installed to $OUT_DIR"
}

copy_minimal_pg() {
  local pg_prefix="$1"

  mkdir -p "$OUT_DIR"/{bin,lib,share/postgresql/extension}

  # Copy essential binaries
  for bin in "${KEEP_BINS[@]}"; do
    if [ -f "$pg_prefix/bin/$bin" ]; then
      cp "$pg_prefix/bin/$bin" "$OUT_DIR/bin/"
    fi
  done

  # Fail fast if no binaries were copied
  if [ ! -f "$OUT_DIR/bin/initdb" ] && [ ! -f "$OUT_DIR/bin/initdb.exe" ]; then
    echo "ERROR: initdb not found after copy. Contents of $pg_prefix/bin/:" >&2
    ls -la "$pg_prefix/bin/" >&2
    exit 1
  fi

  # Copy all shared libraries and server modules (dict_snowball, plpgsql, etc.).
  # Use cp -a to preserve the full directory tree — PG's $libdir resolution
  # expects server modules at the same relative offset as the compiled prefix.
  if [ -d "$pg_prefix/lib" ]; then
    cp -a "$pg_prefix"/lib/* "$OUT_DIR/lib/"
  fi

  # Verify critical server module is present
  if ! find "$OUT_DIR/lib" -name "dict_snowball*" -print -quit 2>/dev/null | grep -q .; then
    echo "WARNING: dict_snowball not found in $OUT_DIR/lib/ — initdb will fail" >&2
    log "Contents of $pg_prefix/lib/:"
    ls -la "$pg_prefix/lib/" 2>/dev/null || true
  fi

  # Copy share directory into normalized $OUT_DIR/share/postgresql/ layout.
  # All platforms end up with postgres.bki at $OUT_DIR/share/postgresql/postgres.bki.
  if [ -d "$pg_prefix/share/postgresql" ]; then
    # Homebrew / --prefix=/opt/pg layout: share/postgresql/ contains the actual files
    cp -a "$pg_prefix/share/postgresql/"* "$OUT_DIR/share/postgresql/" 2>/dev/null || true
  elif [ -d "$pg_prefix/share" ]; then
    cp -a "$pg_prefix"/share/* "$OUT_DIR/share/postgresql/" 2>/dev/null || true
  fi
}

fetch_linux_x86_64() {
  log "Compiling PostgreSQL $PG_VERSION from source for Linux x86_64..."

  local pg_src_url="https://ftp.postgresql.org/pub/source/v${PG_VERSION}/postgresql-${PG_VERSION}.tar.bz2"

  cd "$WORK_DIR"
  curl -fsSL --retry 3 --retry-delay 5 "$pg_src_url" -o postgresql.tar.bz2
  tar xjf postgresql.tar.bz2
  cd "postgresql-${PG_VERSION}"

  # --prefix=/opt/pg gives a clean relocatable offset:
  # bin/ -> ../share/postgresql (one hop up). The bundle mirrors this layout.
  ./configure \
    --prefix=/opt/pg \
    --without-readline \
    --without-icu

  make -j"$(nproc)"
  make install DESTDIR="$WORK_DIR/pg_install"

  # Copy from staged install into output
  copy_minimal_pg "$WORK_DIR/pg_install/opt/pg"

  # Build pgvector against the freshly compiled PG
  local pg_config="$WORK_DIR/pg_install/opt/pg/bin/pg_config"
  build_pgvector "$pg_config"

  # Set rpath so bundled binaries find their libs at runtime
  if command -v patchelf &>/dev/null; then
    for bin in "$OUT_DIR"/bin/*; do
      patchelf --set-rpath '$ORIGIN/../lib' "$bin" 2>/dev/null || true
    done
  fi
}

# Scans all Mach-O binaries and dylibs in $OUT_DIR for references to
# /opt/homebrew, copies those dylibs into $OUT_DIR/lib/, and rewrites the
# load commands to use @rpath. Recurses to pick up transitive deps.
# Compatible with bash 3.2 (macOS default).
bundle_homebrew_dylibs() {
  log "Bundling Homebrew dylibs for portability..."
  local seen_file
  seen_file="$(mktemp)"
  trap 'rm -f "$seen_file"' RETURN

  # Iteratively discover and bundle Homebrew deps until no new ones are found.
  # Each pass scans all Mach-O files in OUT_DIR for /opt/homebrew references,
  # copies any not-yet-seen dylib into lib/, and marks it as seen.
  local pass=0
  while true; do
    pass=$((pass + 1))
    local found_new=0

    for f in "$OUT_DIR"/bin/* "$OUT_DIR"/lib/*.dylib "$OUT_DIR"/lib/postgresql/*.dylib; do
      [ -f "$f" ] || continue
      file "$f" | grep -q "Mach-O" || continue

      # grep || true prevents pipefail from aborting when no matches
      otool -L "$f" 2>/dev/null | awk '{print $1}' | (grep '^/opt/homebrew' || true) | while read -r dep; do
        [ -z "$dep" ] && continue
        local dep_basename
        dep_basename="$(basename "$dep")"
        if ! grep -qx "$dep_basename" "$seen_file" 2>/dev/null; then
          echo "$dep_basename" >> "$seen_file"
          if [ -f "$dep" ]; then
            cp -L "$dep" "$OUT_DIR/lib/$dep_basename"
            chmod 755 "$OUT_DIR/lib/$dep_basename"
            log "  Bundled $dep_basename"
            # Signal that we found something new (write marker file)
            touch "$seen_file.changed"
          else
            log "  WARNING: $dep not found (needed by $(basename "$f"))"
          fi
        fi
      done
    done

    if [ -f "$seen_file.changed" ]; then
      rm -f "$seen_file.changed"
    else
      break
    fi

    # Safety valve
    if [ "$pass" -gt 10 ]; then
      log "  WARNING: Stopping after $pass passes (possible circular deps)"
      break
    fi
  done

  # Rewrite all Homebrew references to @rpath in binaries and dylibs
  for f in "$OUT_DIR"/bin/* "$OUT_DIR"/lib/*.dylib "$OUT_DIR"/lib/postgresql/*.dylib; do
    [ -f "$f" ] || continue
    file "$f" | grep -q "Mach-O" || continue

    otool -L "$f" 2>/dev/null | awk '{print $1}' | (grep '^/opt/homebrew' || true) | while read -r dep; do
      [ -z "$dep" ] && continue
      local dep_basename
      dep_basename="$(basename "$dep")"
      install_name_tool -change "$dep" "@rpath/$dep_basename" "$f" 2>/dev/null || true
    done

    # Also fix the install name of dylibs themselves
    if echo "$f" | grep -q '\.dylib$'; then
      local current_id
      current_id="$(otool -D "$f" 2>/dev/null | tail -1)"
      if echo "$current_id" | grep -q '^/opt/homebrew'; then
        install_name_tool -id "@rpath/$(basename "$f")" "$f" 2>/dev/null || true
      fi
    fi
  done

  # Add @loader_path rpath to bundled dylibs so they can find each other
  for f in "$OUT_DIR"/lib/*.dylib; do
    [ -f "$f" ] || continue
    install_name_tool -add_rpath "@loader_path" "$f" 2>/dev/null || true
  done

  # Resolve @loader_path references that point to files not yet bundled.
  # ICU libraries reference libicudata via @loader_path — when those dylibs
  # were in Homebrew's lib/ dir they could find it, but in our bundle they need
  # the actual file present. Find the originals via Homebrew paths.
  log "Resolving @loader_path references..."
  for f in "$OUT_DIR"/lib/*.dylib; do
    [ -f "$f" ] || continue
    otool -L "$f" 2>/dev/null | awk '{print $1}' | (grep '^@loader_path/' || true) | while read -r dep; do
      local dep_basename
      dep_basename="$(echo "$dep" | sed 's|@loader_path/||')"
      local target_file="$OUT_DIR/lib/$dep_basename"
      if [ ! -f "$target_file" ]; then
        # Search Homebrew for the missing dylib
        local real_path
        real_path="$(find /opt/homebrew -name "$dep_basename" -not -type d -print -quit 2>/dev/null)"
        if [ -n "$real_path" ]; then
          cp -L "$real_path" "$target_file"
          chmod 755 "$target_file"
          log "  Bundled $dep_basename (transitive @loader_path dep)"
        else
          log "  WARNING: @loader_path dep $dep_basename not found"
        fi
      fi
    done
  done

  log "Homebrew dylib bundling complete"
}

# Re-signs all Mach-O files in $OUT_DIR with ad-hoc signatures.
# Required on Apple Silicon where the kernel kills binaries with invalid
# code signatures (which install_name_tool modifications invalidate).
resign_macos_binaries() {
  log "Re-signing Mach-O binaries..."
  find "$OUT_DIR" -type f | while read -r f; do
    if file "$f" | grep -q "Mach-O"; then
      codesign --force --sign - "$f" 2>/dev/null || true
    fi
  done
  log "Re-signing complete"
}

fetch_macos() {
  local arch="$1"
  log "Fetching PostgreSQL $PG_MAJOR for macOS ($arch)..."

  # Use Homebrew postgresql@$PG_MAJOR
  if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew is required for macOS builds" >&2
    exit 1
  fi

  # Ensure postgresql@$PG_MAJOR is installed
  if ! brew list "postgresql@${PG_MAJOR}" &>/dev/null; then
    brew install "postgresql@${PG_MAJOR}"
  fi

  local pg_prefix
  pg_prefix="$(brew --prefix "postgresql@${PG_MAJOR}")"

  copy_minimal_pg "$pg_prefix"

  # Build pgvector
  build_pgvector "$pg_prefix/bin/pg_config"

  # Bundle Homebrew dylibs that PG binaries depend on, so the app is portable
  # to machines without Homebrew. System dylibs (/usr/lib, /System) are fine.
  bundle_homebrew_dylibs

  # Fix dylib rpaths to be portable
  for bin in "$OUT_DIR"/bin/*; do
    if [ -f "$bin" ] && file "$bin" | grep -q "Mach-O"; then
      install_name_tool -add_rpath "@executable_path/../lib" "$bin" 2>/dev/null || true
      install_name_tool -add_rpath "@executable_path/../lib/postgresql" "$bin" 2>/dev/null || true
    fi
  done

  # Re-sign all Mach-O binaries and dylibs after install_name_tool modifications.
  # On Apple Silicon, modifying a binary invalidates its code signature, and the
  # kernel will SIGKILL any binary with an invalid signature.
  resign_macos_binaries
}

fetch_windows_x86_64() {
  log "Fetching PostgreSQL $PG_MAJOR for Windows x86_64..."

  local EDB_URL="https://get.enterprisedb.com/postgresql/postgresql-${PG_VERSION}-1-windows-x64-binaries.zip"

  cd "$WORK_DIR"
  curl -fsSL --retry 3 --retry-delay 5 "$EDB_URL" -o pg.zip
  unzip -q pg.zip

  local pg_prefix="$WORK_DIR/pgsql"

  # EDB Windows binaries resolve SHAREDIR as ../share (no postgresql/ nesting).
  # Keep the flat share/ layout to match the compiled-in offset so that
  # CREATE EXTENSION and timezone lookups work at runtime.
  mkdir -p "$OUT_DIR"/{bin,lib,share/extension}

  # Copy essential binaries (with .exe suffix)
  for bin in "${KEEP_BINS[@]}"; do
    if [ -f "$pg_prefix/bin/${bin}.exe" ]; then
      cp "$pg_prefix/bin/${bin}.exe" "$OUT_DIR/bin/"
    fi
  done

  # Copy required DLLs
  cp "$pg_prefix"/bin/*.dll "$OUT_DIR/bin/" 2>/dev/null || true
  cp -a "$pg_prefix"/lib/*.dll "$OUT_DIR/lib/" 2>/dev/null || true
  cp -a "$pg_prefix"/lib/*.lib "$OUT_DIR/lib/" 2>/dev/null || true

  # Copy share into flat layout (matching EDB's compiled-in ../share offset)
  if [ -d "$pg_prefix/share" ]; then
    cp -a "$pg_prefix"/share/extension "$OUT_DIR/share/" 2>/dev/null || true
    cp -a "$pg_prefix"/share/timezone* "$OUT_DIR/share/" 2>/dev/null || true
    cp -a "$pg_prefix"/share/*.bki "$OUT_DIR/share/" 2>/dev/null || true
    cp -a "$pg_prefix"/share/*.sql "$OUT_DIR/share/" 2>/dev/null || true
    cp -a "$pg_prefix"/share/*.sample "$OUT_DIR/share/" 2>/dev/null || true
  fi

  # Build pgvector with CMake (requires MSVC)
  log "Building pgvector for Windows..."
  cd "$WORK_DIR"
  curl -fsSL --retry 3 --retry-delay 5 "https://github.com/pgvector/pgvector/archive/refs/tags/v${PGVECTOR_VERSION}.tar.gz" \
    -o pgvector.tar.gz
  tar xzf pgvector.tar.gz
  cd "pgvector-${PGVECTOR_VERSION}"

  mkdir -p build && cd build
  cmake -G "NMake Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DPostgreSQL_ROOT="$pg_prefix" \
    ..
  cmake --build .

  # Copy pgvector artifacts
  find . -name "vector.dll" -exec cp {} "$OUT_DIR/lib/" \;
  cp ../vector.control "$OUT_DIR/share/extension/" 2>/dev/null || true
  cp ../sql/vector--*.sql "$OUT_DIR/share/extension/" 2>/dev/null || true

  # Strip $libdir/ prefix (same fix as build_pgvector — see comment there)
  sed -i.bak 's|\$libdir/||' "$OUT_DIR/share/extension/vector.control"
  rm -f "$OUT_DIR/share/extension/vector.control.bak"
}

# Main dispatch
log "Target: $TRIPLE"
log "Output: $OUT_DIR"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

case "$TRIPLE" in
  x86_64-unknown-linux-gnu)
    fetch_linux_x86_64
    ;;
  aarch64-apple-darwin)
    fetch_macos "arm64"
    ;;
  x86_64-apple-darwin)
    fetch_macos "x86_64"
    ;;
  x86_64-pc-windows-msvc)
    fetch_windows_x86_64
    ;;
  *)
    echo "ERROR: Unsupported target triple: $TRIPLE" >&2
    echo "Supported: x86_64-unknown-linux-gnu, aarch64-apple-darwin, x86_64-apple-darwin, x86_64-pc-windows-msvc" >&2
    exit 1
    ;;
esac

# Strip $libdir/ prefix from ALL extension control files. PostgreSQL hardcodes
# $libdir to the compiled-in prefix at build time. In a Burrito bundle that
# absolute path doesn't exist. Bare module names let PostgreSQL fall back to
# dynamic_library_path (set by PostgresManager at startup) instead.
for f in "$OUT_DIR"/share/postgresql/extension/*.control "$OUT_DIR"/share/extension/*.control; do
  if [ -f "$f" ]; then
    sed -i.bak 's|\$libdir/||' "$f"
    rm -f "${f}.bak"
  fi
done

# Verify critical shared libraries exist
for lib in plpgsql dict_snowball; do
  if ! find "$OUT_DIR/lib" -name "${lib}.*" -print -quit 2>/dev/null | grep -q .; then
    echo "WARNING: ${lib} shared library not found in $OUT_DIR/lib/" >&2
    log "Contents of $OUT_DIR/lib/:"
    ls -la "$OUT_DIR/lib/" 2>/dev/null || true
  fi
done

log "Done! PostgreSQL $PG_MAJOR + pgvector $PGVECTOR_VERSION installed to $OUT_DIR"
ls -la "$OUT_DIR/bin/"
