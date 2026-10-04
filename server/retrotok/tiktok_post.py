"""Posting through TikTok's official Content Posting API (Login Kit OAuth + Direct Post / Upload to inbox).

Needs a TikTok developer app with the Content Posting API product and the scopes user.info.basic,
video.upload and video.publish. Until TikTok audits that app, direct posts can only be private (SELF_ONLY).
"""
import logging
import os
import secrets
import threading
import time
import urllib.parse

import requests

log = logging.getLogger("retrotok.post")

AUTH_URL = "https://www.tiktok.com/v2/auth/authorize/"
API = "https://open.tiktokapis.com"
SCOPES = "user.info.basic,video.upload,video.publish"
MIN_CHUNK = 5 * 1024 * 1024
MAX_CHUNK = 64 * 1024 * 1024
CHUNK = 10 * 1024 * 1024


class PostError(Exception):
    pass


class TikTokPoster:
    def __init__(self, store):
        self.store = store
        self._state = None
        self._lock = threading.Lock()

    # ---- settings / OAuth ----------------------------------------------------------------------
    @property
    def conf(self):
        return self.store.get("tiktok") or {}

    def _save(self, **kw):
        c = dict(self.conf)
        c.update(kw)
        self.store.set("tiktok", c)

    def configure(self, client_key, client_secret, redirect_uri):
        self._save(client_key=client_key.strip(), client_secret=client_secret.strip(),
                   redirect_uri=redirect_uri.strip())

    def configured(self):
        c = self.conf
        return bool(c.get("client_key") and c.get("client_secret") and c.get("redirect_uri"))

    def logged_in(self):
        return bool(self.conf.get("refresh_token"))

    def authorize_url(self):
        if not self.configured():
            raise PostError("Enter the TikTok client key, secret and redirect URI first")
        self._state = secrets.token_urlsafe(16)
        q = {"client_key": self.conf["client_key"], "scope": SCOPES, "response_type": "code",
             "redirect_uri": self.conf["redirect_uri"], "state": self._state}
        return AUTH_URL + "?" + urllib.parse.urlencode(q)

    def finish_login(self, code_or_url):
        """Accepts the code or the whole URL TikTok redirected to."""
        code, state = code_or_url.strip(), None
        if "code=" in code:
            q = urllib.parse.parse_qs(urllib.parse.urlparse(code).query)
            code, state = q.get("code", [""])[0], q.get("state", [None])[0]
            if q.get("error"):
                raise PostError("TikTok said: %s" % q.get("error_description", q["error"])[0])
        if state and self._state and state != self._state:
            raise PostError("The login link is stale - start the login again")
        self._token({"grant_type": "authorization_code", "code": code, "redirect_uri": self.conf["redirect_uri"]})
        self._save(account=self.user_info())

    def logout(self):
        c = dict(self.conf)
        for k in ("access_token", "refresh_token", "expires_at", "open_id", "account"):
            c.pop(k, None)
        self.store.set("tiktok", c)

    def _token(self, params):
        data = {"client_key": self.conf["client_key"], "client_secret": self.conf["client_secret"]}
        data.update(params)
        r = requests.post(API + "/v2/oauth/token/", data=data,
                          headers={"Content-Type": "application/x-www-form-urlencoded"}, timeout=30)
        j = r.json()
        if "access_token" not in j:
            raise PostError("Token request failed: %s" % (j.get("error_description") or j.get("error") or r.text[:200]))
        self._save(access_token=j["access_token"], refresh_token=j.get("refresh_token") or self.conf.get("refresh_token"),
                   expires_at=time.time() + int(j.get("expires_in", 3600)) - 120, open_id=j.get("open_id"),
                   scopes=j.get("scope"))

    def _access_token(self):
        with self._lock:
            c = self.conf
            if not c.get("refresh_token"):
                raise PostError("Not logged in to TikTok - open the server's /admin page on a computer")
            if not c.get("access_token") or time.time() > c.get("expires_at", 0):
                self._token({"grant_type": "refresh_token", "refresh_token": c["refresh_token"]})
            return self.conf["access_token"]

    def _call(self, method, path, json_body=None, params=None):
        r = requests.request(method, API + path, json=json_body, params=params, timeout=60,
                             headers={"Authorization": "Bearer " + self._access_token(),
                                      "Content-Type": "application/json; charset=UTF-8"})
        try:
            j = r.json()
        except ValueError:
            raise PostError("TikTok API %s answered %s" % (path, r.status_code))
        err = j.get("error") or {}
        if err.get("code") not in (None, "ok"):
            raise PostError("%s: %s" % (err.get("code"), err.get("message")))
        return j.get("data") or {}

    def user_info(self):
        d = self._call("GET", "/v2/user/info/", params={"fields": "open_id,display_name,avatar_url"})
        u = d.get("user") or {}
        return {"display_name": u.get("display_name"), "avatar_url": u.get("avatar_url")}

    def creator_info(self):
        return self._call("POST", "/v2/post/publish/creator_info/query/", json_body={})

    # ---- upload --------------------------------------------------------------------------------
    @staticmethod
    def chunk_plan(size):
        if size <= MAX_CHUNK:
            return size, 1
        return CHUNK, size // CHUNK

    def post_video(self, path, caption, mode="direct", privacy="SELF_ONLY", allow_comments=True,
                   allow_duet=True, allow_stitch=True, progress=None):
        size = os.path.getsize(path)
        chunk_size, count = self.chunk_plan(size)
        source = {"source": "FILE_UPLOAD", "video_size": size, "chunk_size": chunk_size, "total_chunk_count": count}
        if mode == "inbox":
            init = self._call("POST", "/v2/post/publish/inbox/video/init/", json_body={"source_info": source})
        else:
            body = {"post_info": {"title": caption[:2200], "privacy_level": privacy,
                                  "disable_comment": not allow_comments, "disable_duet": not allow_duet,
                                  "disable_stitch": not allow_stitch, "video_cover_timestamp_ms": 1000},
                    "source_info": source}
            init = self._call("POST", "/v2/post/publish/video/init/", json_body=body)
        publish_id, upload_url = init["publish_id"], init["upload_url"]
        with open(path, "rb") as f:
            for n in range(count):
                start = n * chunk_size
                length = size - start if n == count - 1 else chunk_size
                f.seek(start)
                data = f.read(length)
                r = requests.put(upload_url, data=data, timeout=300, headers={
                    "Content-Type": "video/mp4", "Content-Length": str(length),
                    "Content-Range": "bytes %d-%d/%d" % (start, start + length - 1, size)})
                if r.status_code not in (200, 201, 206):
                    raise PostError("Chunk %d/%d was refused (%s)" % (n + 1, count, r.status_code))
                if progress:
                    progress((start + length) / size)
        return publish_id

    def status(self, publish_id):
        return self._call("POST", "/v2/post/publish/status/fetch/", json_body={"publish_id": publish_id})
