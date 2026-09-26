#!/bin/bash
# run.sh <logname> <Test-IDs…>  – baut und führt nur die angegebenen Tests aus (macOS, eigene DerivedData)
C=$(cd "$(dirname "$0")" && pwd)
LOG=$C/logs/$1.log; shift
ARGS=(); for t in "$@"; do ARGS+=("-only-testing:MikaPlusPlayerTests/$t"); done
cd $C
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export TEST_RUNNER_B07_BRIDGE=$C/bridge
xcodebuild test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' \
  -derivedDataPath build/dd -skipPackagePluginValidation "${ARGS[@]}" > $LOG 2>&1
grep -E "^\*\* (BUILD|TEST).*\*\*|error:|Executed [0-9]+ test|Test Case .*(passed|failed|skipped)" $LOG | sort -u | head -60
