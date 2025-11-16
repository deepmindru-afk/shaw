#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/backend" || exit 1
exec bash start.sh
