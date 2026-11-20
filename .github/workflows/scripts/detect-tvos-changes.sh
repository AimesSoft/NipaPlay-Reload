#!/usr/bin/env bash
set -euo pipefail

result=0
git diff --quiet --no-ext-diff --no-renames --ignore-submodules=none HEAD^1 HEAD -- \
  .flutter-version-tvos .gitmodules .gitattributes .metadata \
  .github/workflows/build-tvos.yml .github/workflows/build-all-manual.yml \
  .github/workflows/main.yml .github/workflows/scripts/ .github/actions/ \
  pubspec.yaml pubspec.lock ':(top,glob)pubspec_overrides*.yaml' \
  l10n.yaml flutter_rust_bridge.yaml \
  tvos/ ios/ packages/ third_party/ rust/ rust_builder/ cpp_native/ \
  tool/ tools/ scripts/ ':(top,glob)*.sh' \
  lib/ assets/ others/ \
  ':(exclude)lib/next/' ':(exclude)assets/next/' ':(exclude)scripts/next/' \
  || result=$?

case "$result" in
  0) echo 'build=false' >> "$GITHUB_OUTPUT" ;;
  1) echo 'build=true' >> "$GITHUB_OUTPUT" ;;
  *)
    echo '::warning::Could not compare the PR merge commit to its base; building tvOS.'
    echo 'build=true' >> "$GITHUB_OUTPUT"
    ;;
esac
