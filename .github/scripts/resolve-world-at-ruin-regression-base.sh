#!/usr/bin/env bash
# Resolve the target repository's GitHub-supplied base commit without reading
# any ref, selector, or control bytes from the candidate checkout.
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${TARGET_REPOSITORY:?TARGET_REPOSITORY is required}"
: "${EVENT_NAME:?EVENT_NAME is required}"

source_repository="devantler-tech/actions"
target_repository="devantler-tech/world-at-ruin"

# Required-workflow source files also receive ordinary events in their own
# repository until/if the workflow is disabled. Complete those runs without
# evaluating this target-specific product gate. No other target may no-op.
if [ "${TARGET_REPOSITORY}" = "${source_repository}" ]; then
	printf '%s\n' 'run=false' >>"${GITHUB_OUTPUT}"
	exit 0
fi

if [ "${TARGET_REPOSITORY}" != "${target_repository}" ]; then
	echo "::error::unexpected required-workflow target: ${TARGET_REPOSITORY}" >&2
	exit 1
fi

case "${EVENT_NAME}" in
pull_request)
	trusted_sha="${PULL_REQUEST_BASE_SHA:-}"
	;;
merge_group)
	trusted_sha="${MERGE_GROUP_BASE_SHA:-}"
	;;
*)
	echo "::error::unsupported required-workflow event: ${EVENT_NAME}" >&2
	exit 1
	;;
esac

if [[ ! "${trusted_sha}" =~ ^[0-9a-f]{40}$ ]]; then
	echo "::error::trusted base is not a full commit SHA for ${EVENT_NAME}" >&2
	exit 1
fi

{
	printf '%s\n' 'run=true'
	printf 'trusted-sha=%s\n' "${trusted_sha}"
} >>"${GITHUB_OUTPUT}"
