#!/usr/bin/env bash
# Fails when the "where are we" documents do not mention the version in pubspec.yaml (AU-02): a document that still
# says 0.4.1 while the code is 0.5.0 is a false statement. Also checks that kAppVersion matches pubspec.yaml.
set -euo pipefail
cd "$(dirname "$0")/.."
v=$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' pubspec.yaml | head -1)
[ -n "$v" ] || { echo "cannot read the version from pubspec.yaml" >&2; exit 2; }
rc=0
for f in docs/CHECKPOINT.md docs/MANIFEST.md; do
  if grep -qF "$v" "$f"; then echo "ok: $f mentions $v"; else echo "STALE DOC: $f does not mention $v"; rc=1; fi
done
if grep -qF "const String kAppVersion = '$v';" lib/app_info.dart; then
  echo "ok: kAppVersion is $v"
else
  echo "VERSION MISMATCH: lib/app_info.dart kAppVersion is not $v"; rc=1
fi
exit $rc
