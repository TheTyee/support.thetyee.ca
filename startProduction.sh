#!/bin/bash
# Resume normal service: turn maintenance mode OFF (site goes live).
DIR="$(cd "$(dirname "$0")" && pwd)"
rm -f "$DIR/maintenance.on"
echo "maintenance mode OFF - site is serving normally"
