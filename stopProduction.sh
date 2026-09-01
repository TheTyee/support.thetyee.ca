#!/bin/bash
# Go into maintenance: turn maintenance mode ON (visitors see the maintenance page).
DIR="$(cd "$(dirname "$0")" && pwd)"
touch "$DIR/maintenance.on"
echo "maintenance mode ON - visitors see the maintenance page (HTTP 503)"
