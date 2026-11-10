#!/usr/bin/env bash
set -euo pipefail

# Install the same pinned Lua release used by the native CI matrix, without
# relying on gh-actions-lua's unretired 5.4 alias or single-attempt download.
version=5.4.9
workspace="${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"
prefix="$workspace/.lua"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
archive="$work/lua-$version.tar.gz"

download() {
  curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
    --connect-timeout 20 --max-time 300 "$1" -o "$archive"
}

if ! download "https://www.lua.org/ftp/lua-$version.tar.gz"; then
  echo "Canonical Lua download failed; retrying tagged upstream mirror" >&2
  download "https://github.com/lua/lua/archive/refs/tags/v$version.tar.gz"
fi

tar -xzf "$archive" -C "$work"
source_dir="$work/lua-$version"
test -d "$source_dir"
mkdir -p "$prefix/bin" "$prefix/include" "$prefix/lib"

if [[ -d "$source_dir/src" ]]; then
  # Official release tarball: install the built interpreter, headers and lib.
  # POSIX-only builds cannot load LuaRocks C modules (for example lfs.so).
  make -C "$source_dir" posix MYCFLAGS="-DLUA_USE_DLOPEN" MYLDFLAGS="-Wl,-E" MYLIBS="-ldl"
  make -C "$source_dir" install INSTALL_TOP="$prefix"
else
  # The tagged GitHub mirror has a flat C source tree and no release Makefile.
  (
    cd "$source_dir"
    objects=()
    shopt -s nullglob
    for file in *.c; do
      case "$file" in lua.c|luac.c|onelua.c|ltests.c) continue ;; esac
      obj="${file%.c}.o"
      cc -O2 -DLUA_USE_LINUX -c "$file" -o "$obj"
      objects+=("$obj")
    done
    test "${#objects[@]}" -gt 0
    ar rcs "$prefix/lib/liblua.a" "${objects[@]}"
    cc -O2 -DLUA_USE_LINUX -Wl,-E -o "$prefix/bin/lua" \
      lua.c "$prefix/lib/liblua.a" -lm -ldl
    cc -O2 -DLUA_USE_LINUX -o "$prefix/bin/luac" \
      luac.c "$prefix/lib/liblua.a" -lm -ldl
    install -m 644 lua.h luaconf.h lualib.h lauxlib.h "$prefix/include/"
  )
fi

test -x "$prefix/bin/lua"
test -f "$prefix/include/lua.h"
test -f "$prefix/lib/liblua.a"
"$prefix/bin/lua" -v
"$prefix/bin/lua" -e 'assert(_VERSION == "Lua 5.4", "unexpected Lua version")'
"$prefix/bin/lua" -e 'assert(math.maxinteger > 2^53, "64-bit Lua integers required")'
printf '%s\n' "$prefix/bin" >> "${GITHUB_PATH:?GITHUB_PATH is required}"
