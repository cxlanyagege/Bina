#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$project_dir/.build/macos"
derived_data_dir="$build_dir/DerivedData"
configuration="${1:-debug}"

case "$configuration" in
    debug) xcode_configuration="Debug" ;;
    release) xcode_configuration="Release" ;;
    *)
        printf 'Usage: %s [debug|release]\n' "$0" >&2
        exit 2
        ;;
esac

mkdir -p "$build_dir"

# Both configurations share DerivedData and the published app bundle.
lock_path="$build_dir/.Bina.lock"
exec 9>>"$lock_path"
lockf -s -t 0 9 || {
    result=$?
    printf 'Could not lock %s (exit %s). If another Bina macOS build is running, wait and retry.\n' "$lock_path" "$result" >&2
    exit "$result"
}

build_options=(
    -project "$project_dir/Bina.xcodeproj"
    -scheme BinaMac
    -configuration "$xcode_configuration"
    -destination "platform=macOS"
    -derivedDataPath "$derived_data_dir"
    -quiet
)

if [[ -n "${BINA_MAC_DEVELOPMENT_TEAM:-}" ]]; then
    build_options+=("DEVELOPMENT_TEAM=$BINA_MAC_DEVELOPMENT_TEAM")
fi

xcodebuild "${build_options[@]}" build
built_app="$derived_data_dir/Build/Products/$xcode_configuration/Bina.app"
output_app="$build_dir/Bina.app"
stage_dir="$(mktemp -d "$build_dir/.Bina.XXXXXX")"
previous_app="$stage_dir/Previous.app"

cleanup() {
    local result=$?
    # Keep the previous build on disk even if restoring it to the output path fails.
    if (( result != 0 )) && [[ -e "$previous_app" || -L "$previous_app" ]]; then
        if [[ -e "$output_app" || -L "$output_app" ]] || ! mv "$previous_app" "$output_app"; then
            printf 'Previous build retained at %s\n' "$previous_app" >&2
            exit "$result"
        fi
    fi

    rm -rf "$stage_dir"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ditto "$built_app" "$stage_dir/Bina.app"
codesign --verify --deep --strict "$stage_dir/Bina.app"

if [[ -e "$output_app" || -L "$output_app" ]]; then
    mv "$output_app" "$previous_app"
fi
mv "$stage_dir/Bina.app" "$output_app"
printf 'Built %s\n' "$output_app"
