# OpenDash iOS

OpenDash iOS is a SwiftUI companion app for riders who want the OpenDash experience on iPhone. This first iOS build focuses on the features that are feasible on Apple devices without the unresolved dash-streaming proof of concept:

- Navigation planning with OSRM routing, ETA, remaining distance, and GPS status.
- Import shared map links from Google Maps, Apple Maps, or `geo:` URLs.
- Vehicle profiles with active-vehicle selection.
- Garage tracking with odometer, service intervals, fuel fill-ups, and mileage.
- Expense logging with monthly/all-time filters and CSV export through the iOS share sheet.
- Idle wallpaper gallery with local images and crop/fit preferences.
- Local-first JSON storage plus Keychain-backed dash Wi-Fi credentials.
- A motorcycle-inspired SwiftUI interface that stays native to iOS.

## Open In Xcode

Open `OpenDashiOS.xcodeproj`, select the `OpenDash` scheme, and run on an iPhone simulator or device.

The app uses iOS 17 APIs for SwiftUI Map overlays and PhotosPicker.

## Dash Streaming Note

The Android app's screen-off H.264/RTP dash streaming is intentionally not included here yet. On iOS, continuous locked-screen streaming needs a real hardware proof-of-concept with the Tripper dash before it should be built into the product.
