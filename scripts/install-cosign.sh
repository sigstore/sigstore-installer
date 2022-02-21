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


install_cosign() {
  if [[ $COSIGN_VERSION == "main" ]]; then
    log_info "installing cosign via 'go install' from its main version"
    GOBIN=$(go env GOPATH)/bin
    go install github.com/sigstore/cosign/cmd/cosign@main
    ln -s "$GOBIN"/cosign "$(eval echo "$INSTALL_DIR")"/cosign
    return 0
  fi

  bootstrap_version='v1.5.2'
  bootstrap_linux_amd64_sha='080c0ba10674d2909fb3b4b867b102aefa021959edf2696c8cc1ba08e824bccb'
  bootstrap_linux_arm_sha='052fc183f5f114984f2292ead3a3dea88806d5b8c96ae6570c538aa2ddcb66fc'
  bootstrap_linux_arm64_sha='9b7551a871f14b4c278a7857c2cc7d9366b922ed9a4c73387f507ab25cfec463'
  bootstrap_darwin_amd64_sha='991c3f961f901aec75a4068ac2c3046bd5ab36d00cba6ddbf231b5d0123c83bf'
  bootstrap_darwin_arm64_sha='d6ceb52358b69e02ddc2194d47cf5587e8c4885aaa0b9dbb98f0902410adc2ae'
  bootstrap_windows_amd64_sha='b3f2636db8179c2c0a7cace2531d7c5e7bf37a26aaef960f040bf063f06469c6'

  trap "popd >/dev/null" return

  pushd "$(eval echo "$INSTALL_DIR")" > /dev/null

  case $OS in
    Linux)
      case $ARCH in
        X64)
          bootstrap_filename='cosign-linux-amd64'
          bootstrap_sha=${bootstrap_linux_amd64_sha}
          desired_cosign_filename='cosign-linux-amd64'
          # v0.6.0 had different filename structures from all other releases
          if [[ $COSIGN_VERSION == 'v0.6.0' ]]; then
            desired_cosign_filename='cosign_linux_amd64'
            desired_cosign_v060_signature='cosign_linux_amd64_0.6.0_linux_amd64.sig'
          fi
          ;;

        ARM)
          bootstrap_filename='cosign-linux-arm'
          bootstrap_sha=${bootstrap_linux_arm_sha}
          desired_cosign_filename='cosign-linux-arm'
          if [[ $COSIGN_VERSION == 'v0.6.0' ]]; then
            log_error "linux-arm build not available at v0.6.0"
            return 1
          fi
          ;;

        ARM64)
          bootstrap_filename='cosign-linux-arm64'
          bootstrap_sha=${bootstrap_linux_arm64_sha}
          desired_cosign_filename='cosign-linux-amd64'
          if [[ $COSIGN_VERSION == 'v0.6.0' ]]; then
            log_error "linux-arm64 build not available at v0.6.0"
            return 1
          fi
          ;;

        *)
          log_error "unsupported architecture $ARCH"
          return 1
          ;;
      esac
      ;;

    macOS)
      case $ARCH in
        X64)
          bootstrap_filename='cosign-darwin-amd64'
          bootstrap_sha=${bootstrap_darwin_amd64_sha}
          desired_cosign_filename='cosign-darwin-amd64'
          # v0.6.0 had different filename structures from all other releases
          if [[ $COSIGN_VERSION == 'v0.6.0' ]]; then
            desired_cosign_filename='cosign_darwin_amd64'
            desired_cosign_v060_signature='cosign_darwin_amd64_0.6.0_darwin_amd64.sig'
          fi
          ;;

        ARM64)
          bootstrap_filename='cosign-darwin-arm64'
          bootstrap_sha=${bootstrap_darwin_arm64_sha}
          desired_cosign_filename='cosign-darwin-arm64'
          # v0.6.0 had different filename structures from all other releases
          if [[ $COSIGN_VERSION == 'v0.6.0' ]]; then
            desired_cosign_filename='cosign_darwin_arm64'
            desired_cosign_v060_signature='cosign_darwin_arm64_0.6.0_darwin_arm64.sig'
          fi
          ;;

        *)
          log_error "unsupported architecture $ARCH"
          return 1
          ;;
      esac
      ;;

    Windows)
      case $ARCH in
        X64)
          bootstrap_filename='cosign-windows-amd64.exe'
          bootstrap_sha=${bootstrap_windows_amd64_sha}
          desired_cosign_filename='cosign-windows-amd64.exe'
          # v0.6.0 had different filename structures from all other releases
          if [[ $COSIGN_VERSION == 'v0.6.0' ]]; then
            desired_cosign_filename='cosign_windows_amd64.exe'
            desired_cosign_v060_signature='cosign_windows_amd64_0.6.0_windows_amd64.exe.sig'
          fi
          ;;
        *)
          log_error "unsupported architecture $ARCH"
          return 1
          ;;
      esac
      ;;
    *)
      log_error "unsupported architecture $ARCH"
      return 1
      ;;
  esac

  expected_bootstrap_version_digest=${bootstrap_sha}
  log_info "Downloading bootstrap version '${bootstrap_version}' of cosign to verify version to be installed...\n      https://storage.googleapis.com/cosign-releases/${bootstrap_version}/${bootstrap_filename}"
  curl -sL https://storage.googleapis.com/cosign-releases/${bootstrap_version}/${bootstrap_filename} -o cosign
  shaBootstrap=$(shaprog cosign);
  if [[ $shaBootstrap != "${expected_bootstrap_version_digest}" ]]; then
    log_error "Unable to validate cosign version: '$COSIGN_VERSION'"
    return 1
  fi
  chmod +x cosign

  # If the bootstrap and specified `cosign` releases are the same, we're done.
  if [[ $COSIGN_VERSION == "${bootstrap_version}" ]]; then
    log_info "bootstrap version successfully verified and matches requested version so nothing else to do"
    return 0
  fi

  semver='^v([0-9]+\.){0,2}(\*|[0-9]+)$'
  if [[ $COSIGN_VERSION =~ $semver ]]; then
    log_info "Custom cosign version '$COSIGN_VERSION' requested"
  else
    log_error "Unable to validate requested cosign version: '$COSIGN_VERSION'"
    return 1
  fi

  # Download custom cosign
  log_info "Downloading platform-specific version '$COSIGN_VERSION' of cosign...\n      https://storage.googleapis.com/cosign-releases/$COSIGN_VERSION/${desired_cosign_filename}"
  curl -sL https://storage.googleapis.com/cosign-releases/"$COSIGN_VERSION"/${desired_cosign_filename} -o cosign_"$COSIGN_VERSION"
  shaCustom=$(shaprog cosign_"$COSIGN_VERSION");

  # same hash means it is the same release
  if [[ $shaCustom != "$shaBootstrap" ]]; then
    if [[ $COSIGN_VERSION == 'v0.6.0' && $OS == 'Linux' ]]; then
      # v0.6.0's linux release has a dependency on `libpcsclite1`
      log_info "Installing libpcsclite1 package if necessary..."
      set +e
      if ! sudo dpkg -s libpcsclite1; then
          log_info "libpcsclite1 package is already installed"
      else
            log_info "libpcsclite1 package is not installed, installing it now."
            sudo apt-get update -q -q
            sudo apt-get install -yq libpcsclite1
      fi
      set -e
    fi

    if [[ $COSIGN_VERSION == 'v0.6.0' ]]; then
      log_info "Downloading detached signature for platform-specific '$COSIGN_VERSION' of cosign...\n      https://github.com/sigstore/cosign/releases/download/$COSIGN_VERSION/${desired_cosign_v060_signature}"
      curl -sL https://github.com/sigstore/cosign/releases/download/"$COSIGN_VERSION"/${desired_cosign_v060_signature} -o ${desired_cosign_filename}.sig
    else
      log_info "Downloading detached signature for platform-specific '$COSIGN_VERSION' of cosign...\n      https://github.com/sigstore/cosign/releases/download/$COSIGN_VERSION/${desired_cosign_filename}.sig"
      curl -sLO https://github.com/sigstore/cosign/releases/download/"$COSIGN_VERSION"/${desired_cosign_filename}.sig
    fi

    if [[ $COSIGN_VERSION < 'v0.6.0' ]]; then
      RELEASE_COSIGN_PUB_KEY=https://raw.githubusercontent.com/sigstore/cosign/"$COSIGN_VERSION"/.github/workflows/cosign.pub
    else
      RELEASE_COSIGN_PUB_KEY=https://raw.githubusercontent.com/sigstore/cosign/"$COSIGN_VERSION"/release/release-cosign.pub
    fi

    log_info "Using bootstrap cosign to verify signature of desired cosign version"
    ./cosign verify-blob --key "$RELEASE_COSIGN_PUB_KEY" --signature ${desired_cosign_filename}.sig cosign_"$COSIGN_VERSION"

    rm cosign
    mv cosign_"$COSIGN_VERSION" cosign
    chmod +x cosign
    log_info "Installation complete!"
  fi
}