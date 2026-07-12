#!/usr/bin/env bash
# Shared image selection/build behavior for the standalone test harnesses.

test_image_ref() {
  printf '%s\n' "${TEST_IMAGE:-hindsight-addon:dev}"
}

prepare_test_image() {
  local build_context=${1:?build context is required}
  local image
  image=$(test_image_ref)

  if [[ -n ${TEST_IMAGE:-} ]]; then
    printf '== pull prebuilt image: %s ==\n' "$image"
    docker pull "$image"
    return 0
  fi

  printf '%s\n' '== build =='
  docker build -t "$image" "$build_context"
}
