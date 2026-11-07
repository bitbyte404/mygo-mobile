#!/bin/sh
# Stamps build/web/sw.js with a hash of the build, after `flutter build web`:
# every build that changes the app gets a new service worker and cache, and
# the home-screen app offers to reload. Usage: tool/stamp_sw.sh [build/web]
set -eu
dir="${1:-build/web}"
[ -f "$dir/sw.js" ] || { echo "no $dir/sw.js" >&2; exit 1; }
hash=$(cd "$dir" && find . -type f ! -name 'sw.js' ! -name '*.map' ! -name '*.gz' | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -c1-16)
sed -i "s/__MYGO_BUILD__/$hash/" "$dir/sw.js"
echo "sw.js build $hash"
