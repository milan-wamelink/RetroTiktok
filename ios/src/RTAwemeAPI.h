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

// V4 search. TikTok's free-text video/user search needs signatures we can't make, so search is: typing suggestions,
// hashtags (challenge/detail + challenge/item_list, signed on the phone with X-Bogus) and creators by exact username.
// Hashtag keys: hashtag_id, title, desc, videos, views. Creator lookups return a profile dictionary (see RTFeedSource.h).
- (void)loadSuggestions:(NSString *)text handler:(void (^)(NSArray *words, NSError *error))handler;
- (void)lookupHashtag:(NSString *)name handler:(void (^)(NSDictionary *tag, NSError *error))handler;
- (void)loadHashtagVideos:(NSString *)tagID cursor:(NSString *)cursor handler:(RTProfileHandler)handler;
- (void)lookupUser:(NSString *)uniqueID handler:(void (^)(NSDictionary *profile, NSError *error))handler;
@end
