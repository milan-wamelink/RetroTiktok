"""The /admin page: TikTok developer keys and the login used for posting."""
from html import escape

PAGE = """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>RetroTok server</title><style>
body{font:15px Helvetica,Arial,sans-serif;background:#c5ccd4 repeating-linear-gradient(90deg,#c5ccd4 0,#c5ccd4 5px,#cbd2d8 5px,#cbd2d8 7px);margin:0;color:#222}
h1{margin:0;padding:10px;text-align:center;color:#fff;font-size:20px;text-shadow:0 -1px 0 rgba(0,0,0,.5);
background:linear-gradient(#b0bccd,#889bb3 50%%,#8195af 50%%,#6d84a2);border-bottom:1px solid #2d3642}
.box{background:#fff;border:1px solid #aab;border-radius:9px;margin:16px auto;max-width:560px;padding:12px 16px}
h2{font-size:16px;color:#4c566c;text-shadow:0 1px 0 #fff;max-width:560px;margin:18px auto 0}
input[type=text],input[type=password]{width:100%%;box-sizing:border-box;padding:7px;margin:4px 0 10px;border:1px solid #999;border-radius:5px}
button,.btn{display:inline-block;padding:7px 16px;border-radius:6px;border:1px solid #2a4a7a;color:#fff;font-weight:bold;text-decoration:none;
background:linear-gradient(#7ea3e0,#3a6cc2 50%%,#2b5db5 50%%,#3567bf);text-shadow:0 -1px 0 rgba(0,0,0,.4);cursor:pointer}
.msg{background:#ffd;border-color:#cc9}.small{color:#666;font-size:13px}code{background:#eee;padding:1px 4px}
</style></head><body><h1>RetroTok server</h1>%(msg)s
<h2>Posting account</h2><div class="box">%(account)s</div>
<h2>TikTok developer app</h2><div class="box"><form method="post" action="/admin/keys">
<label>Client key<input type="text" name="client_key" value="%(client_key)s"></label>
<label>Client secret %(secret_state)s<input type="password" name="client_secret" placeholder="leave empty to keep"></label>
<label>Redirect URI (exactly as registered in the TikTok app)<input type="text" name="redirect_uri" value="%(redirect_uri)s"></label>
<button>Save</button></form>
<p class="small">Create an app at <a href="https://developers.tiktok.com/apps">developers.tiktok.com</a>, add <b>Login Kit</b>
and <b>Content Posting API</b> (enable Direct Post), request the scopes <code>user.info.basic</code>,
<code>video.upload</code>, <code>video.publish</code>. Until TikTok audits the app, direct posts can only be private
(&quot;Only me&quot;); &quot;Send to TikTok inbox&quot; drafts work for finishing the post in the TikTok app.
If this server is reachable over HTTPS you can register <code>https://&lt;server&gt;/admin/callback</code>;
otherwise register any HTTPS page you own and paste the address TikTok sends you to below.</p></div>
</body></html>"""


def render_admin(poster, msg=None, access_key=None):
    c = poster.conf
    if poster.logged_in():
        acc = c.get("account") or {}
        account = ("<p>Logged in as <b>%s</b></p><form method='post' action='/admin/logout'><button>Log out</button></form>"
                   % escape(acc.get("display_name") or "TikTok user"))
    elif poster.configured():
        account = ("<p><a class='btn' href='/admin/login' target='_blank'>Log in with TikTok</a></p>"
                   "<form method='post' action='/admin/code'><label>After logging in, paste the address TikTok "
                   "redirected you to (or just the code):<input type='text' name='code'></label>"
                   "<button>Finish login</button></form>")
    else:
        account = "<p>Fill in the developer app below first.</p>"
    return PAGE % {
        "msg": "<div class='box msg'>%s</div>" % escape(msg) if msg else "",
        "account": account,
        "client_key": escape(c.get("client_key", "")),
        "secret_state": "(saved)" if c.get("client_secret") else "",
        "redirect_uri": escape(c.get("redirect_uri", "")),
    }
