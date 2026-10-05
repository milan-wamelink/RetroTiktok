#import "RTCommon.h"

@interface RTSettings : NSObject
+ (NSString *)serverURL;              // "http://192.168.1.20:8460", no trailing slash; nil when not set
+ (void)setServerURL:(NSString *)url;
+ (NSString *)accessKey;
+ (void)setAccessKey:(NSString *)key;
+ (BOOL)soundOn;
+ (void)setSoundOn:(BOOL)on;
+ (NSInteger)cacheLimitMB;            // video cache size cap, default 25
+ (void)setCacheLimitMB:(NSInteger)mb;
@end
