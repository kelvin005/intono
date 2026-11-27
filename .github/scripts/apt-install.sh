#!/usr/bin/env bash
# apt install for CI runners: drops the image's packages.microsoft.com source, which this repository never uses and which has returned
# 403 and failed a build (2026-11-27), then updates and installs with retries.  Usage: .github/scripts/apt-install.sh PKG...
set -euo pipefail
sudo rm -f /etc/apt/sources.list.d/microsoft-prod*
sudo apt-get -o Acquire::Retries=3 update
sudo apt-get -o Acquire::Retries=3 install -y "$@"
