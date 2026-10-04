#import "RTImageLoader.h"
#import "RTAPI.h"
#import <objc/runtime.h>

static char kRTWantedKey;

@interface RTImageLoader ()
@property (nonatomic, strong) NSCache *cache;
@property (nonatomic, strong) NSMutableDictionary *waiting;   // URL string -> array of handlers
@end

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
        _cache.totalCostLimit = 12 * 1024 * 1024;
        _waiting = [NSMutableDictionary dictionary];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearMemory)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (void)clearMemory { [self.cache removeAllObjects]; }

- (void)loadPath:(NSString *)path handler:(void (^)(UIImage *))handler
{
    if (!path) { if (handler) handler(nil); return; }
    UIImage *cached = [self.cache objectForKey:path];
    if (cached) { if (handler) handler(cached); return; }
    NSMutableArray *list = self.waiting[path];
    if (list) { if (handler) [list addObject:[handler copy]]; return; }
    list = [NSMutableArray array];
    if (handler) [list addObject:[handler copy]];
    self.waiting[path] = list;
    [[RTAPI shared] dataAtURL:[[RTAPI shared] URLForPath:path] handler:^(NSData *data, NSError *error) {
        UIImage *image = data ? [UIImage imageWithData:data scale:[UIScreen mainScreen].scale] : nil;
        if (image) [self.cache setObject:image forKey:path cost:data.length * 4];
        NSArray *handlers = self.waiting[path];
        [self.waiting removeObjectForKey:path];
        for (void (^h)(UIImage *) in handlers) h(image);
    }];
}

- (void)loadPath:(NSString *)path into:(UIImageView *)imageView placeholder:(UIImage *)placeholder
{
    objc_setAssociatedObject(imageView, &kRTWantedKey, path, OBJC_ASSOCIATION_COPY_NONATOMIC);
    UIImage *cached = path ? [self.cache objectForKey:path] : nil;
    imageView.image = cached ?: placeholder;
    if (cached || !path) return;
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
