# LegacyTikTok - a standalone TikTok client for iOS 6

A retro TikTok viewer for jailbroken iOS 6 (armv7, built for the iPhone 4S on iOS 6.1.3). It's a native Objective-C
app in the iOS 6 style that **talks to TikTok directly**. There is no proxy, server or computer involved.

Not affiliated with TikTok or ByteDance. It only shows public content. No login is needed.

> **Status: V3 (0.5.0) in testing.** V1 (0.3.1: swipeable direct For You feed, cached playback, prefetch, size-capped
> cache) and V2 (0.4.0: **creator profiles** and **comments**) run on a real iPhone 4S / iOS 6.1.3. V3 adds local
> **favorites**: the heart saves a video's details on the phone (not the video), listed under the **Favorites** tab;
> playing one fetches fresh links from TikTok and downloads it again. The pipeline test is under **Settings > Pipeline Test**.

## How it works

```
iPhone 4S (iOS 6.1.3)
  -> mbedTLS (bundled, TLS 1.2) with bundled root certificates (Resources/roots.pem)
  -> https://api19-core-c-useast1a.tiktokv.com/aweme/v1/feed/   (legacy mobile app API: no login, cookies or signature)
  -> JSON parsed on the phone -> H.264 rendition picked (<= 576 wide, no HEVC), JPEG covers
  -> MP4 downloaded straight from TikTok's CDN (v16m.tiktokcdn.com first) into the cache folder
  -> AVPlayer plays the local file and loops it

V2, same TLS stack, still no server:
  -> https://www.tiktok.com/api/creator/item_list/?secUid=...   (profile header + that creator's videos, 12 per page)
  -> https://www.tiktok.com/api/comment/list/?aweme_id=...      (20 comments per page)
  -> profile videos come from v16-webapp-prime, which needs "Referer: https://www.tiktok.com/" (sent on every download)
```

- **Why web endpoints for V2:** the aweme endpoints for profiles, profile videos and comments now need request
  signatures (they answer empty or 404 without one). TikTok's public web JSON endpoints above need no signature,
  login or cookies, and are just as direct. The V1 feed stays on aweme.

- **Why mbedTLS:** TikTok's certificates chain to DigiCert Global Root G2 (API) and G3 (CDN). Those roots are newer
  than iOS 6, so the system TLS stack rejects them. The app bundles mbedTLS 3.6 and its own root list instead. It
  verifies the certificate chain and host name itself, and falls back to nothing insecure.
- **Why a cache file:** AVPlayer can only use the system TLS stack. So each video is downloaded through mbedTLS first,
  then played from disk.
- **Empty answers:** about half of TikTok's feed answers have an empty body. The app retries up to 6 times.
- **Layers:** `rt_http.c` (plain C: HTTP/1.1 over mbedTLS, redirects, chunked encoding, streaming to file) ->
  `RTHTTPClient` (Objective-C, gzip) -> `RTAwemeAPI` (the only TikTok-specific code, behind the `RTFeedSource`
  protocol) -> `RTVideoCache` -> UI. If the endpoint changes, only `RTAwemeAPI` needs replacing.
- **Risk:** this is TikTok's unofficial legacy app API, and TikTok can change or close it at any time.

The old server-based version lives in [`server/`](server/README.md) as an **optional fallback**. The app does not
need it, and neither the build nor the .deb depends on it.

## Install (Cydia / dpkg)

Get `nl.retrotok.legacytiktok_*_iphoneos-arm.deb` from the CI artifacts (`LegacyTikTok-packages`), or build it
yourself (see below).

```sh
scp nl.retrotok.legacytiktok_0.5.0_iphoneos-arm.deb root@<iphone-ip>:/tmp/
ssh root@<iphone-ip> dpkg -i /tmp/nl.retrotok.legacytiktok_0.5.0_iphoneos-arm.deb
```

Or open the .deb in iFile and tap Install. The package:
- installs only `/Applications/LegacyTikTok.app` (binary, Info.plist, icons, launch images, `roots.pem`);
- depends only on `firmware (>= 6.0)`;
- runs `uicache` after install/remove, so the icon appears and disappears without a respring;
- on removal (`dpkg -r nl.retrotok.legacytiktok` or Cydia), also deletes what the app created:
  `/var/mobile/Library/Caches/nl.retrotok.legacytiktok` (downloaded videos, capped at 25 MB by default, adjustable in Settings) and
  `/var/mobile/Library/Preferences/nl.retrotok.legacytiktok.plist`.

An `.ipa` of the same app is also built, for testing.

### Pipeline test

Open **Settings > Pipeline Test**. It runs automatically; tap **Run** to repeat. Steps 1-6 are the V1 pipeline;
steps 7 and 8 load the picked video's profile videos and comments. When it finishes (or fails), tap
**Copy Log** and paste the log into a message. It shows which step failed, the TLS version and cipher, and the
download speed.

## Build the app yourself

The app uses [Theos](https://theos.dev) with the iOS 9.3 SDK, deployment target 6.0, armv7, and ARC. It also
builds on Linux.

```sh
export THEOS=~/theos            # with toolchain/linux/iphone and sdks/iPhoneOS9.3.sdk
cd ios
python3 tools/gen_assets.py     # icon + launch images (Pillow)
./tools/fetch_mbedtls.sh        # mbedTLS 3.6.7 -> vendor/mbedtls with the iOS 6 config (make also does this)
make package FINALPACKAGE=1     # -> ios/packages/*.deb
```

`tools/http_test.sh` builds the same network core (`src/rt_http.c` + mbedTLS) as a desktop command-line tool. Use
it to test TikTok's endpoints from a computer with exactly the TLS the phone uses:
`obj/http_test/http_test Resources/roots.pem <url> out.bin "User-Agent: ..."`.

The app links only iOS 6 frameworks: UIKit, Foundation, CoreGraphics, QuartzCore, AVFoundation, CoreMedia,
Security (for `SecRandomCopyBytes`), plus libz. `-Wunguarded-availability` catches app code that uses an API newer
than iOS 6.0, and mbedTLS uses `gettimeofday` instead of `clock_gettime`, which needs iOS 10.
GitHub Actions (`.github/workflows/build.yml`) builds the .deb and an .ipa on every push.

## Roadmap

| version | what | status |
|---------|------|--------|
| V1 | direct For You feed, vertical swiping, cached playback, prefetch, thumbnails | done (0.3.1, tested on a 4S) |
| V2 | creator profiles, comments | 0.4.0 |
| V3 | local favorites (saved on the phone; real likes need a login) | **0.5.0 in testing** |
| V4 | search | |
| V5 | login | |
| V6 | uploads | |
