"""Turns TikTok videos and pictures into what an iOS 6 device can show: H.264 Baseline + AAC-LC MP4
with the index at the front, and small baseline JPEGs."""
import io
import logging
import os
import subprocess
import threading
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

log = logging.getLogger("retrotok.media")

# Baseline 3.0 plays on every iOS 6 device (iPhone 3GS and up); 432x768 at 30 fps fits that level.
# "hq" is Main 3.1 at 540x960 for the iPhone 4 / 4S / 5 and iPads.
PROFILES = {
    "compat": {"w": 432, "h": 768, "profile": "baseline", "level": "3.0", "maxrate": "1100k", "crf": "26"},
    "hq": {"w": 540, "h": 960, "profile": "main", "level": "3.1", "maxrate": "1800k", "crf": "24"},
}


def ffmpeg_ios6(src, dst, profile="compat"):
    p = PROFILES.get(profile, PROFILES["compat"])
    vf = ("scale=w=%d:h=%d:force_original_aspect_ratio=decrease,"
          "scale=trunc(iw/2)*2:trunc(ih/2)*2,fps=30,format=yuv420p" % (p["w"], p["h"]))
    tmp = dst + ".part.mp4"
    cmd = ["ffmpeg", "-y", "-v", "error", "-i", src, "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn",
           "-vf", vf, "-c:v", "libx264", "-preset", "veryfast", "-profile:v", p["profile"], "-level", p["level"],
           "-crf", p["crf"], "-maxrate", p["maxrate"], "-bufsize", "2M", "-g", "60",
           "-c:a", "aac", "-profile:a", "aac_low", "-ac", "2", "-ar", "44100", "-b:a", "96k",
           "-movflags", "+faststart", "-map_metadata", "-1", tmp]
    subprocess.run(cmd, check=True, timeout=600)
    os.replace(tmp, dst)


def ffmpeg_for_tiktok(src, dst):
    """Upload side: iPhone .mov (H.264/AAC, sometimes rotated) -> clean MP4 that TikTok accepts."""
    tmp = dst + ".part.mp4"
    try:
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", src, "-map", "0:v:0", "-map", "0:a:0?",
                        "-c", "copy", "-movflags", "+faststart", tmp], check=True, timeout=600)
    except subprocess.CalledProcessError:
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", src, "-map", "0:v:0", "-map", "0:a:0?",
                        "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
                        "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", tmp], check=True, timeout=900)
    os.replace(tmp, dst)


def probe_duration(path):
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                              "default=nw=1:nk=1", path], capture_output=True, text=True, timeout=60).stdout
        return float(out.strip())
    except (ValueError, subprocess.SubprocessError):
        return 0.0


def to_jpeg(data, width, square=False):
    img = Image.open(io.BytesIO(data))
    img = img.convert("RGB")
    if square:
        s = min(img.size)
        left, top = (img.width - s) // 2, (img.height - s) // 2
        img = img.crop((left, top, left + s, top + s))
    if img.width > width:
        img = img.resize((width, max(1, round(img.height * width / img.width))), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, "JPEG", quality=82, progressive=False)  # iOS 6 decodes progressive JPEGs slowly
    return out.getvalue()


class MediaCache:
    def __init__(self, source, cache_dir, profile="compat", max_bytes=2 * 1024 ** 3):
        self.source = source
        self.profile = profile
        self.max_bytes = max_bytes
        self.video_dir = os.path.join(cache_dir, "videos")
        self.image_dir = os.path.join(cache_dir, "images")
        os.makedirs(self.video_dir, exist_ok=True)
        os.makedirs(self.image_dir, exist_ok=True)
        self._locks = {}
        self._locks_lock = threading.Lock()
        self._errors = {}
        self._prefetch = ThreadPoolExecutor(max_workers=2)

    def _lock(self, key):
        with self._locks_lock:
            return self._locks.setdefault(key, threading.Lock())

    def video_path(self, vid):
        return os.path.join(self.video_dir, "%s.%s.mp4" % (vid, self.profile))

    def is_ready(self, vid):
        return os.path.exists(self.video_path(vid))

    def prepare_video(self, vid):
        """Blocks until the iOS 6 version exists; returns its path."""
        vid = str(vid)
        dst = self.video_path(vid)
        if os.path.exists(dst):
            return dst
        with self._lock("v" + vid):
            if os.path.exists(dst):
                return dst
            base = os.path.join(self.video_dir, vid)
            src = None
            try:
                src = self.source.download_video(vid, base)
                ffmpeg_ios6(src, dst, self.profile)
                self._errors.pop(vid, None)
            except Exception as e:
                self._errors[vid] = str(e)
                raise
            finally:
                if src and os.path.exists(src):
                    os.remove(src)
            self._trim()
            return dst

    def prefetch(self, vids):
        for vid in vids:
            if not self.is_ready(vid):
                self._prefetch.submit(self._quiet_prepare, vid)

    def _quiet_prepare(self, vid):
        try:
            self.prepare_video(vid)
        except Exception as e:  # noqa: BLE001
            log.warning("prefetch of %s failed: %s", vid, e)

    def image(self, kind, key, url, width, square=False):
        path = os.path.join(self.image_dir, "%s_%s_%d.jpg" % (kind, key, width))
        if os.path.exists(path):
            return path
        with self._lock("i" + path):
            if not os.path.exists(path):
                data = to_jpeg(self.source.fetch_bytes(url), width, square)
                with open(path + ".part", "wb") as f:
                    f.write(data)
                os.replace(path + ".part", path)
        return path

    def _trim(self):
        files = []
        for d in (self.video_dir, self.image_dir):
            for name in os.listdir(d):
                p = os.path.join(d, name)
                try:
                    st = os.stat(p)
                    files.append((st.st_atime, st.st_size, p))
                except OSError:
                    pass
        total = sum(f[1] for f in files)
        for _, size, p in sorted(files):
            if total <= self.max_bytes:
                break
            try:
                os.remove(p)
                total -= size
            except OSError:
                pass
