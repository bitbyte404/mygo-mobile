#!/bin/bash
# Release build: arm64 + armv7 + x86_64 split APKs. Needs tools/env.sh and the local proxy.
source /workspace/work/tools/env.sh
pgrep -f localproxy.py >/dev/null || (setsid nohup python3 /workspace/work/tools/localproxy.py >/tmp/localproxy.log 2>&1 &)
cd /workspace/work/mygo-mobile
flutter build apk --release --split-per-abi "$@"
rc=$?
# AGP can "succeed" with an APK that has no AndroidManifest.xml when an aapt2 step
# fails quietly (see README, aapt2 wrapper). Refuse such output.
if [[ $rc == 0 ]]; then
  for apk in build/app/outputs/flutter-apk/app-*-release.apk; do
    if ! unzip -l "$apk" | grep -q ' AndroidManifest.xml$'; then
      echo "ERROR: $apk has no AndroidManifest.xml (aapt2 optimize failed?)"; rc=2
    fi
    if ! unzip -l "$apk" | grep -q 'lib/.*/libmygojs.so$'; then
      echo "ERROR: $apk has no libmygojs.so"; rc=2
    fi
  done
fi
echo "BUILD_EXIT $rc"
exit $rc
