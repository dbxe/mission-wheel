#!/bin/zsh
set -euo pipefail

bundle_id="com.danielbriskin.mission-wheel"
app_name="Mission Wheel"
executable_name="mission-wheel"
cooldown_ms="${COOLDOWN_MS:-250}"
swap_directions="${SWAP_DIRECTIONS:-0}"
exclude_bundle_ids="${EXCLUDE_BUNDLE_IDS:-}"
signing_identity_name="Mission Wheel Signing"

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
app_path="${HOME}/Applications/${app_name}.app"
executable_path="${app_path}/Contents/MacOS/${executable_name}"
icon_source_path="${repo_root}/Resources/AppIcon.icns"
icon_destination_path="${app_path}/Contents/Resources/AppIcon.icns"
launch_agent_path="${HOME}/Library/LaunchAgents/${bundle_id}.plist"
log_dir="${HOME}/Library/Logs"

stop_executable() {
  local executable_to_stop="$1"
  [[ -n "${executable_to_stop}" ]] || return 0

  pkill -TERM -f "${executable_to_stop}" 2>/dev/null || true
  sleep 0.2
  pkill -KILL -f "${executable_to_stop}" 2>/dev/null || true
}

find_signing_identity() {
  local identity_name="$1"
  security find-identity -v -p codesigning 2>/dev/null | awk -F '"' -v name="${identity_name}" '$2 == name { print $2; exit }'
}

xml_escape() {
  print -r -- "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

if ! command -v swift >/dev/null 2>&1; then
  echo "swift was not found in PATH." >&2
  exit 1
fi

if [[ ! -f "${icon_source_path}" ]]; then
  echo "App icon not found: ${icon_source_path}" >&2
  exit 1
fi

if (( ${+CODESIGN_IDENTITY} )); then
  if [[ -z "${CODESIGN_IDENTITY}" ]]; then
    echo "CODESIGN_IDENTITY must not be empty." >&2
    exit 1
  fi

  codesign_identity="${CODESIGN_IDENTITY}"
  signing_identity_source="explicit"
else
  detected_identity="$(find_signing_identity "${signing_identity_name}" || true)"
  if [[ -n "${detected_identity}" ]]; then
    codesign_identity="${detected_identity}"
    signing_identity_source="auto-detected"
  else
    codesign_identity="-"
    signing_identity_source="ad-hoc"
  fi
fi

cd "${repo_root}"
swift build -c release

launchctl bootout "gui/${UID}" "${launch_agent_path}" 2>/dev/null || true
stop_executable "${executable_path}"

mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources" "${HOME}/Applications" "${HOME}/Library/LaunchAgents" "${log_dir}"
cp ".build/release/${executable_name}" "${executable_path}"
cp "${icon_source_path}" "${icon_destination_path}"
chmod 755 "${executable_path}"

swap_directions_argument=""
if [[ "${swap_directions}" == "1" || "${swap_directions}" == "true" || "${swap_directions}" == "yes" ]]; then
  swap_directions_argument="    <string>--swap-directions</string>"
fi

exclude_bundle_ids_argument=""
if [[ -n "${exclude_bundle_ids}" ]]; then
  escaped_exclude_bundle_ids="$(xml_escape "${exclude_bundle_ids}")"
  exclude_bundle_ids_argument="    <string>--exclude-bundle-id</string>
    <string>${escaped_exclude_bundle_ids}</string>"
fi

cat > "${app_path}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>${executable_name}</string>
  <key>CFBundleIdentifier</key>
  <string>${bundle_id}</string>
  <key>CFBundleName</key>
  <string>${app_name}</string>
  <key>CFBundleDisplayName</key>
  <string>${app_name}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --deep --sign "${codesign_identity}" "${app_path}" >/dev/null
/usr/bin/codesign --verify --deep --strict "${app_path}" >/dev/null

cat > "${launch_agent_path}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${bundle_id}</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>${bundle_id}</string>
  </array>
  <key>ProgramArguments</key>
  <array>
    <string>${executable_path}</string>
    <string>run</string>
    <string>--cooldown-ms</string>
    <string>${cooldown_ms}</string>
${swap_directions_argument}
${exclude_bundle_ids_argument}
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardErrorPath</key>
  <string>${log_dir}/mission-wheel.err.log</string>
  <key>StandardOutPath</key>
  <string>${log_dir}/mission-wheel.log</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "${app_path}/Contents/Info.plist" "${launch_agent_path}" >/dev/null
launchctl bootstrap "gui/${UID}" "${launch_agent_path}"

sleep 1
agent_state="$(launchctl print "gui/${UID}/${bundle_id}" 2>/dev/null | awk -F '= ' '/state = / { print $2; exit }')"

if [[ "${codesign_identity}" == "-" ]]; then
  signing_summary="ad-hoc"
  signing_guidance="If it does not react, open System Settings > Privacy & Security > Accessibility
and enable \"${app_name}\". The agent waits for permission and should begin
reacting shortly after the grant.

Ad-hoc signed rebuilds get a new code hash, so macOS may require a fresh
Accessibility approval after reinstall. For stable approval across rebuilds,
run this once and reinstall:

  scripts/create-signing-identity.sh
  scripts/install.sh

If macOS keeps a stale denial, reset this app's Accessibility entry first:

  tccutil reset Accessibility ${bundle_id}

Then add \"${app_path}\" in Accessibility and enable it."
else
  signing_summary="${codesign_identity} (${signing_identity_source})"
  signing_guidance="If it does not react, open System Settings > Privacy & Security > Accessibility
and enable \"${app_name}\". The agent waits for permission and should begin
reacting shortly after the grant.

After the first approval, reinstalls signed with the same identity should keep
the existing Accessibility approval."
fi

cat <<EOF
Installed ${app_name}.

App: ${app_path}
LaunchAgent: ${launch_agent_path}
Code signing: ${signing_summary}
Logs:
  ${log_dir}/mission-wheel.log
  ${log_dir}/mission-wheel.err.log

LaunchAgent state: ${agent_state:-unknown}

${signing_guidance}
EOF
