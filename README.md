# JABA: Julie's Aurora Borealis App

A native iPhone app (SwiftUI, iOS 26+) that answers one question for any place you
save: **should I get out of the tent tonight to see the northern lights?**

Each location gets a **0–100 score** and a **GO / MAYBE / NO** verdict, the
reasoning behind it, the best time to look, and an hour-by-hour view of Kp index
and cloud cover. The design follows the iOS Weather app: a list of location cards,
and swipeable full-screen detail pages.

## What it shows

- **Location list**: one card per place with tonight's score, verdict, best
  window (or what's blocking it), peak Kp and cloud cover. Search adds places;
  each result shows the Kp that place needs.
- **Detail page**:
  - **Tonight**: the verdict, the best time with Kp, cloud and temperature,
    plain-language reasoning, and a good/fair/bad breakdown of the three
    factors at the key hour.
  - **Conditions**: the next 24 hours as columns. A glass toggle switches between
    **Kp index** and **cloud cover**, with sunset and sunrise columns. GO and
    MAYBE hours are tinted.
  - **3-Night Outlook**: Kp range bars for as far ahead as NOAA forecasts, with
    a tick at the Kp this place needs. Tap a night for its reasoning.
  - **Right Now**: NOAA's 30-minute aurora model for this spot: the chance of
    aurora overhead and within view.
  - **Tiles**: magnetic latitude, current Kp, sunset/sunrise, and when the sky is
    properly dark.
- **Offline cache**: the last forecast is saved on the phone. With no signal
  (in a tent), JABA re-scores it against the current time and marks it as old.
- **Alerts**: optional notifications 10 minutes before a GO window (and
  optionally MAYBE). They are scheduled on the phone, so they fire even without
  signal. Background refreshes update them. JABA also alerts immediately if
  NOAA's nowcast shows aurora in view while it's dark and not overcast.

## How the score works

The Kp needed at a location comes from its **magnetic latitude**. JABA computes
it with a centered-dipole model (IGRF geomagnetic pole, epoch 2025) and
interpolates the standard NOAA/UAF visibility table.

| Place      | Magnetic lat. | Kp needed |
|------------|---------------|-----------|
| Canmore    | 57.3°         | ~4.5      |
| Haines     | 62.3°         | ~2.0      |
| Whitehorse | 63.8°         | ~1.3      |

"High" and "moderate" Kp are measured against that local threshold. Each hour
between sunset and sunrise is rated:

| Verdict | Score  | Rule |
|---------|--------|------|
| **NO**    | 0      | Kp more than 1 below the local threshold (too weak even for a camera), **or** more than 50% cloud, **or** daylight/civil twilight, **or** nautical twilight without high Kp |
| **MAYBE** | 30–69  | Anything that passes the NO checks but isn't a GO: Kp within ±1 of the threshold, 10–50% cloud, or deep twilight during a strong storm. *Take a photo facing north.* |
| **GO**    | 70–100 | Kp at least 1 above the threshold, **and** under 10% cloud, **and** dark (sun below −12°) |

Within a band, the score weighs Kp margin (50%), clear sky (35%) and darkness
(15%). Tonight's score is the best hour, and the best window is the run of
hours around it with the same verdict. All thresholds live in `ScoringRules`
([JABAKit/Sources/JABAKit/Scoring.swift](JABAKit/Sources/JABAKit/Scoring.swift)).

## Data sources (no API keys)

| Data | Source |
|------|--------|
| 3-day Kp forecast (3-hour blocks) | NOAA SWPC `noaa-planetary-k-index-forecast.json`. This is the same NOAA forecast that [gi.alaska.edu/monitors/aurora-forecast](https://www.gi.alaska.edu/monitors/aurora-forecast) displays; the GI site has no API of its own. |
| 30-minute aurora nowcast | NOAA SWPC OVATION `ovation_aurora_latest.json` |
| Hourly cloud cover, temperature, sunrise/sunset | [Open-Meteo](https://open-meteo.com) forecast API |
| Place search | Open-Meteo geocoding API |
| Sun elevation, twilight, magnetic latitude | Computed on the phone |

## Project layout

```
JABA.xcodeproj         Xcode project (app target + local package)
JABA/                  SwiftUI app
  JABAApp.swift        entry point, background refresh, notification delegate
  AppModel.swift       locations, refresh, offline cache, alert preferences
  AlertScheduler.swift local notifications for GO windows and the nowcast
  Theme.swift          colors, card style, shared small views
  Views/               list, detail pager, conditions strip, outlook cards, sky background, settings
JABAKit/               Swift package: the forecast engine (Foundation only)
  Sources/JABAKit/     data clients, parsers, geomagnetic + solar math, scoring, outlook builder
  Tests/JABAKitTests/  scoring, parsing, sun math and full-night scenario tests
```

## Building

Requires **Xcode 27** (iOS 27 SDK). Open `JABA.xcodeproj`, choose your team
under *Signing & Capabilities* (the bundle ID is `com.charlieq.jaba`; change it
if needed), and run on an iPhone or simulator.

Run the engine tests without Xcode, using the Command Line Tools:

```bash
cd JABAKit
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test --build-system native -Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F \
  -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

With Xcode, `swift test` works directly, or run the JABA scheme's tests (⌘U).

## Limitations

- NOAA's Kp forecast is planetary and in 3-hour blocks, so hourly Kp repeats
  within a block, and local activity can differ from it.
- The dipole magnetic latitude is accurate to about a degree.
- Moonlight and light pollution aren't scored yet. Both matter for faint (MAYBE) aurora.
- iOS decides when background refreshes run. The scheduled GO alerts are
  reliable; the live nowcast alert only fires when iOS wakes the app.
