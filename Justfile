generate:
    xcodegen generate

simulators:
    xcrun simctl list devices booted

screenshot:
    xcrun simctl io screenshot screenshot.png

