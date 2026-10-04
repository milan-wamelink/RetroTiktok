"""RetroTok server: the bridge between TikTok and an iOS 6 device. Speaks plain HTTP + JSON to the app."""
import argparse
import logging
import os
import socket
import tempfile
import threading
import time
import uuid

from flask import Flask, abort, jsonify, redirect, request, send_file

from . import __version__
from .media import MediaCache, ffmpeg_for_tiktok, probe_duration
from .store import Store
from .tiktok_post import PostError, TikTokPoster
from .tiktok_source import TikTokError, TikTokSource
from .admin_page import render_admin

log = logging.getLogger("retrotok")

PUBLIC_KEYS = ("id", "desc", "author", "nickname", "duration", "width", "height", "likes", "comments",
               "shares", "plays", "music", "music_author", "create_time")


def create_app(data_dir, profile="hq", access_key=None, cache_gb=2.0):
    os.makedirs(data_dir, exist_ok=True)
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = 1024 * 1024 * 1024
    store = Store(os.path.join(data_dir, "retrotok.json"))
    source = TikTokSource()
    media = MediaCache(source, os.path.join(data_dir, "cache"), profile, int(cache_gb * 1024 ** 3))
    poster = TikTokPoster(store)
    uploads = {}
    upload_dir = os.path.join(data_dir, "uploads")
    os.makedirs(upload_dir, exist_ok=True)

    def public(item):
        out = {k: item.get(k) for k in PUBLIC_KEYS}
        out["liked"] = item["id"] in {i["id"] for i in store.get("likes", [])}
        out["following"] = (item.get("author") or "").lower() in store.get("following", [])
        out["video"] = "/media/video/%s.mp4" % item["id"]
        out["cover"] = "/media/cover/%s.jpg" % item["id"]
        out["avatar"] = "/media/avatar/%s.jpg" % item["author"] if item.get("author") else None
        out["web_url"] = "https://www.tiktok.com/@%s/video/%s" % (item.get("author") or "_", item["id"])
        return out

    def feed(items, prefetch=3):
        media.prefetch([i["id"] for i in items[:prefetch]])
        return jsonify({"items": [public(i) for i in items]})

    @app.before_request
    def check_key():
        if not access_key or request.path in ("/", "/favicon.ico"):
            return None
        given = request.headers.get("X-RetroTok-Key") or request.args.get("key") or request.cookies.get("rtkey")
        if given != access_key:
            abort(401)
        return None

    @app.errorhandler(TikTokError)
    @app.errorhandler(PostError)
    def tiktok_error(e):
        return jsonify({"error": str(e)}), 502

    @app.errorhandler(401)
    def unauthorized(_e):
        return jsonify({"error": "Wrong or missing access key (Settings > Access key)"}), 401

    @app.route("/")
    def index():
        return ("<h1>RetroTok server %s</h1><p>Point the RetroTok app at this address. "
                "TikTok login for posting: <a href='/admin'>/admin</a></p>" % __version__)

    # ---- reading -------------------------------------------------------------------------------
    @app.route("/api/status")
    def status():
        c = poster.conf
        return jsonify({"version": __version__, "profile": profile, "following": store.get("following", []),
                        "tiktok": {"configured": poster.configured(), "logged_in": poster.logged_in(),
                                   "account": c.get("account")}})

    @app.route("/api/feed/foryou")
    def for_you():
        return feed(source.for_you(min(int(request.args.get("count", 12)), 30)))

    @app.route("/api/feed/following")
    def following_feed():
        users = store.get("following", [])
        if not users:
            return jsonify({"items": [], "message": "Follow some creators first (Discover tab)"})
        return feed(source.following_feed(users, min(int(request.args.get("count", 30)), 60)))

    @app.route("/api/user/<name>")
    def user(name):
        name = name.lstrip("@").lower()
        items = source.user_videos(name, min(int(request.args.get("count", 30)), 60),
                                   use_cache=request.args.get("refresh") != "1")
        detail = TikTokSource._safe(source.user_detail, name) or {
            "username": name, "nickname": next((i.get("nickname") for i in items if i.get("nickname")), name)}
        detail.update(avatar="/media/avatar/%s.jpg" % name, following=name in store.get("following", []))
        return jsonify({"user": detail,
                        "items": [public(i) for i in items]})

    @app.route("/api/resolve")
    def resolve():
        q = (request.args.get("q") or "").strip()
        if not q:
            abort(400)
        if "tiktok.com" not in q and not q.isdigit():
            return jsonify({"user": q.lstrip("@").split("/")[0].lower()})
        item = source.resolve(q)
        media.prefetch([item["id"]])
        return jsonify({"item": public(item)})

    @app.route("/api/video/<vid>")
    def video_info(vid):
        item = source.get_item(vid) or source.resolve(vid)
        return jsonify({"item": public(item)})

    @app.route("/api/video/<vid>/comments")
    def comments(vid):
        return jsonify(source.comments(vid, int(request.args.get("cursor", 0)), 20))

    @app.route("/api/prepare/<vid>")
    def prepare(vid):
        media.prepare_video(vid)
        return jsonify({"ready": True, "video": "/media/video/%s.mp4" % vid})

    @app.route("/api/prefetch", methods=["POST"])
    def prefetch():
        ids = [str(i) for i in (request.get_json(silent=True) or {}).get("ids", [])][:5]
        media.prefetch(ids)
        return jsonify({"ok": True})

    # ---- media ---------------------------------------------------------------------------------
    @app.route("/media/video/<vid>.mp4")
    def video(vid):
        return send_file(media.prepare_video(vid), mimetype="video/mp4", conditional=True, max_age=86400)

    @app.route("/media/cover/<vid>.jpg")
    def cover(vid):
        item = source.get_item(vid)
        if not item or not item.get("cover_url"):
            abort(404)
        width = max(64, min(int(request.args.get("w", 320)), 640))
        return send_file(media.image("cover", vid, item["cover_url"], width), mimetype="image/jpeg", max_age=86400)

    @app.route("/media/avatar/<name>.jpg")
    def avatar(name):
        url = source.avatar_url(name)
        if not url:
            abort(404)
        width = max(32, min(int(request.args.get("w", 120)), 300))
        return send_file(media.image("avatar", name.lower(), url, width, square=True), mimetype="image/jpeg",
                         max_age=86400)

    # ---- follows & likes (kept on this server) ------------------------------------------------
    @app.route("/api/following", methods=["GET"])
    def following_list():
        return jsonify({"following": store.get("following", [])})

    @app.route("/api/following/<name>", methods=["POST", "DELETE"])
    def follow(name):
        name = name.lstrip("@").lower()
        users = [u for u in store.get("following", []) if u != name]
        if request.method == "POST":
            users.insert(0, name)
        store.set("following", users)
        return jsonify({"following": users})

    @app.route("/api/likes", methods=["GET"])
    def likes():
        return jsonify({"items": [public(i) for i in store.get("likes", [])]})

    @app.route("/api/likes/<vid>", methods=["POST", "DELETE"])
    def like(vid):
        liked = [i for i in store.get("likes", []) if i["id"] != vid]
        if request.method == "POST":
            item = source.get_item(vid)
            if item:
                liked.insert(0, {k: item.get(k) for k in PUBLIC_KEYS + ("cover_url", "avatar_url")})
        store.set("likes", liked)
        return jsonify({"liked": request.method == "POST"})

    # ---- posting -------------------------------------------------------------------------------
    @app.route("/api/creator_info")
    def creator_info():
        return jsonify(poster.creator_info())

    @app.route("/api/upload", methods=["POST"])
    def upload():
        if not poster.logged_in():
            return jsonify({"error": "The server is not logged in to TikTok yet - open http://<server>/admin"}), 400
        job_id = uuid.uuid4().hex[:12]
        raw = os.path.join(upload_dir, job_id + ".mov")
        with open(raw, "wb") as f:
            while True:
                chunk = request.stream.read(1024 * 1024)
                if not chunk:
                    break
                f.write(chunk)
        if os.path.getsize(raw) < 1000:
            os.remove(raw)
            return jsonify({"error": "The video did not arrive"}), 400
        a = request.args
        job = {"id": job_id, "state": "processing", "progress": 0.0, "message": "Preparing video",
               "publish_id": None, "created": time.time()}
        uploads[job_id] = job
        opts = {"caption": a.get("caption", ""), "mode": a.get("mode", "direct"),
                "privacy": a.get("privacy", "SELF_ONLY"), "allow_comments": a.get("comments", "1") == "1",
                "allow_duet": a.get("duet", "1") == "1", "allow_stitch": a.get("stitch", "1") == "1"}
        threading.Thread(target=run_upload, args=(job, raw, opts), daemon=True).start()
        return jsonify(job)

    def run_upload(job, raw, opts):
        mp4 = raw[:-4] + ".mp4"
        try:
            ffmpeg_for_tiktok(raw, mp4)
            if probe_duration(mp4) < 3:
                raise PostError("TikTok needs videos of at least 3 seconds")
            job.update(state="uploading", message="Sending to TikTok")
            job["publish_id"] = poster.post_video(mp4, progress=lambda p: job.update(progress=p), **opts)
            job.update(state="sent", progress=1.0, message="TikTok is processing the video")
        except Exception as e:  # noqa: BLE001
            log.exception("upload %s failed", job["id"])
            job.update(state="failed", message=str(e))
        finally:
            for p in (raw, mp4):
                if os.path.exists(p):
                    os.remove(p)

    @app.route("/api/upload/<job_id>")
    def upload_status(job_id):
        job = uploads.get(job_id)
        if not job:
            abort(404)
        if job["state"] == "sent" and job.get("publish_id"):
            try:
                st = poster.status(job["publish_id"])
                s = st.get("status")
                if s == "PUBLISH_COMPLETE":
                    job.update(state="published", message="Posted to TikTok")
                elif s == "SEND_TO_USER_INBOX":
                    job.update(state="published", message="Sent to your TikTok inbox - finish posting in TikTok")
                elif s == "FAILED":
                    job.update(state="failed", message="TikTok rejected it: %s" % st.get("fail_reason"))
            except PostError as e:
                job["message"] = "Checking status: %s" % e
        return jsonify(job)

    # ---- admin (TikTok developer keys + login), use from a computer browser -------------------
    @app.route("/admin", methods=["GET"])
    def admin():
        resp = app.make_response(render_admin(poster, request.args.get("msg"), access_key))
        if access_key and request.args.get("key") == access_key:
            resp.set_cookie("rtkey", access_key, httponly=True, samesite="Lax")
        return resp

    @app.route("/admin/keys", methods=["POST"])
    def admin_keys():
        f = request.form
        poster.configure(f.get("client_key", ""), f.get("client_secret", "") or poster.conf.get("client_secret", ""),
                         f.get("redirect_uri", ""))
        return redirect("/admin?msg=Saved")

    @app.route("/admin/login")
    def admin_login():
        return redirect(poster.authorize_url())

    @app.route("/admin/code", methods=["POST"])
    def admin_code():
        try:
            poster.finish_login(request.form.get("code", ""))
            return redirect("/admin?msg=Logged+in")
        except PostError as e:
            return redirect("/admin?msg=" + str(e))

    @app.route("/admin/callback")
    def admin_callback():
        try:
            poster.finish_login(request.url)
            return redirect("/admin?msg=Logged+in")
        except PostError as e:
            return redirect("/admin?msg=" + str(e))

    @app.route("/admin/logout", methods=["POST"])
    def admin_logout():
        poster.logout()
        return redirect("/admin?msg=Logged+out")

    app.media = media
    app.source = source
    return app


def lan_addresses():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        ip = s.getsockname()[0]
        s.close()
        return [ip]
    except OSError:
        return []


def main():
    ap = argparse.ArgumentParser(description="RetroTok server - TikTok bridge for iOS 6")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=int(os.environ.get("RETROTOK_PORT", 8460)))
    ap.add_argument("--data", default=os.environ.get("RETROTOK_DATA", os.path.join(os.getcwd(), "data")))
    ap.add_argument("--profile", choices=["compat", "hq"], default=os.environ.get("RETROTOK_PROFILE", "hq"),
                    help="compat: H.264 Baseline 432x768 (every iOS 6 device); hq: Main 540x960 (iPhone 4 and newer)")
    ap.add_argument("--key", default=os.environ.get("RETROTOK_KEY"), help="optional access key the app must send")
    ap.add_argument("--cache-gb", type=float, default=float(os.environ.get("RETROTOK_CACHE_GB", 2)))
    a = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    app = create_app(a.data, a.profile, a.key, a.cache_gb)
    for ip in lan_addresses():
        log.info("RetroTok server on http://%s:%d  (enter this in the app's Settings)", ip, a.port)
    try:
        from waitress import serve
        serve(app, host=a.host, port=a.port, threads=16, channel_timeout=900)
    except ImportError:
        app.run(host=a.host, port=a.port, threaded=True)


if __name__ == "__main__":
    main()
