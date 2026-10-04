# RetroTok server - OPTIONAL fallback

**Not needed for LegacyTikTok V1.** The app in `../ios` talks to TikTok directly. Nothing in the app build or the
.deb depends on this folder. It is kept as an optional fallback in case TikTok ever closes the direct route. The app
has no switch to use it yet; one can be added behind `RTFeedSource` (`ios/src/RTFeedSource.h`).

## How it works (server mode)

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

## Run the server

Needs Python 3.9+ and ffmpeg.

```sh
cd server
pip install -r requirements.txt
python3 -m retrotok                 # port 8460; prints the LAN address to enter in the app
python3 -m retrotok --profile compat --key mysecret   # optional: Baseline video, require an access key
```

Settings can also come from the environment: `RETROTOK_PORT`, `RETROTOK_DATA`, `RETROTOK_PROFILE`, `RETROTOK_KEY`
and `RETROTOK_CACHE_GB` (the video cache size, 2 GB by default).

## Server API

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
