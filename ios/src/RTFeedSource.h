#import "RTCommon.h"

// The UI only talks to an RTFeedSource. Items are normalized dictionaries, so the TikTok endpoint can be swapped
// (another aweme host, the web API, the optional RetroTok server) without touching the screens.
//
// Item keys: id, desc, author, nickname, avatar_url, cover_url, video_urls (NSArray of http(s) URL strings, best
// mirror first), width, height, duration (seconds), likes, comments, shares, plays, music, music_author, web_url.
typedef void (^RTFeedLog)(NSString *line);
typedef void (^RTFeedHandler)(NSArray *items, NSError *error);

@protocol RTFeedSource <NSObject>
- (NSString *)sourceName;
// refresh = start over; otherwise the next page. log (optional) receives progress lines for diagnostics.
- (void)loadFeedRefresh:(BOOL)refresh log:(RTFeedLog)log handler:(RTFeedHandler)handler;
@end
