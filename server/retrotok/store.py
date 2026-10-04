"""Small JSON store for the server's settings, follows, likes and TikTok tokens."""
import json
import os
import threading


class Store:
    DEFAULTS = {"following": [], "likes": [], "tiktok": {}}

    def __init__(self, path):
        self.path = path
        self._lock = threading.Lock()
        self.data = json.loads(json.dumps(self.DEFAULTS))
        if os.path.exists(path):
            with open(path) as f:
                self.data.update(json.load(f))

    def save(self):
        with self._lock:
            tmp = self.path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(self.data, f, indent=2)
            os.chmod(tmp, 0o600)
            os.replace(tmp, self.path)

    def get(self, key, default=None):
        return self.data.get(key, default)

    def set(self, key, value):
        self.data[key] = value
        self.save()
