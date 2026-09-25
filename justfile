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

# Delete build output
[macos]
clean:
    rm -rf build
