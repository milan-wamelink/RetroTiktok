#import "RTCommon.h"

// For You language levels (local recommendations).
typedef NS_ENUM(NSInteger, RTLevel) { RTLevelBlock = -2, RTLevelReduce = -1, RTLevelNormal = 0, RTLevelPrefer = 1 };

@interface RTSettings : NSObject
+ (NSString *)serverURL;              // "http://192.168.1.20:8460", no trailing slash; nil when not set
+ (void)setServerURL:(NSString *)url;
+ (NSString *)accessKey;
+ (void)setAccessKey:(NSString *)key;
+ (BOOL)soundOn;
+ (void)setSoundOn:(BOOL)on;
+ (BOOL)playerDebug;                 // on-screen player state overlay (diagnostics), default off
+ (void)setPlayerDebug:(BOOL)on;
+ (NSInteger)cacheLimitMB;            // video cache size cap, default 25
+ (void)setCacheLimitMB:(NSInteger)mb;
+ (BOOL)personalized;                 // rank For You locally and learn from viewing, default YES
+ (void)setPersonalized:(BOOL)on;
+ (double)discovery;                  // 0 Familiar, 0.5 Balanced (default), 1 Experimental
+ (void)setDiscovery:(double)value;
+ (RTLevel)levelForLanguage:(NSString *)code;
// Country TikTok's For You feed is requested for (region=, and its language as language=); defaults to the iPhone's region.
+ (NSString *)feedRegion;
+ (void)setFeedRegion:(NSString *)country;
+ (NSString *)feedLanguage;
+ (void)setLevel:(RTLevel)level forLanguage:(NSString *)code;
@end
