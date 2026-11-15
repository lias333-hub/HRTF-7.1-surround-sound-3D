# timeout=900
cd "$DS_REPO" && flutter build apk --release 2>&1 | tail -2; mkdir -p "$DS_ART" && cp build/app/outputs/flutter-apk/app-release.apk "$DS_ART/directional-audio-0.2.0.apk" && ls -la "$DS_ART"
