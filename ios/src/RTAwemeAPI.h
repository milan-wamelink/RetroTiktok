#import "RTFeedSource.h"

// Direct For You feed from TikTok's legacy mobile app API (aweme/v1/feed). No login, cookies or signature.
// TikTok answers roughly every other request with an empty body, so requests are retried.
// Profiles and comments come from TikTok's public web JSON endpoints on www.tiktok.com (the aweme ones for those
// now require request signatures); those need no signature, login or cookies either.
@interface RTAwemeAPI : NSObject <RTFeedSource, RTProfileSource>
+ (instancetype)shared;
+ (NSDictionary *)normalizeAweme:(NSDictionary *)aweme;   // nil for photo posts / unplayable items
// Replies under one comment, 5 per page (web endpoint).
- (void)loadReplies:(NSString *)commentID videoID:(NSString *)videoID cursor:(NSString *)cursor handler:(RTCommentsHandler)handler;
// V3 favorites: fresh video links for a saved item (needs its id, sec_uid and create_time).
- (void)refreshItem:(NSDictionary *)item handler:(void (^)(NSDictionary *fresh, NSError *error))handler;
@end
