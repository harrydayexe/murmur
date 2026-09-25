derived_data := "build/DerivedData"
app := derived_data / "Build/Products/Debug/Murmur.app"
xcodebuild := "xcodebuild -scheme Murmur -destination 'platform=macOS' -derivedDataPath " + derived_data

# Regenerate Murmur.xcodeproj from project.yml
[macos]
generate:
    xcodegen generate

# Build the Debug app
[macos]
build: generate
    {{xcodebuild}} build

# Run the test suite
[macos]
test: generate
    {{xcodebuild}} test

# Build, quit any running Murmur, then launch the fresh build
[default]
[macos]
run: build stop
    open "{{app}}"

# Quit any running Murmur
[macos]
stop:
    -pkill -x Murmur

# Open the project in Xcode
[macos]
open: generate
    open Murmur.xcodeproj

# Set the marketing version (e.g. just new-version 0.1.1) and bump the build number
[macos]
new-version version:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! "{{version}}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "error: version must look like X.Y.Z" >&2
        exit 1
    fi
    build=$(sed -nE 's/^ *CFBundleVersion: "([0-9]+)"/\1/p' project.yml)
    next=$((build + 1))
    sed -i '' -E \
        -e 's/^( *CFBundleShortVersionString: )"[^"]*"/\1"{{version}}"/' \
        -e "s/^( *CFBundleVersion: )\"[0-9]+\"/\1\"$next\"/" \
        project.yml
    echo "Murmur {{version}} (build $next)"

# Delete build output
[macos]
clean:
    rm -rf build
