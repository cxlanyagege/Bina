#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/bina-macos-build-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
fixture="$(cd "$fixture" && pwd -P)"

tools_dir="$fixture/bin"
built_app="$fixture/.build/macos/DerivedData/Build/Products/Release/Bina.app"
output_app="$fixture/.build/macos/Bina.app"
mkdir -p "$tools_dir" "$fixture/scripts" "$built_app" "$output_app"
cp "$project_dir/scripts/build-macos.sh" "$fixture/scripts/build-macos.sh"
printf 'new\n' > "$built_app/version"
printf 'previous\n' > "$output_app/version"

# Exercise the actual packaging script with a disposable pair of bundles.
cat > "$tools_dir/xcodebuild" <<'STUB'
#!/bin/bash
exit 0
STUB
cat > "$tools_dir/codesign" <<'STUB'
#!/bin/bash
if [[ "$BINA_MAC_TEST_FAILURE" == signature ]]; then exit 70; fi
STUB
cat > "$tools_dir/mv" <<'STUB'
#!/bin/bash
case "$1" in
    */.Bina.*/Bina.app)
        case "$BINA_MAC_TEST_FAILURE" in
            publish|rollback) exit 71 ;;
            interruption)
                kill -TERM "$PPID"
                exit 143
                ;;
            paused)
                touch "$BINA_MAC_TEST_DIRECTORY/publish-ready"
                for attempt in {1..100}; do
                    if [[ -e "$BINA_MAC_TEST_DIRECTORY/publish-resume" ]]; then
                        exec /bin/mv "$@"
                    fi
                    sleep 0.05
                done
                printf 'Timed out waiting to publish the fixture.\n' >&2
                exit 73
                ;;
        esac
        ;;
    */.Bina.*/Previous.app)
        if [[ "$BINA_MAC_TEST_FAILURE" == rollback ]]; then exit 72; fi
        ;;
esac
exec /bin/mv "$@"
STUB
chmod +x "$tools_dir/"*

run_build() {
    PATH="$tools_dir:/usr/bin:/bin" BINA_MAC_TEST_FAILURE="$1" BINA_MAC_TEST_DIRECTORY="$fixture" \
        /bin/bash "$fixture/scripts/build-macos.sh" release
}

expect_failure() {
    local result=0
    run_build "$1" > "$fixture/build.log" 2>&1 || result=$?
    if [[ "$result" != "$2" ]]; then
        cat "$fixture/build.log" >&2
        printf 'Expected %s to exit with %s, got %s\n' "$1" "$2" "$result" >&2
        exit 1
    fi
}

expect_failure signature 70
[[ "$(cat "$output_app/version")" == previous ]]

expect_failure publish 71
[[ "$(cat "$output_app/version")" == previous ]]

expect_failure interruption 143
[[ "$(cat "$output_app/version")" == previous ]]

run_build none
[[ "$(cat "$output_app/version")" == new ]]

run_build paused > "$fixture/paused.log" 2>&1 &
first_build=$!
for attempt in {1..100}; do
    if [[ -e "$fixture/publish-ready" ]] || ! kill -0 "$first_build" 2>/dev/null; then break; fi
    sleep 0.05
done
if [[ ! -e "$fixture/publish-ready" ]]; then
    cat "$fixture/paused.log" >&2
    printf 'The first build did not reach publication.\n' >&2
    exit 1
fi

other_result=0
run_build none > "$fixture/concurrent.log" 2>&1 || other_result=$?
touch "$fixture/publish-resume"
wait "$first_build"
if [[ "$other_result" -ne 75 || -e "$output_app/Bina.app" ]]; then
    cat "$fixture/concurrent.log" >&2
    printf 'A concurrent build interfered with publication (exit %s).\n' "$other_result" >&2
    exit 1
fi
[[ "$(cat "$output_app/version")" == new ]]

expect_failure rollback 71
[[ ! -e "$output_app" ]]
preserved=( "$fixture"/.build/macos/.Bina.*/Previous.app )
[[ "${#preserved[@]}" == 1 && "$(cat "${preserved[0]}/version")" == new ]]
grep -Fq "$preserved" "$fixture/build.log"

printf 'Build packaging checks passed.\n'
