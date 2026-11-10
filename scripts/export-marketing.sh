#!/bin/bash
set -euo pipefail
# Run from any directory. Optionally pass an available iPhone simulator UDID.
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_simulator="${1:-}"
if [[ -z "$task_simulator" ]]; then
  task_simulator="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; rows=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d.get("isAvailable") and d["name"].startswith("iPhone")]; rows.sort(key=lambda d:d["state"]!="Booted"); print(rows[0]["udid"])')"
fi
task_build="${FRAMELINE_MARKETING_BUILD:-${TMPDIR:-/tmp}/FrameLineProMarketingBuild}"
task_shots="$task_build/NativeShots"
mkdir -p "$task_shots"
xcrun simctl boot "$task_simulator" 2>/dev/null || true
xcrun simctl bootstatus "$task_simulator" -b
xcodebuild -project "$task_root/FrameLinePro.xcodeproj" -scheme MyApp -configuration Debug \
  -destination "platform=iOS Simulator,id=$task_simulator" -derivedDataPath "$task_build" CODE_SIGNING_ALLOWED=NO build > "$task_build/build.log" 2>&1
xcrun simctl install "$task_simulator" "$task_build/Build/Products/Debug-iphonesimulator/FrameLinePro.app"
xcrun simctl status_bar "$task_simulator" override --time '9:41' --batteryState charged --batteryLevel 100
for task_index in {1..10}; do
  task_number="$(printf '%02d' "$task_index")"
  xcrun simctl launch --terminate-running-process "$task_simulator" com.edwinmuronzipersonalteam.FrameLinePro --capture-story "$task_index"
  sleep 8
  xcrun simctl io "$task_simulator" screenshot "$task_shots/camera-$task_number.png"
done
task_data="$(xcrun simctl get_app_container "$task_simulator" com.edwinmuronzipersonalteam.FrameLinePro data)"
mkdir -p "$task_data/Documents/MarketingInput"
cp "$task_shots"/camera-*.png "$task_data/Documents/MarketingInput/"
rm -f "$task_data/Documents/MarketingExport/export-complete.txt"
xcrun simctl launch --terminate-running-process "$task_simulator" com.edwinmuronzipersonalteam.FrameLinePro --export-marketing
for task_wait in {1..30}; do
  [[ -f "$task_data/Documents/MarketingExport/export-complete.txt" ]] && break
  sleep 1
done
[[ "$(cat "$task_data/Documents/MarketingExport/export-complete.txt")" == '10' ]]
mkdir -p "$task_root/Marketing/AppStore"
for task_file in "$task_data/Documents/MarketingExport"/[0-9][0-9]-*.png; do
  task_name="$(basename "$task_file")"
  cp "$task_file" "$task_root/Marketing/AppStore/${task_name//&/and}"
done
for task_file in "$task_shots"/camera-*.png; do
  task_name="$(basename "$task_file" .png)"
  task_number="${task_name#camera-}"
  task_asset="$task_root/FrameLinePro/Assets.xcassets/Screen$task_number.imageset"
  mkdir -p "$task_asset"
  sips -s format jpeg -s formatOptions 88 -Z 1280 "$task_file" --out "$task_asset/screen.jpg" >/dev/null
  cat > "$task_asset/Contents.json" <<'JSON'
{"images":[{"filename":"screen.jpg","idiom":"universal"}],"info":{"author":"xcode","version":1}}
JSON
done
xcrun simctl status_bar "$task_simulator" clear
printf 'Exported ten native-interface marketing images to %s/Marketing/AppStore\n' "$task_root"
printf 'Rebuild the app to include the refreshed cached onboarding previews.\n'
