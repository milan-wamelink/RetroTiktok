# RetroTok - TikTok for iOS 6

A retro TikTok viewer for jailbroken iOS 6 (armv7, built for the iPhone 4S, runs on any iOS 6 device). It's a native
Objective-C app in the iOS 6 style: glossy black bars, a linen background and code-drawn icons. The app shows a
full-screen **For You** feed: swipe up for the next video, videos loop, tap to pause, and covers show as thumbnails
while a video loads.

Not affiliated with TikTok or ByteDance. It only shows public content. No login is needed.

## How it works

```
iPhone (iOS 6)  --plain HTTP/JSON-->  RetroTok server (your PC / Raspberry Pi)  --modern TLS-->  TikTok
```

iOS 6 can't talk to TikTok itself. Its TLS is too old, TikTok only answers clients that look like a current Chrome,
and many TikTok videos use codecs (H.265) that iOS 6 can't decode. The **server** does that part:

- It loads the For You / Explore feed, creator videos and comments through `curl_cffi` (with Chrome impersonation)
  and `yt-dlp`.
- It converts every video with ffmpeg into an MP4 iOS 6 can play: H.264 + AAC, with `faststart`.
  - `hq` (the default): Main 3.1, 540x960. For the iPhone 4/4S/5 and iPads.
  - `compat`: Baseline 3.0, 432x768. For every iOS 6 device, including the 3GS.
- It prepares the next videos ahead of time, and caches covers and avatars as small JPEGs.

When TikTok changes something, update `yt-dlp` / `curl_cffi` on the server. The app does not need rebuilding.

## 1. Run the server

Needs Python 3.9+ and ffmpeg.

```sh
cd server
pip install -r requirements.txt
python3 -m retrotok                 # port 8460; prints the LAN address to enter in the app
python3 -m retrotok --profile compat --key mysecret   # optional: Baseline video, require an access key
```

Settings can also come from the environment: `RETROTOK_PORT`, `RETROTOK_DATA`, `RETROTOK_PROFILE`, `RETROTOK_KEY`
and `RETROTOK_CACHE_GB` (the video cache size, 2 GB by default).

## 2. Install the app

Download `nl.retrotok.app_*.deb` (from the CI artifacts, or build it yourself, see below) and copy it to the phone:

```sh
scp nl.retrotok.app_0.1.0_iphoneos-arm.deb root@<iphone-ip>:/tmp/
ssh root@<iphone-ip> "dpkg -i /tmp/nl.retrotok.app_0.1.0_iphoneos-arm.deb && su mobile -c uicache"
```

Or open the .deb with iFile and tap Install. Then open RetroTok, go to **Settings**, and enter the server
address (e.g. `192.168.1.20`; the port 8460 is added for you).

## Build the app yourself

The app uses [Theos](https://theos.dev) with the iOS 9.3 SDK, deployment target 6.0, armv7, and ARC. It also
builds on Linux.

```sh
export THEOS=~/theos            # with toolchain/linux/iphone and sdks/iPhoneOS9.3.sdk
cd ios
python3 tools/gen_assets.py     # icon + launch images (Pillow)
make package FINALPACKAGE=1     # -> ios/packages/*.deb
```

The app uses only frameworks that exist on iOS 6: UIKit, Foundation, CoreGraphics, QuartzCore, AVFoundation and
CoreMedia. `-Wunguarded-availability` is an error for app code, so any API newer than iOS 6.0 fails the build.
GitHub Actions (`.github/workflows/build.yml`) builds the .deb and an .ipa on every push.

## Roadmap

| version | what | status |
|---------|------|--------|
| V1 | For You feed, vertical swiping, playback, thumbnails, settings | **this version** |
| V2 | creator profiles, comments | server endpoints ready |
| V3 | likes / favorites | server endpoints ready (stored on your server) |
| V4 | search | |
| V5 | login | |
| V6 | uploads | server side via the official TikTok Content Posting API (needs a TikTok developer app) |

## Server API (for the app)

| path | returns |
|------|---------|
| `GET /api/status` | version, video profile |
| `GET /api/feed/foryou` | `{items:[{id, author, nickname, desc, cover, avatar, video, likes, comments, shares, plays, music, ...}]}` |
| `GET /api/prepare/<id>` | waits until the iOS 6 MP4 exists: `{ready, video}` |
| `POST /api/prefetch` | `{ids:[...]}`, converts these in the background |
| `GET /media/video/<id>.mp4` | the converted video (Range supported) |
| `GET /media/cover/<id>.jpg`, `/media/avatar/<user>.jpg` | thumbnails |
| `GET /api/user/<name>`, `/api/video/<id>/comments` | profile + videos, comments (V2) |
| `/api/likes`, `/api/following` | local likes / follows (V3) |
