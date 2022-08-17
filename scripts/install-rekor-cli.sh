#!/usr/bin/env bash
# Copyright 2022 The Sigstore Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT=$(dirname "${BASH_SOURCE[0]}")/..
# shellcheck source=../scripts/utils.sh
source "${REPO_ROOT}/scripts/utils.sh"

install_rekor() {
  if [[ $REKOR_VERSION == "main" ]]; then
    log_info "installing cosign via 'go install' from its main version"
    GOBIN=$(go env GOPATH)/bin
    go install github.com/sigstore/rekor/cmd/rekor-cli@main
    ln -s "$GOBIN"/rekor-cli "$(eval echo "$INSTALL_DIR")"/rekor-cli
    exit 0
  fi

  trap "popd >/dev/null" EXIT

  pushd "$(eval echo "$INSTALL_DIR")" > /dev/null

  case $OS in
    Linux)
      case $ARCH in
        X64)
          desired_rekor_cli_filename='rekor-cli-linux-amd64'
          ;;

        ARM)
          desired_rekor_cli_filename='rekor-cli-linux-arm'
          ;;

        ARM64)
          desired_rekor_cli_filename='rekor-cli-linux-amd64'
          ;;

        *)
          log_error "unsupported architecture $ARCH"
          exit 1
          ;;
      esac
      ;;

    macOS)
      case $ARCH in
        X64)
          desired_rekor_cli_filename='rekor-cli-darwin-amd64'
          ;;

        ARM64)
          desired_rekor_cli_filename='rekor-cli-darwin-arm64'
          ;;

        *)
          log_error "unsupported architecture $ARCH"
          exit 1
          ;;
      esac
      ;;

    Windows)
      case $ARCH in
        X64)
          desired_rekor_cli_filename='rekor-cli-windows-amd64.exe'
          ;;
        *)
          log_error "unsupported architecture $ARCH"
          exit 1
          ;;
      esac
      ;;
    *)
      log_error "unsupported architecture $ARCH"
      exit 1
      ;;
  esac

  semver='^v([0-9]+\.){0,2}(\*|[0-9]+)$'
  if [[ $REKOR_VERSION =~ $semver ]]; then
    log_info "Custom rekor-cli version '$REKOR_VERSION' requested"
  else
    log_error "Unable to validate requested rekor-cli version: '$REKOR_VERSION'"
    exit 1
  fi

  # Download custom rekor-cli
  log_info "Downloading platform-specific version '$REKOR_VERSION' of rekor-cli...\n      https://github.com/sigstore/rekor/releases/download/$REKOR_VERSION/${desired_rekor_cli_filename}"
  curl -sL https://github.com/sigstore/rekor/releases/download/"$REKOR_VERSION"/${desired_rekor_cli_filename} -o rekor-cli_"$REKOR_VERSION"

  log_info "Using default cosign to verify signature of desired cosign version"
  COSIGN_EXPERIMENTAL=1 cosign verify-blob --signature https://github.com/sigstore/rekor/releases/download/"$REKOR_VERSION"/${desired_rekor_cli_filename}-keyless.sig rekor-cli_"$REKOR_VERSION"

  mv rekor-cli_"$REKOR_VERSION" rekor-cli
  chmod +x rekor-cli
  log_info "Installation complete!"
  exit 0
}
