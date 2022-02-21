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

NO_COLOR=${NO_COLOR:-""}

shopt -s expand_aliases
if [ -z "$NO_COLOR" ]; then
  alias log_info="echo -e \"\033[1;32mINFO\033[0m:\""
  alias log_error="echo -e \"\033[1;31mERROR\033[0m:\""
else
  alias log_info="echo \"INFO:\""
  alias log_error="echo \"ERROR:\""
fi

set -e

shaprog() {
  case $OS in
    Linux)
      sha256sum "$1" | cut -d' ' -f1
      ;;
    macOS)
      shasum -a256 "$1" | cut -d' ' -f1
      ;;
    Windows)
      powershell -command "(Get-FileHash ""$1"" -Algorithm SHA256 | Select-Object -ExpandProperty Hash).ToLower()"
      ;;
    *)
      log_error "unsupported OS $OS"
      exit 1
      ;;
  esac
}
