#!/bin/bash
#
# Guards the build-config invariants that no unit test can reach.
#
# The bug this exists for: Debug and Release shared one entitlements file carrying
# aps-environment = development, so Release builds registered sandbox APNs tokens and
# production pushes silently never arrived. Nothing in the code could detect that.
#
# Run from CI, or add as a Run Script build phase. Exits non-zero on a mismatch.

set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

check() {
    local file=$1 key=$2 expected=$3 actual
    if [[ ! -f $file ]]; then
        echo "error: $file is missing"
        fail=1
        return
    fi
    actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || echo "<absent>")
    if [[ $actual != "$expected" ]]; then
        echo "error: $file: $key is '$actual', expected '$expected'"
        fail=1
    else
        echo "ok: $file: $key = $actual"
    fi
}

check Zyncloud.entitlements aps-environment development
check Zyncloud.Release.entitlements aps-environment production

# The Release build configuration must point at the production entitlements file.
if ! grep -q 'CODE_SIGN_ENTITLEMENTS = Zyncloud.Release.entitlements;' \
        Zyncloud.xcodeproj/project.pbxproj; then
    echo "error: no build configuration references Zyncloud.Release.entitlements"
    fail=1
else
    echo "ok: project references the Release entitlements file"
fi

# --- signed output ------------------------------------------------------------
#
# Everything above passed while a real archive was signed with
# aps-environment = development. The source files are not authoritative: automatic
# signing reconciles entitlements down to whatever the resolved provisioning profile
# permits, so a development profile silently downgrades the production value with no
# warning. Only the signed binary proves what shipped.
#
#   ./check-entitlements.sh /path/to/Zyncloud.xcarchive
#   ./check-entitlements.sh /path/to/Zyncloud.app
#
# Point this at a *distribution* build. A local `xcodebuild archive` on a machine
# without an App Store profile will legitimately fail this check.
if [[ $# -gt 0 ]]; then
    target=$1

    if [[ -d $target && $target == *.xcarchive ]]; then
        app=$(find "$target/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)
    else
        app=$target
    fi

    if [[ -z ${app:-} || ! -d $app ]]; then
        echo "error: no .app found at $target"
        exit 1
    fi

    tmp=$(mktemp -t entitlements)
    trap 'rm -f "$tmp"' EXIT

    if ! codesign -d --entitlements - --xml "$app" 2>/dev/null \
            | plutil -convert xml1 -o "$tmp" - 2>/dev/null; then
        echo "error: could not read signed entitlements from $app"
        exit 1
    fi

    signed=$(/usr/libexec/PlistBuddy -c "Print :aps-environment" "$tmp" 2>/dev/null || echo "<absent>")

    if [[ $signed != production ]]; then
        echo "error: $(basename "$app"): signed aps-environment is '$signed', expected 'production'"
        profile=$app/embedded.mobileprovision
        if [[ -f $profile ]]; then
            name=$(security cms -D -i "$profile" 2>/dev/null \
                | plutil -extract Name raw -o - - 2>/dev/null || echo "<unknown>")
            echo "note: signed against provisioning profile '$name'"
            echo "note: a development profile caps aps-environment at 'development' no matter"
            echo "      what the entitlements file says. Re-export with an App Store profile."
        fi
        fail=1
    else
        echo "ok: $(basename "$app"): signed aps-environment = production"
    fi
fi

exit "$fail"
