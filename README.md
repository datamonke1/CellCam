# BlobCam — hourly blob-growth timelapse (iPhone)

Takes a photo every hour (zoom + flash set in the app) and stores it, to track
cell growth for a school project.

## ⚠️ The one rule

**The iPhone must stay unlocked, plugged into power, with this app in the
foreground.** iOS prohibits camera use in the background
(`videoDeviceNotAvailableInBackground`) — locking the phone stops capture.
There is no API/workaround for locked capture; use *Settings → Display &
Brightness → Auto-Lock → Never* and *Guided Access* during a run.

## Build route: Linux-only (GitHub Actions + SideStore)

No Mac available, so:

1. **Build (cloud Mac):** push to GitHub → the `Build unsigned IPA` workflow
   (`.github/workflows/build-ipa.yml`) compiles the app on a macOS runner and
   uploads `BlobCam-unsigned.ipa` as a workflow artifact. Download it.
2. **Sign + install (Linux):** install [SideStore](https://docs.sidestore.io/docs/installation/install)
   once from Linux (`iloader`), then open the downloaded `.ipa` in SideStore
   and sign it with your free Apple ID. (AltServer-Linux also works.)
3. **On the iPhone:** trust the developer profile
   (*Settings → General → VPN & Device Management*), enable Developer Mode if
   asked, open BlobCam, allow camera/photos, frame the sample, set zoom/flash,
   pick **60 min**, tap **Start timelapse** (a first photo is taken immediately
   so you can verify framing/flash).

**Free-signing limit:** the app expires after 7 days. For longer runs, refresh
it in SideStore weekly (briefly interrupting the timelapse), or re-install.
Plan experiments in ≤7-day blocks if possible.

Photos are saved both in the app's `Documents/CellCam` folder
(`cell-yyyyMMdd-HHmmss.jpg`) and in the Photos library. The folder and bundle
ID kept their old internal names when the app was renamed to BlobCam, so
updating the app keeps all existing photos and saved settings.

## Project layout

- `Sources/BlobCam/` — SwiftUI + AVFoundation app (`CameraService`,
  `ContentView`, `CameraPreview`)
- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) project spec
  (CI generates the `.xcodeproj`; there is intentionally no checked-in project)
- `.github/workflows/build-ipa.yml` — unsigned IPA build
