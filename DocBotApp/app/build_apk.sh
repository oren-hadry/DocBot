#!/bin/bash

# Build APK and copy to fixed location
# Usage: ./build_apk.sh [release|debug]

BUILD_TYPE="${1:-release}"
OUTPUT_DIR="/Users/oren/Documents/personal/DocBot/DocBotApp/builds"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

echo "Building $BUILD_TYPE APK..."

# Build the APK
flutter build apk --$BUILD_TYPE \
  --dart-define=API_BASE_URL=http://192.168.2.12:8000 \
  --dart-define=ALLOW_INSECURE_HTTP=true

if [ $? -eq 0 ]; then
    # Find the built APK
    if [ "$BUILD_TYPE" = "release" ]; then
        APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
        OUTPUT_NAME="docbot_release_${TIMESTAMP}.apk"
    else
        APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
        OUTPUT_NAME="docbot_debug_${TIMESTAMP}.apk"
    fi

    if [ -f "$APK_PATH" ]; then
        # Copy with timestamp
        cp "$APK_PATH" "$OUTPUT_DIR/$OUTPUT_NAME"
        
        # Also keep a "latest" copy
        LATEST_NAME="docbot_${BUILD_TYPE}_latest.apk"
        cp "$APK_PATH" "$OUTPUT_DIR/$LATEST_NAME"
        
        # Copy to Downloads folder
        cp "$APK_PATH" ~/Downloads/app-release.apk
        
        echo ""
        echo "✅ APK built successfully!"
        echo "📁 Saved to: $OUTPUT_DIR/$OUTPUT_NAME"
        echo "📁 Latest:   $OUTPUT_DIR/$LATEST_NAME"
        echo "📁 Downloads: ~/Downloads/app-release.apk"
    else
        echo "❌ APK file not found at $APK_PATH"
        exit 1
    fi
else
    echo "❌ Build failed"
    exit 1
fi
