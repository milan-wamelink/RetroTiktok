#import "RTCommon.h"

// The UI only talks to an RTFeedSource. Items are normalized dictionaries, so the TikTok endpoint can be swapped
// (another aweme host, the web API, the optional RetroTok server) without touching the screens.
//
// Item keys: id, desc, author, nickname, avatar_url, cover_url, video_urls (NSArray of http(s) URL strings, best
// mirror first), width, height, duration (seconds), likes, comments, shares, plays, music, music_author, web_url,
// sec_uid (the author's profile id), create_time (unix seconds), thumb_url (small square cover, profile grids only),
// lang and features (aweme feed only, for the local ranking; see RTFeatures).
typedef void (^RTFeedLog)(NSString *line);
typedef void (^RTFeedHandler)(NSArray *items, NSError *error);

@protocol RTFeedSource <NSObject>
- (NSString *)sourceName;
// refresh = start over; otherwise the next page. log (optional) receives progress lines for diagnostics.
- (void)loadFeedRefresh:(BOOL)refresh log:(RTFeedLog)log handler:(RTFeedHandler)handler;
@end

// Optional: a source that learns from what the player saw (the local For You ranking). Read-only reports.
@protocol RTFeedLearning <NSObject>
// The user left this video: seconds played including loops, the video's length, and whether its picture ever showed.
- (void)feedDidView:(NSDictionary *)item seconds:(double)seconds duration:(double)duration showedVideo:(BOOL)showed;
- (void)feedDidEngage:(NSDictionary *)item kind:(NSString *)kind;   // @"favorite", @"comments", @"profile"
@end

// V2: profiles and comments. nextCursor is nil when there are no more pages.
// Profile keys: author, nickname, sec_uid, avatar_url, signature, followers, following, hearts, videos.
// Comment keys: id, text, author, nickname, avatar_url, likes, replies, time (unix seconds).
typedef void (^RTProfileHandler)(NSDictionary *profile, NSArray *items, NSString *nextCursor, NSError *error);
typedef void (^RTCommentsHandler)(NSArray *comments, long long total, NSString *nextCursor, NSError *error);

@protocol RTProfileSource <NSObject>
- (void)loadProfileVideos:(NSString *)secUID cursor:(NSString *)cursor log:(RTFeedLog)log handler:(RTProfileHandler)handler;
- (void)loadComments:(NSString *)videoID cursor:(NSString *)cursor log:(RTFeedLog)log handler:(RTCommentsHandler)handler;
@end
