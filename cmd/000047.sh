# timeout=800
flutter analyze 2>&1 | tail -3; flutter test 2>&1 | tail -2; bash ci/prepare_android.sh >/dev/null 2>&1; flutter build apk --release 2>&1 | grep -E "Built|FAIL|e: " | head; mkdir -p "$DS_ART" && cp build/app/outputs/flutter-apk/app-release.apk "$DS_ART/directional-audio-v0.3.0.apk" && ls -la "$DS_ART"/*.apk
