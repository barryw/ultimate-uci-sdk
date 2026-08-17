#!/bin/sh
# Report which toolchains are present and what version, so a build log says what
# it actually tested rather than what the Dockerfile intended.
set -u

# Optional toolchains are reported but do not fail the image: upstreams that
# have no stable download must not be able to break a build of everything else.
optional() {
    name=$1; shift
    if command -v "$1" >/dev/null 2>&1; then
        printf '%-14s ok    %s\n' "$name" "$("$@" 2>&1 | head -1)"
    else
        printf '%-14s absent (optional)\n' "$name"
    fi
}

report() {
    name=$1; shift
    if command -v "$1" >/dev/null 2>&1; then
        version=$("$@" 2>&1 | head -1)
        printf '%-14s ok    %s\n' "$name" "$version"
    else
        printf '%-14s MISSING\n' "$name"
        missing=$((missing + 1))
    fi
}

missing=0
echo "Ultimate SDK toolchain image"
echo
report cc65       cl65 --version
report ca65       ca65 --version
report 64tass     64tass --version
report acme       acme --version
report kickass    kickass -version
report oscar64    oscar64
optional kickc    kickc --version
report llvm-mos   mos-c64-clang --version
echo
if [ "$missing" -gt 0 ]; then
    echo "$missing required toolchain(s) missing"
    exit 1
fi
echo "all toolchains present"
