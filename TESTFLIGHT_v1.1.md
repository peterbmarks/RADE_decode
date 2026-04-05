# RADE Decode v1.1 — TestFlight Release Notes

## What's New

This release adds EOO (End-of-Over) callsign decoding, allowing the iOS receiver to detect and display the transmitter's callsign sent by Android TX at the end of a voice session.

---

## What to Test

### 1. EOO Callsign Decoding (Core Feature)

**Prerequisite:** An Android device running RADE TX with a configured callsign.

- [ ] Android starts TX → iOS starts RX → wait for sync
- [ ] Android stops TX (sends EOO frame) → iOS should display the callsign
- [ ] Callsign banner disappears automatically after ~10 seconds
- [ ] Repeat 5+ times and note the success rate (expected >60%; >95% after Android gain fix)
- [ ] Test with various callsign lengths (1–8 characters)

### 2. Callsign Auto-Dismiss

- [ ] After successful decode, callsign banner appears for ~10 seconds
- [ ] Banner fades out smoothly (no abrupt flash)
- [ ] Receiving a new EOO re-triggers the banner and resets the timer

### 3. Reception Log Deletion (Crash Fix)

- [ ] Open Reception Log with existing session records
- [ ] Swipe-delete a single session → app should NOT crash
- [ ] Rapidly delete multiple sessions in succession → app should NOT crash
- [ ] Delete a session that contains callsign records → app should NOT crash
- [ ] Delete a session with a recorded WAV → confirm the WAV file is also removed

### 4. Reception Log Accuracy

- [ ] Session duration looks reasonable (no extra ~3 seconds)
- [ ] Callsign events display correctly in session detail
- [ ] Charts (SNR, Sync Timeline, etc.) render properly in session detail

### 5. Background Capture + Foreground Analysis

- [ ] Start RX → switch to background → wait 30+ seconds → return to foreground
- [ ] Background analysis page should show a pending analysis task
- [ ] Switch to background during analysis → should be paused when returning
- [ ] Press STOP during analysis → analysis continues, live RX stops

### 6. General Stability

- [ ] App launches normally; onboarding flow works
- [ ] Settings page options are functional
- [ ] Spectrum / Waterfall displays render correctly
- [ ] Map does NOT show coordinates for background-replay decoded events
- [ ] Extended RX (>10 minutes) does not crash or cause excessive memory usage

---

## Known Limitations

- Android TX currently applies a 0.45× gain to EOO frames, reducing callsign decode success rate to ~60–70%. After the Android-side fix, success rate is expected to exceed 95%.
- Background analysis task queue shares a single underlying audio file; multiple background capture sessions may overwrite each other.

---

## How to Report Issues

Please include:
1. Steps to reproduce
2. Screenshots or screen recordings
3. Approximate time the issue occurred (to correlate with console logs)

---

## Build Info

- Version: 1.1
- Build: 1
- Minimum iOS: 17.0
