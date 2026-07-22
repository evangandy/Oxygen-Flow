#!/bin/bash
# Double-click this file in Finder to install Oxygen Flow — it opens Terminal and runs the
# full setup (make.sh) for you. No command line needed.
set -euo pipefail
cd "$(dirname "$0")"

./make.sh

echo
read -p "Press Return to close this window… "
