#import "RTFeedSource.h"

// Direct For You feed from TikTok's legacy mobile app API (aweme/v1/feed). No login, cookies or signature.
// TikTok answers roughly every other request with an empty body, so requests are retried.
@interface RTAwemeAPI : NSObject <RTFeedSource>
+ (instancetype)shared;
+ (NSDictionary *)normalizeAweme:(NSDictionary *)aweme;   // nil for photo posts / unplayable items
@end
