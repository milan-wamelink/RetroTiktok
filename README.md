# LegacyTikTok - a standalone TikTok client for iOS 6

A retro TikTok viewer for jailbroken iOS 6 (armv7, built for the iPhone 4S on iOS 6.1.3). It's a native Objective-C
app in the iOS 6 style that **talks to TikTok directly**. There is no proxy, server or computer involved.

Not affiliated with TikTok or ByteDance. It only shows public content. No login is needed.

> **Status: V1 milestone 1.** The app currently opens a **V1 Test** screen that runs the whole direct pipeline once
> and logs every step: mbedTLS handshake, aweme feed request, JSON parse, one video URL, download to the local cache,
> then looping AVPlayer playback. The swipeable 12-video feed with prefetching comes once this works on a real 4S.

## How it works

```
iPhone 4S (iOS 6.1.3)
  -> mbedTLS (bundled, TLS 1.2) with bundled root certificates (Resources/roots.pem)
  -> https://api19-core-c-useast1a.tiktokv.com/aweme/v1/feed/   (legacy mobile app API: no login, cookies or signature)
  -> JSON parsed on the phone -> H.264 rendition picked (<= 576 wide, no HEVC), JPEG covers
  -> MP4 downloaded straight from TikTok's CDN (v16m.tiktokcdn.com first) into the cache folder
  -> AVPlayer plays the local file and loops it
```

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
scp nl.retrotok.legacytiktok_0.2.0_iphoneos-arm.deb root@<iphone-ip>:/tmp/
ssh root@<iphone-ip> dpkg -i /tmp/nl.retrotok.legacytiktok_0.2.0_iphoneos-arm.deb
```

Or open the .deb in iFile and tap Install. The package:
- installs only `/Applications/LegacyTikTok.app` (binary, Info.plist, icons, launch images, `roots.pem`);
- depends only on `firmware (>= 6.0)`;
- runs `uicache` after install/remove, so the icon appears and disappears without a respring;
- on removal (`dpkg -r nl.retrotok.legacytiktok` or Cydia), also deletes what the app created:
  `/var/mobile/Library/Caches/nl.retrotok.legacytiktok` (downloaded videos, at most 24 kept) and
  `/var/mobile/Library/Preferences/nl.retrotok.legacytiktok.plist`.

An `.ipa` of the same app is also built, for testing.

### Reporting the milestone 1 test

Open LegacyTikTok. The **Test** tab runs automatically; tap **Run** to repeat. When it finishes (or fails), tap
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
| V1 | direct For You feed, vertical swiping, cached playback, prefetch, thumbnails | **milestone 1 (pipeline test) in progress** |
| V2 | creator profiles, comments | |
| V3 | likes / favorites | |
| V4 | search | |
| V5 | login | |
| V6 | uploads | |
