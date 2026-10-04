#import "RTHTTPClient.h"

// Downloads feed videos straight from TikTok's CDN into the app's cache folder
// (/var/mobile/Library/Caches/<bundle id>/videos), so AVPlayer only ever plays local files.
@interface RTVideoCache : NSObject
+ (instancetype)shared;
+ (NSString *)cacheDirectory;
- (NSString *)cachedPathForID:(NSString *)videoID;      // nil when not downloaded yet
// Tries each URL in item[@"video_urls"] until one downloads. Concurrent calls for the same id share one download.
- (void)fetchItem:(NSDictionary *)item handler:(void (^)(NSString *path, RTHTTPResponse *response, NSError *error))handler;
- (void)prune;                                          // keeps the newest kRTVideoCacheKeep files
@end
