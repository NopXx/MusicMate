#!/bin/bash
# Patch project.pbxproj so AppIcon.icon is recognized as Icon Composer bundle.
# xcodegen sets folder type → Xcode treats as plain CpResource and skips actool.
set -euo pipefail
PBX="MusicMate.xcodeproj/project.pbxproj"
/usr/bin/sed -i '' \
  -E 's|(/\* AppIcon\.icon \*/ = \{isa = PBXFileReference;)( lastKnownFileType = folder\.iconcomposericon;)* lastKnownFileType = folder;|\1 lastKnownFileType = folder.iconcomposericon;|' \
  "$PBX"
echo "[fix-icon-filetype] patched $PBX"
