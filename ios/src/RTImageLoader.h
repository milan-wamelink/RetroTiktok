#import "RTCommon.h"

// Loads JPEGs from the server into image views, with a memory cache. Reused cells are handled: the image is
// only set when the view still wants the same URL.
@interface RTImageLoader : NSObject
+ (instancetype)shared;
- (void)loadPath:(NSString *)path into:(UIImageView *)imageView placeholder:(UIImage *)placeholder;
- (void)loadPath:(NSString *)path handler:(void (^)(UIImage *image))handler;
- (void)clearMemory;
@end
