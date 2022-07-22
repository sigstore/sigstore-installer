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

  default_version='v0.9.1'
  default_linux_amd64_sha='1bebeaf3d8fbd16841a6f9cf86312085b4eb331075d17978af2fd221ce361eb3'
  default_linux_arm_sha='1fe49488ff6057c5d06f0fe8a383e5193319d108bf3d7955c58490ab1e74570b'
  default_linux_arm64_sha='d0d3c513baa89ab256cacebe6d33e5e765ecc493bc672aa213d5a87679a1aa1d'
  default_darwin_amd64_sha='3d06cf86d726f625f94d16613b671b0e280c349662bf50e2a7a262d09d993849'
  default_darwin_arm64_sha='10924422c9e48a35fba089039612c96bcb38b5e7799191b2e1119fd57a94fddf'
  default_windows_amd64_sha='f2f698d9210e85cd8264a45faec9afcb7907dd02614bdde96a5004bd5c1816e0'

  trap "popd >/dev/null" EXIT

  pushd "$(eval echo "$INSTALL_DIR")" > /dev/null

  case $OS in
    Linux)
      case $ARCH in
        X64)
          default_filename='rekor-cli-linux-amd64'
          default_sha=${default_linux_amd64_sha}
          desired_rekor_cli_filename='rekor-cli-linux-amd64'
          ;;

        ARM)
          default_filename='rekor-cli-linux-arm'
          default_sha=${default_linux_arm_sha}
          desired_rekor_cli_filename='rekor-cli-linux-arm'
          ;;

        ARM64)
          default_filename='rekor-cli-linux-arm64'
          default_sha=${default_linux_arm64_sha}
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
          default_filename='rekor-cli-darwin-amd64'
          default_sha=${default_darwin_amd64_sha}
          desired_rekor_cli_filename='rekor-cli-darwin-amd64'
          ;;

        ARM64)
          default_filename='rekor-cli-darwin-arm64'
          default_sha=${default_darwin_arm64_sha}
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
          default_filename='rekor-cli-windows-amd64.exe'
          default_sha=${default_windows_amd64_sha}
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

  expected_default_version_digest=${default_sha}
  log_info "Downloading default version '${default_version}' of rekor-cli to verify version to be installed...\n      https://github.com/sigstore/rekor/releases/download/${default_version}/${default_filename}"
  curl -sL https://github.com/sigstore/rekor/releases/download/${default_version}/${default_filename} -o rekor-cli
  shadefault=$(shaprog rekor-cli);
  if [[ $shadefault != "${expected_default_version_digest}" ]]; then
    log_error "Unable to validate rekor-cli version: '$REKOR_VERSION'"
    exit 1
  fi
  chmod +x rekor-cli

  # If the default and specified `rekor-cli` releases are the same, we're done.
  if [[ $REKOR_VERSION == "${default_version}" ]]; then
    COSIGN_EXPERIMENTAL=1 cosign verify-blob --signature https://github.com/sigstore/rekor/releases/download/"$REKOR_VERSION"/${desired_rekor_cli_filename}-keyless.sig rekor-cli
    log_info "default version successfully verified and matches requested version so nothing else to do"
    exit 0
  fi

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