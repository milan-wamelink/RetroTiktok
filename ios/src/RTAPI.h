#import "RTCommon.h"

typedef void (^RTJSONHandler)(id json, NSError *error);
typedef void (^RTDataHandler)(NSData *data, NSError *error);

// Talks plain HTTP + JSON to the RetroTok server (see /server). All handlers run on the main thread.
@interface RTAPI : NSObject

+ (instancetype)shared;

- (NSURL *)URLForPath:(NSString *)path;             // "/media/cover/1.jpg" -> absolute URL (with the access key)
- (BOOL)hasServer;

- (void)GET:(NSString *)path handler:(RTJSONHandler)handler;
- (void)GET:(NSString *)path timeout:(NSTimeInterval)timeout handler:(RTJSONHandler)handler;
- (void)POST:(NSString *)path body:(NSDictionary *)body handler:(RTJSONHandler)handler;
- (void)DELETE:(NSString *)path handler:(RTJSONHandler)handler;
- (void)dataAtURL:(NSURL *)url handler:(RTDataHandler)handler;

// Feed helpers
- (void)forYou:(RTJSONHandler)handler;              // json: { items: [...] }
- (void)prepareVideo:(NSString *)videoID handler:(RTJSONHandler)handler;   // waits until the iOS 6 MP4 exists
- (void)prefetchVideos:(NSArray *)videoIDs;

@end
