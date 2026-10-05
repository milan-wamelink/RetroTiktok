#import "RTFeedSource.h"

// Direct For You feed from TikTok's legacy mobile app API (aweme/v1/feed). No login, cookies or signature.
// TikTok answers roughly every other request with an empty body, so requests are retried.
// Profiles and comments come from TikTok's public web JSON endpoints on www.tiktok.com (the aweme ones for those
// now require request signatures); those need no signature, login or cookies either.
@interface RTAwemeAPI : NSObject <RTFeedSource, RTProfileSource>
+ (instancetype)shared;
+ (NSDictionary *)normalizeAweme:(NSDictionary *)aweme;   // nil for photo posts / unplayable items
@end
