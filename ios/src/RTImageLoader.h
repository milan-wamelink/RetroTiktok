#import "RTCommon.h"

// Loads cover / avatar JPEGs straight from TikTok's CDN (through RTHTTPClient / mbedTLS) into image views, with a
// memory cache. Images are decoded and shrunk to screen size off the main thread. Reused views are handled: the
// image is only set when the view still wants the same URL.
@interface RTImageLoader : NSObject
+ (instancetype)shared;
- (void)loadPath:(NSString *)url into:(UIImageView *)imageView placeholder:(UIImage *)placeholder;
- (void)loadPath:(NSString *)url handler:(void (^)(UIImage *image))handler;
- (void)clearMemory;
@end
