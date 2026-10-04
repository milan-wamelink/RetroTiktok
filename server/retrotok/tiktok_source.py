"""Reads TikTok without logging in: the explore feed and comments through TikTok's web API (with a
browser-like TLS fingerprint from curl_cffi), creators' videos and single videos through yt-dlp."""
import logging
import random
import threading
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor

import json
import re

import yt_dlp
from curl_cffi import requests as creq
from yt_dlp.networking.impersonate import ImpersonateTarget

log = logging.getLogger("retrotok.tiktok")

WEB = "https://www.tiktok.com"
EXPLORE_CATEGORIES = list(range(100, 121))
PLAY_URL_TTL = 45 * 60
USER_TTL = 20 * 60


def _ydl_opts(**kw):
    # TikTok refuses the default Python TLS fingerprint, so yt-dlp has to go through curl_cffi as well.
    opts = {"quiet": True, "no_warnings": True, "impersonate": ImpersonateTarget.from_str("chrome")}
    opts.update(kw)
    return opts


class TikTokError(Exception):
    pass


def _int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0


class TikTokSource:
    def __init__(self):
        self._session = None
        self._session_time = 0
        self._session_lock = threading.Lock()
        self._items = {}
        self._items_lock = threading.Lock()
        self._avatars = {}
        self._recent = deque(maxlen=400)
        self._user_cache = {}
        self._pool = ThreadPoolExecutor(max_workers=6)

    # ---- web API -------------------------------------------------------------------------------
    def _get_session(self, fresh=False):
        with self._session_lock:
            if fresh or self._session is None or time.time() - self._session_time > 30 * 60:
                s = creq.Session(impersonate="chrome")
                s.get(WEB + "/explore", timeout=30)
                self._session, self._session_time = s, time.time()
            return self._session

    def _api(self, path, params, referer=WEB + "/explore"):
        query = {"aid": 1988}
        query.update(params)
        for attempt in range(2):
            s = self._get_session(fresh=attempt > 0)
            r = s.get(WEB + path, params=query, headers={"Referer": referer}, timeout=30)
            if r.status_code == 200 and r.text.strip():
                try:
                    return r.json()
                except ValueError:
                    pass
            log.warning("empty/invalid answer from %s (attempt %d)", path, attempt + 1)
        raise TikTokError("TikTok did not answer %s" % path)

    # ---- item cache ----------------------------------------------------------------------------
    def _remember(self, item):
        with self._items_lock:
            old = self._items.get(item["id"])
            if old:
                for k, v in old.items():
                    if not item.get(k) and v:
                        item[k] = v
            self._items[item["id"]] = item
        if item.get("author") and item.get("avatar_url"):
            self._avatars[item["author"].lower()] = item["avatar_url"]
        return item

    def get_item(self, vid):
        with self._items_lock:
            return self._items.get(str(vid))

    def avatar_url(self, username):
        return self._avatars.get((username or "").lower())

    def _from_struct(self, i):
        v = i.get("video") or {}
        a = i.get("author") or {}
        st = i.get("stats") or {}
        st2 = i.get("statsV2") or {}
        m = i.get("music") or {}
        return self._remember({
            "id": str(i.get("id")),
            "desc": i.get("desc") or "",
            "author": a.get("uniqueId") or "",
            "nickname": a.get("nickname") or "",
            "avatar_url": a.get("avatarMedium") or a.get("avatarThumb"),
            "cover_url": v.get("cover") or v.get("originCover"),
            "play_url": v.get("playAddr") or v.get("downloadAddr"),
            "fetched": time.time(),
            "duration": _int(v.get("duration")),
            "width": _int(v.get("width")),
            "height": _int(v.get("height")),
            "likes": _int(st2.get("diggCount") or st.get("diggCount")),
            "comments": _int(st2.get("commentCount") or st.get("commentCount")),
            "shares": _int(st2.get("shareCount") or st.get("shareCount")),
            "plays": _int(st2.get("playCount") or st.get("playCount")),
            "music": m.get("title") or "",
            "music_author": m.get("authorName") or "",
            "create_time": _int(i.get("createTime")),
        })

    def _from_ytdlp(self, e):
        thumbs = e.get("thumbnails") or []
        cover = None
        for t in thumbs:
            if t.get("id") in ("cover", "originCover") and t.get("url"):
                cover = t["url"]
                break
        if not cover:
            cover = e.get("thumbnail") or (thumbs[0]["url"] if thumbs else None)
        author = e.get("uploader") or ""
        return self._remember({
            "id": str(e.get("id")),
            "desc": e.get("description") or e.get("title") or "",
            "author": author,
            "nickname": e.get("channel") or author,
            "avatar_url": self._avatars.get(author.lower()),
            "cover_url": cover,
            "play_url": None,
            "fetched": time.time(),
            "duration": _int(e.get("duration")),
            "width": _int(e.get("width")),
            "height": _int(e.get("height")),
            "likes": _int(e.get("like_count")),
            "comments": _int(e.get("comment_count")),
            "shares": _int(e.get("repost_count")),
            "plays": _int(e.get("view_count")),
            "music": e.get("track") or "",
            "music_author": ", ".join(e.get("artists") or []),
            "create_time": _int(e.get("timestamp")),
        })

    # ---- feeds ---------------------------------------------------------------------------------
    def _explore(self, category, count=10):
        data = self._api("/api/explore/item_list/", {"count": count, "categoryType": category,
                                                       "app_language": "en", "device_platform": "web_pc"})
        return [self._from_struct(i) for i in (data.get("itemList") or []) if i.get("id")]

    def for_you(self, count=12):
        """A trending mix from several explore categories, skipping videos served recently."""
        cats = random.sample(EXPLORE_CATEGORIES, 3)
        out, seen = [], set()
        for result in self._pool.map(lambda c: self._safe(self._explore, c), cats):
            for it in result or []:
                if it["id"] in seen or it["id"] in self._recent:
                    continue
                seen.add(it["id"])
                out.append(it)
        if not out:
            # everything was recent: serve repeats rather than nothing
            for c in cats[:1]:
                out = self._safe(self._explore, c) or []
        random.shuffle(out)
        out = out[:count]
        self._recent.extend(i["id"] for i in out)
        return out

    def user_videos(self, username, count=30, use_cache=True):
        key = username.lower().lstrip("@")
        cached = self._user_cache.get(key)
        if use_cache and cached and time.time() - cached[0] < USER_TTL and len(cached[1]) >= min(count, cached[2]):
            return cached[1][:count]
        opts = _ydl_opts(extract_flat=True, playlistend=count, skip_download=True)
        with yt_dlp.YoutubeDL(opts) as ydl:
            try:
                info = ydl.extract_info("%s/@%s" % (WEB, key), download=False)
            except yt_dlp.utils.DownloadError as e:
                raise TikTokError("Could not load @%s: %s" % (key, str(e).split(": ")[-1]))
        items = [self._from_ytdlp(e) for e in (info.get("entries") or []) if e and e.get("id")]
        for it in items:
            if not it["author"]:
                it["author"] = key
        self._user_cache[key] = (time.time(), items, count)
        return items

    def user_detail(self, username):
        """Nickname, avatar and counters from the profile page (no signed API needed)."""
        key = username.lower().lstrip("@")
        r = self._get_session().get("%s/@%s" % (WEB, key), timeout=30)
        m = re.search(r'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>', r.text, re.S)
        if not m:
            raise TikTokError("Could not read the profile of @%s" % key)
        ud = json.loads(m.group(1)).get("__DEFAULT_SCOPE__", {}).get("webapp.user-detail", {})
        info = ud.get("userInfo") or {}
        u, st = info.get("user") or {}, info.get("stats") or {}
        if not u:
            raise TikTokError("@%s was not found" % key)
        avatar = u.get("avatarMedium") or u.get("avatarThumb")
        if avatar:
            self._avatars[key] = avatar
        return {"username": u.get("uniqueId") or key, "nickname": u.get("nickname") or key,
                "bio": u.get("signature") or "", "verified": bool(u.get("verified")),
                "followers": _int(st.get("followerCount")), "following_count": _int(st.get("followingCount")),
                "hearts": _int(st.get("heartCount") or st.get("heart")), "videos": _int(st.get("videoCount"))}

    def following_feed(self, usernames, count=30):
        per_user = max(4, min(10, 40 // max(1, len(usernames))))
        results = self._pool.map(lambda u: self._safe(self.user_videos, u, per_user), usernames)
        merged = [it for r in results for it in (r or [])]
        merged.sort(key=lambda it: it.get("create_time") or 0, reverse=True)
        return merged[:count]

    def resolve(self, url_or_id):
        """Full metadata for one video (a link or an ID)."""
        url = url_or_id
        if url_or_id.isdigit():
            known = self.get_item(url_or_id)
            url = "%s/@%s/video/%s" % (WEB, (known or {}).get("author") or "_", url_or_id)
        opts = _ydl_opts(skip_download=True)
        with yt_dlp.YoutubeDL(opts) as ydl:
            try:
                info = ydl.extract_info(url, download=False)
            except yt_dlp.utils.DownloadError as e:
                raise TikTokError("Could not load that video: %s" % str(e).split(": ")[-1])
        return self._from_ytdlp(info)

    def comments(self, vid, cursor=0, count=20):
        it = self.get_item(vid) or {}
        ref = "%s/@%s/video/%s" % (WEB, it.get("author") or "_", vid)
        data = self._api("/api/comment/list/", {"aweme_id": vid, "count": count, "cursor": cursor}, referer=ref)
        out = []
        for c in data.get("comments") or []:
            u = c.get("user") or {}
            avatar = ((u.get("avatar_thumb") or {}).get("url_list") or [None])[0]
            name = u.get("unique_id") or ""
            if name and avatar:
                self._avatars.setdefault(name.lower(), avatar)
            out.append({
                "id": str(c.get("cid")),
                "author": name,
                "nickname": u.get("nickname") or name,
                "text": c.get("text") or "",
                "likes": _int(c.get("digg_count")),
                "replies": _int(c.get("reply_comment_total")),
                "create_time": _int(c.get("create_time")),
            })
        return {"comments": out, "cursor": _int(data.get("cursor")), "has_more": bool(data.get("has_more")),
                "total": _int(data.get("total"))}

    # ---- downloads -----------------------------------------------------------------------------
    def fetch_bytes(self, url, timeout=30):
        r = self._get_session().get(url, headers={"Referer": WEB + "/"}, timeout=timeout)
        if r.status_code != 200 or not r.content:
            raise TikTokError("download failed (%s)" % r.status_code)
        return r.content

    def download_video(self, vid, dest_base):
        """Downloads the original video, returns the file path."""
        it = self.get_item(vid)
        if it and it.get("play_url") and time.time() - it.get("fetched", 0) < PLAY_URL_TTL:
            try:
                data = self.fetch_bytes(it["play_url"], timeout=120)
                if len(data) > 10000 and data[4:8] == b"ftyp":
                    path = dest_base + ".src.mp4"
                    with open(path, "wb") as f:
                        f.write(data)
                    return path
            except Exception as e:  # noqa: BLE001 - fall back to yt-dlp
                log.info("direct download of %s failed (%s), trying yt-dlp", vid, e)
        url = "%s/@%s/video/%s" % (WEB, (it or {}).get("author") or "_", vid)
        opts = _ydl_opts(noprogress=True, format="best[vcodec^=h264]/best", outtmpl=dest_base + ".src.%(ext)s")
        with yt_dlp.YoutubeDL(opts) as ydl:
            try:
                info = ydl.extract_info(url, download=True)
            except yt_dlp.utils.DownloadError as e:
                raise TikTokError("Could not download %s: %s" % (vid, str(e).split(": ")[-1]))
            self._from_ytdlp(info)
            return ydl.prepare_filename(info)

    @staticmethod
    def _safe(fn, *args):
        try:
            return fn(*args)
        except Exception as e:  # noqa: BLE001
            log.warning("%s%r failed: %s", fn.__name__, args, e)
            return None
