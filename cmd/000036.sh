# timeout=900
cd "$DS_REPO" && git log -1 --format="%h %s" && flutter analyze 2>&1 | tail -2 && flutter test 2>&1 | tail -1 && flutter build apk --release 2>&1 | tail -1; mkdir -p "$DS_ART" && cp build/app/outputs/flutter-apk/app-release.apk "$DS_ART/directional-audio-0.2.0.apk"
