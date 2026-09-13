#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d /tmp/indus-docker-cleanup-test.XXXXXX)"

cleanup() {
  case "$test_root" in
    /tmp/indus-docker-cleanup-test.*) rm -r "$test_root" ;;
    *) echo "Refusing to remove unexpected test path: $test_root" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

export DOCKER_CLEANUP_TEST_LOG="$test_root/docker.log"
export PATH="$repo_root/scripts/docker/fixtures:$PATH"

bash "$repo_root/scripts/docker/cleanup.sh" --status >/dev/null
if grep -Eq '(^| )(rm|prune)( |$)' "$DOCKER_CLEANUP_TEST_LOG"; then
  echo "Status mode issued a destructive Docker command." >&2
  exit 1
fi

: >"$DOCKER_CLEANUP_TEST_LOG"
bash "$repo_root/scripts/docker/cleanup.sh" --force >/dev/null

grep -Fxq "rm --force indus-container" "$DOCKER_CLEANUP_TEST_LOG"
grep -Fxq "volume rm indus-volume" "$DOCKER_CLEANUP_TEST_LOG"
grep -Fxq "network rm indus-network" "$DOCKER_CLEANUP_TEST_LOG"
grep -Fxq "image rm --force indus-image" "$DOCKER_CLEANUP_TEST_LOG"

if grep -Eq '^(rm|volume rm|network rm|image rm).*control-|(^| )prune( |$)' "$DOCKER_CLEANUP_TEST_LOG"; then
  echo "Cleanup touched a control resource or issued a global prune." >&2
  exit 1
fi

if bash "$repo_root/scripts/docker/cleanup.sh" --all-unused >/dev/null 2>&1; then
  echo "Removed global cleanup option was still accepted." >&2
  exit 1
fi
