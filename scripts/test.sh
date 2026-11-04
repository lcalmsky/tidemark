#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

args=()
developer="$(xcode-select -p 2>/dev/null || true)"
# Command Line Tools 만 있으면 SwiftPM 이 Testing.framework 경로를 넘기지 않아 직접 넘긴다.
if [[ $developer == */CommandLineTools ]]; then
    frameworks="$developer/Library/Developer/Frameworks"
    libs="$developer/Library/Developer/usr/lib"
    args=(-Xswiftc -F -Xswiftc "$frameworks"
          -Xlinker -rpath -Xlinker "$frameworks"
          -Xlinker -rpath -Xlinker "$libs")
fi

output="$(swift test ${args[@]+"${args[@]}"} 2>&1)" || { printf '%s\n' "$output"; exit 1; }
printf '%s\n' "$output"

# 테스트 러너가 Testing 을 찾지 못하면 0건을 돌리고도 0 으로 끝나므로 실행 건수를 확인한다.
summary="$(printf '%s\n' "$output" | grep -E 'Test run with [0-9]+ tests? .* passed' | tail -1 || true)"
count="$(printf '%s\n' "$summary" | sed -E 's/.*Test run with ([0-9]+) tests?.*/\1/')"
if [[ -z $summary || ${count:-0} -eq 0 ]]; then
    echo "오류: 실행된 테스트가 없습니다" >&2
    exit 1
fi
