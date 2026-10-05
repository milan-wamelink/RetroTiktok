#import "RTImageLoader.h"
#import "RTHTTPClient.h"
#import <objc/runtime.h>

static char kRTWantedKey;

@interface RTImageLoader ()
@property (nonatomic, strong) NSCache *cache;
@property (nonatomic, strong) NSMutableDictionary *waiting;   // URL string -> array of handlers
@property (nonatomic, assign) CGFloat screenScale;
@property (nonatomic, assign) CGFloat maxPixels;
@end

// TikTok covers are up to 1080x1920; decoding them at full size would cost ~8 MB each on a 512 MB phone.
static UIImage *RTDecodedImage(NSData *data, CGFloat maxPixels, CGFloat scale)
{
    UIImage *src = data.length ? [UIImage imageWithData:data] : nil;
    if (!src || src.size.width < 1 || src.size.height < 1) return nil;
    CGFloat f = MIN((CGFloat)1, maxPixels / MAX(src.size.width, src.size.height));
    CGSize size = CGSizeMake(floor(src.size.width * f) / scale, floor(src.size.height * f) / scale);
    UIGraphicsBeginImageContextWithOptions(size, YES, scale);
    [src drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

@implementation RTImageLoader

+ (instancetype)shared
{
    static RTImageLoader *loader;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ loader = [[RTImageLoader alloc] init]; });
    return loader;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _cache = [[NSCache alloc] init];
        _cache.totalCostLimit = 16 * 1024 * 1024;
        _screenScale = [UIScreen mainScreen].scale;
        CGSize screen = [UIScreen mainScreen].bounds.size;
        _maxPixels = MAX(screen.width, screen.height) * _screenScale;
        _waiting = [NSMutableDictionary dictionary];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearMemory)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (void)clearMemory { [self.cache removeAllObjects]; }

- (void)loadPath:(NSString *)path handler:(void (^)(UIImage *))handler
{
    if (!path.length) { if (handler) handler(nil); return; }
    UIImage *cached = [self.cache objectForKey:path];
    if (cached) { if (handler) handler(cached); return; }
    NSMutableArray *list = self.waiting[path];
    if (list) { if (handler) [list addObject:[handler copy]]; return; }
    list = [NSMutableArray array];
    if (handler) [list addObject:[handler copy]];
    self.waiting[path] = list;
    void (^finish)(UIImage *) = ^(UIImage *image) {
        if (image) [self.cache setObject:image forKey:path cost:(NSUInteger)(image.size.width * image.size.height * image.scale * image.scale * 4)];
        NSArray *handlers = self.waiting[path];
        [self.waiting removeObjectForKey:path];
        for (void (^h)(UIImage *) in handlers) h(image);
    };
    NSURL *url = [NSURL URLWithString:path];
    if (!url) { finish(nil); return; }
    CGFloat maxPixels = self.maxPixels, scale = self.screenScale;
    [[RTHTTPClient shared] GET:url headers:nil handler:^(RTHTTPResponse *resp, NSError *error) {
        NSData *data = (!error && resp.status == 200) ? resp.data : nil;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UIImage *image = RTDecodedImage(data, maxPixels, scale);
            dispatch_async(dispatch_get_main_queue(), ^{ finish(image); });
        });
    }];
}

- (void)loadPath:(NSString *)path into:(UIImageView *)imageView placeholder:(UIImage *)placeholder
{
    objc_setAssociatedObject(imageView, &kRTWantedKey, path, OBJC_ASSOCIATION_COPY_NONATOMIC);
    UIImage *cached = path ? [self.cache objectForKey:path] : nil;
    imageView.image = cached ?: placeholder;
    if (cached || !path.length) return;
    __weak UIImageView *weakView = imageView;
    [self loadPath:path handler:^(UIImage *image) {
        UIImageView *view = weakView;
        if (!view || !image) return;
        if (![objc_getAssociatedObject(view, &kRTWantedKey) isEqualToString:path]) return;
        view.image = image;
        CATransition *fade = [CATransition animation];
        fade.duration = 0.2;
        [view.layer addAnimation:fade forKey:nil];
    }];
}

@end
