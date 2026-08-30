#!/bin/bash
#
# Guards the Info.plist invariants that no unit test can reach, and that App Review
# would otherwise be the one to catch.
#
# The bugs this exists for:
#   - NSPhotoLibraryUsageDescription was copy-pasted from another project and told users
#     the app wanted their photos "to create audiobooks about them".
#   - UIRequiredDeviceCapabilities was armv7 (32-bit) against a 64-bit-only deployment
#     target — a combination no device can satisfy.
#   - ITSAppUsesNonExemptEncryption was absent, adding a manual answer to every upload.
#
# Exits non-zero on a mismatch.

set -euo pipefail

cd "$(dirname "$0")/.."

plist=Info.plist
fail=0

read_key() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || echo "<absent>"
}

# --- photo library usage string ----------------------------------------------
usage=$(read_key NSPhotoLibraryUsageDescription)
if [[ $usage == "<absent>" || -z $usage ]]; then
    echo "error: NSPhotoLibraryUsageDescription is missing or empty"
    fail=1
elif [[ $(printf '%s' "$usage" | tr '[:upper:]' '[:lower:]') == *audiobook* ]]; then
    echo "error: NSPhotoLibraryUsageDescription still carries the copy-pasted text: '$usage'"
    fail=1
else
    echo "ok: NSPhotoLibraryUsageDescription is set"
fi

# --- device capabilities ------------------------------------------------------
caps=$(/usr/libexec/PlistBuddy -c "Print :UIRequiredDeviceCapabilities" "$plist" 2>/dev/null || echo "")
if [[ $caps == *armv7* ]]; then
    echo "error: UIRequiredDeviceCapabilities lists armv7 (32-bit); no supported device qualifies"
    fail=1
elif [[ $caps != *arm64* ]]; then
    echo "error: UIRequiredDeviceCapabilities does not list arm64"
    fail=1
else
    echo "ok: UIRequiredDeviceCapabilities = arm64"
fi

# --- device family ------------------------------------------------------------
# App Store validation once rejected a build that declared iPad support ("1,2" is
# the Xcode default) while shipping only iPhone icons and a portrait-only
# orientation list: "does not contain an app icon for iPad of exactly 167x167",
# and the same for 152x152, plus a demand for all four iPad multitasking
# orientations. iPad is now supported on purpose, so the three parts must stay
# together: the family, the two icon sizes, and the ~ipad orientation list.
icons=Assets.xcassets/AppIcon.appiconset
if grep -q 'TARGETED_DEVICE_FAMILY = "1,2"' Zyncloud.xcodeproj/project.pbxproj; then
    for px in 152 167; do
        file=$(python3 - "$icons" "$px" <<'PYEOF'
import json, sys
root, px = sys.argv[1], int(sys.argv[2])
for image in json.load(open(f"{root}/Contents.json"))["images"]:
    if image["idiom"] != "ipad":
        continue
    if round(float(image["size"].split("x")[0]) * float(image["scale"].rstrip("x"))) == px:
        print(image.get("filename", ""))
        break
PYEOF
        )
        if [[ -z $file || ! -f $icons/$file ]]; then
            echo "error: no iPad app icon of ${px}x${px} in $icons"
            fail=1
            continue
        fi
        actual=$(sips -g pixelWidth -g pixelHeight "$icons/$file" | awk '/pixel/ {print $2}' | paste -sd x -)
        if [[ $actual != "${px}x${px}" ]]; then
            echo "error: $file is $actual, not ${px}x${px}"
            fail=1
        else
            echo "ok: iPad app icon ${px}x${px} ($file)"
        fi
    done

    ipad_orientations=$(read_key 'UISupportedInterfaceOrientations~ipad')
    missing=""
    for o in Portrait PortraitUpsideDown LandscapeLeft LandscapeRight; do
        [[ $ipad_orientations == *"UIInterfaceOrientation$o"* ]] || missing="$missing $o"
    done
    if [[ -n $missing ]]; then
        echo "error: UISupportedInterfaceOrientations~ipad is missing:$missing"
        echo "note: iPad multitasking requires all four."
        fail=1
    else
        echo "ok: UISupportedInterfaceOrientations~ipad lists all four"
    fi
elif grep -q 'TARGETED_DEVICE_FAMILY = 1;' Zyncloud.xcodeproj/project.pbxproj; then
    echo "ok: TARGETED_DEVICE_FAMILY is iPhone-only"
else
    echo "error: TARGETED_DEVICE_FAMILY is neither 1 nor \"1,2\""
    fail=1
fi

# --- export compliance --------------------------------------------------------
crypto=$(read_key ITSAppUsesNonExemptEncryption)
if [[ $crypto == "<absent>" ]]; then
    echo "error: ITSAppUsesNonExemptEncryption is absent; every upload asks the question by hand"
    fail=1
else
    echo "ok: ITSAppUsesNonExemptEncryption = $crypto"
fi

exit "$fail"
