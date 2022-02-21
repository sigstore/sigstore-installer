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

  bootstrap_version='v0.5.0'
  bootstrap_linux_amd64_sha='a55eba0b526be151ed4b83958d093e925e83c0cda8e15c6508e6d1d360735840'
  bootstrap_linux_arm_sha='342e0794453cedc72ef92ebaa110b68514c8457c9fcd8fcd64f6b24ed1abba53'
  bootstrap_linux_arm64_sha='e61850af805f5c12de92e10e90faaac178f1af200b7353f72d03b7fac8e32d8b'
  bootstrap_darwin_amd64_sha='00621c4ea74347394f7ed5722847259b3dc10256c89a6a568fc1f478f181b83c'
  bootstrap_darwin_arm64_sha='057def5bf18338fc4d85e889195315d2a815aa5784deb173b13cc41d4150ac15'
  bootstrap_windows_amd64_sha='af2342f28d9aba6b9c443c9cdc217357d7fd318fac57389e96dd62be0b34005a'

  trap "popd >/dev/null" EXIT

  pushd "$(eval echo "$INSTALL_DIR")" > /dev/null

  case $OS in
    Linux)
      case $ARCH in
        X64)
          bootstrap_filename='rekor-cli-linux-amd64'
          bootstrap_sha=${bootstrap_linux_amd64_sha}
          desired_rekor_cli_filename='rekor-cli-linux-amd64'
          ;;

        ARM)
          bootstrap_filename='rekor-cli-linux-arm'
          bootstrap_sha=${bootstrap_linux_arm_sha}
          desired_rekor_cli_filename='rekor-cli-linux-arm'
          ;;

        ARM64)
          bootstrap_filename='rekor-cli-linux-arm64'
          bootstrap_sha=${bootstrap_linux_arm64_sha}
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
          bootstrap_filename='rekor-cli-darwin-amd64'
          bootstrap_sha=${bootstrap_darwin_amd64_sha}
          desired_rekor_cli_filename='rekor-cli-darwin-amd64'
          ;;

        ARM64)
          bootstrap_filename='rekor-cli-darwin-arm64'
          bootstrap_sha=${bootstrap_darwin_arm64_sha}
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
          bootstrap_filename='rekor-cli-windows-amd64.exe'
          bootstrap_sha=${bootstrap_windows_amd64_sha}
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

  expected_bootstrap_version_digest=${bootstrap_sha}
  log_info "Downloading bootstrap version '${bootstrap_version}' of rekor-cli to verify version to be installed...\n      https://github.com/sigstore/rekor/releases/download/${bootstrap_version}/${bootstrap_filename}"
  curl -sL https://github.com/sigstore/rekor/releases/download/${bootstrap_version}/${bootstrap_filename} -o rekor-cli
  shaBootstrap=$(shaprog rekor-cli);
  if [[ $shaBootstrap != "${expected_bootstrap_version_digest}" ]]; then
    log_error "Unable to validate rekor-cli version: '$REKOR_VERSION'"
    exit 1
  fi
  chmod +x rekor-cli

  # If the bootstrap and specified `cosign` releases are the same, we're done.
  if [[ $REKOR_VERSION == "${bootstrap_version}" ]]; then
    log_info "bootstrap version successfully verified and matches requested version so nothing else to do"
    exit 0
  fi

  semver='^v([0-9]+\.){0,2}(\*|[0-9]+)$'
  if [[ $REKOR_VERSION =~ $semver ]]; then
    log_info "Custom rekor-cli version '$REKOR_VERSION' requested"
  else
    log_error "Unable to validate requested cosign version: '$REKOR_VERSION'"
    exit 1
  fi

  # Download custom cosign
  log_info "Downloading platform-specific version '$REKOR_VERSION' of rekor-cli...\n      https://github.com/sigstore/rekor/releases/download/$REKOR_VERSION/${desired_rekor_cli_filename}"
  curl -sL https://github.com/sigstore/rekor/releases/download/"$REKOR_VERSION"/${desired_rekor_cli_filename} -o rekor-cli_"$REKOR_VERSION"
  shaCustom=$(shaprog rekor-cli_"$REKOR_VERSION");

  # same hash means it is the same release
  if [[ $shaCustom != "$shaBootstrap" ]]; then
    log_info "Using bootstrap cosign to verify signature of desired cosign version"
    COSIGN_EXPERIMENTAL=1 cosign verify-blob --signature https://github.com/sigstore/rekor/releases/download/"$REKOR_VERSION"/${desired_rekor_cli_filename}-keyless.sig rekor-cli_"$REKOR_VERSION"

    mv rekor-cli_"$REKOR_VERSION" rekor-cli
    chmod +x rekor-cli
    log_info "Installation complete!"
  fi
}