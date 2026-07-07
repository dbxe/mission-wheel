#!/bin/zsh
set -euo pipefail

bundle_id="com.danielbriskin.mission-wheel"
app_name="Mission Wheel"
executable_name="mission-wheel"
app_path="${HOME}/Applications/${app_name}.app"
executable_path="${app_path}/Contents/MacOS/${executable_name}"
launch_agent_path="${HOME}/Library/LaunchAgents/${bundle_id}.plist"

stop_executable() {
  local executable_to_stop="$1"
  [[ -n "${executable_to_stop}" ]] || return 0

  pkill -TERM -f "${executable_to_stop}" 2>/dev/null || true
  sleep 0.2
  pkill -KILL -f "${executable_to_stop}" 2>/dev/null || true
}

launchctl bootout "gui/${UID}" "${launch_agent_path}" 2>/dev/null || true
stop_executable "${executable_path}"
rm -f "${launch_agent_path}"
rm -rf "${app_path}"

echo "Uninstalled ${app_name}."
