#!/bin/sh
# {{AppName}} launcher for Linux/macOS: runs the entry script with PowerShell 7 (pwsh).
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if ! command -v pwsh >/dev/null 2>&1; then
  echo "ERROR: PowerShell 7 (pwsh) was not found. Install it from https://learn.microsoft.com/powershell/scripting/install/installing-powershell" >&2
  exit 3
fi
exec pwsh -NoLogo -NoProfile -File "$here/Start-{{AppId}}.ps1" "$@"
