#!/usr/bin/env bash
set -euo pipefail

dest="${1:-third_party/cv32e40x}"
ref="${2:-master}"
repo="${COREV_CV32E40X_REPO:-https://github.com/openhwgroup/cv32e40x.git}"

mkdir -p "$(dirname "$dest")"

if [[ -d "$dest/.git" ]]; then
  git -C "$dest" fetch --depth 1 origin "$ref"
  git -C "$dest" checkout --detach FETCH_HEAD
else
  if ! git clone --depth 1 --branch "$ref" "$repo" "$dest"; then
    if [[ "$ref" == "master" ]]; then
      git clone --depth 1 --branch main "$repo" "$dest"
    else
      exit 1
    fi
  fi
fi

git -C "$dest" submodule update --init --recursive --depth 1
git -C "$dest" rev-parse --short HEAD

