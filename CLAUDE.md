# SleepNoise

## Purpose

A minimal sleep noise app. The primary use case is falling asleep; secondary uses include noise masking, focus, and relaxation. The app intentionally has no presets, no buttons, no preferences, and a single view. Minimalism is a core design constraint — resist suggestions to add UI chrome, settings, or explanatory text.

## The Grid

The grid provides a continuous range of noise. The user drags a dot to find a sound that is soothing to them. Discovery is intentional — there is no axis labeling or onboarding. Broadly: moving the dot changes pitch/tone, giving access to a wide spectrum from bright to dark noise.

## Bookmarks

Bookmarks are automatic — they record a position the user has genuinely settled on, not a deliberate "save" action. In production, a bookmark is created after 15 minutes of playing at a position (`dwellDuration = 900`). The current value of 10 seconds is for development/testing only.

Bookmark UX intent:

- Subtle visibility is intentional — bookmarks should not clutter the minimal UI
- No progress indicator during dwell — the feature is meant to be discovered, not explained
- Haptic feedback (one-time pulse) when the dot first overlaps a bookmark, so the user knows they've found a saved position
- No snapping to bookmarks
- No manual deletion — bookmarks are evicted FIFO when the limit (5) is reached

## First Launch

On first launch (no previously saved position), the dot is placed at a default position of 75% from the left and 75% from the top of the grid. This puts the user in a warm, mid-dark noise range as a starting point.

## Interaction Model

- **Move the dot**: drag it anywhere on the grid
- **Start/stop**: tap anywhere on the screen to toggle playback
- The dot persists its last position between sessions

## Platform

- iPhone and iPad, portrait only
- Audio must continue when the screen locks (`.playback` audio session category)
- Target user is in bed, possibly in the dark — interactions should be forgiving and low-effort
- Opening the app must not interrupt existing device playback (e.g. music, podcasts) — the audio session should only become active when the user taps to start playing noise

## Battery

- The app should minimize its impact on battery life — users may run it for hours overnight
- Release audio hardware (stop the AVAudioEngine) when the user stops playback; do not keep the engine running silently
- Avoid background processing, timers, or work that runs when audio is not playing

## Performance

- Tapping rapidly must not cause the UI to fall behind or appear to get stuck — the dot's active/inactive state must always reflect the true playback state immediately
- Audio engine start/stop must not block the main thread or cause frame drops
- Drag interactions must remain smooth at all times

## Non-goals

- No preset sounds
- No settings or preferences screen
- No onboarding or feature explanations
- No manual bookmark management
