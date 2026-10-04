#import "RTVideoCache.h"

static const NSUInteger kRTVideoCacheKeep = 24;
static NSString * const kRTCDNUserAgent = @"AppleCoreMedia/1.0.0.10B329 (iPhone; U; CPU OS 6_1_3 like Mac OS X; en_us)";

typedef void (^RTVideoHandler)(NSString *, RTHTTPResponse *, NSError *);

@interface RTVideoCache ()
@property (nonatomic, strong) NSMutableDictionary *waiting;   // id -> handlers
@end

@implementation RTVideoCache

+ (instancetype)shared
{
    static RTVideoCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[RTVideoCache alloc] init]; });
    return cache;
}

+ (NSString *)cacheDirectory
{
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *caches = dirs.count ? dirs[0] : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"nl.retrotok.legacytiktok";
    return [[caches stringByAppendingPathComponent:bundleID] stringByAppendingPathComponent:@"videos"];
}

- (instancetype)init
{
    if ((self = [super init])) _waiting = [NSMutableDictionary dictionary];
    return self;
}

- (NSString *)pathForID:(NSString *)videoID
{
    return [[RTVideoCache cacheDirectory] stringByAppendingPathComponent:[videoID stringByAppendingPathExtension:@"mp4"]];
}

- (NSString *)cachedPathForID:(NSString *)videoID
{
    NSString *path = [self pathForID:videoID];
    return [[NSFileManager defaultManager] fileExistsAtPath:path] ? path : nil;
}

- (void)fetchItem:(NSDictionary *)item handler:(RTVideoHandler)handler
{
    NSString *vid = RTStr(item[@"id"]);
    if (!vid.length) { handler(nil, nil, RTMakeError(-1, @"video has no id")); return; }
    NSString *cached = [self cachedPathForID:vid];
    if (cached) {
        [[NSFileManager defaultManager] setAttributes:@{ NSFileModificationDate: [NSDate date] } ofItemAtPath:cached error:NULL];
        handler(cached, nil, nil);
        return;
    }
    NSMutableArray *list = self.waiting[vid];
    if (list) { [list addObject:[handler copy]]; return; }
    self.waiting[vid] = [NSMutableArray arrayWithObject:[handler copy]];
    [self tryURLs:RTArr(item[@"video_urls"]) index:0 videoID:vid lastError:nil];
}

- (void)tryURLs:(NSArray *)urls index:(NSUInteger)i videoID:(NSString *)vid lastError:(NSError *)lastError
{
    if (i >= urls.count) {
        [self finish:vid path:nil response:nil error:lastError ?: RTMakeError(-1, @"no playable video address")];
        return;
    }
    NSURL *url = [NSURL URLWithString:RTStr(urls[i])];
    if (!url) { [self tryURLs:urls index:i + 1 videoID:vid lastError:lastError]; return; }
    [[RTHTTPClient shared] download:url headers:@{ @"User-Agent": kRTCDNUserAgent } toFile:[self pathForID:vid]
                            handler:^(RTHTTPResponse *resp, NSError *error) {
        if (!error && resp.bytes < 1024) {
            [[NSFileManager defaultManager] removeItemAtPath:resp.filePath error:NULL];
            error = RTMakeError(-1, @"CDN sent an empty file");
        }
        if (error) {
            RTLog(@"download %@ from %@ failed: %@", vid, url.host, error.localizedDescription);
            [self tryURLs:urls index:i + 1 videoID:vid lastError:error];
            return;
        }
        [self finish:vid path:resp.filePath response:resp error:nil];
        [self prune];
    }];
}

- (void)finish:(NSString *)vid path:(NSString *)path response:(RTHTTPResponse *)resp error:(NSError *)error
{
    NSArray *handlers = self.waiting[vid];
    [self.waiting removeObjectForKey:vid];
    for (RTVideoHandler h in handlers) h(path, resp, error);
}

- (void)prune
{
    NSString *dir = [RTVideoCache cacheDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
        NSString *p = [dir stringByAppendingPathComponent:name];
        NSDate *m = [fm attributesOfItemAtPath:p error:NULL][NSFileModificationDate];
        if ([name hasSuffix:@".mp4"] && m) [files addObject:@[ m, p ]];
    }
    if (files.count <= kRTVideoCacheKeep) return;
    [files sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [b[0] compare:a[0]]; }];
    for (NSUInteger i = kRTVideoCacheKeep; i < files.count; i++) [fm removeItemAtPath:files[i][1] error:NULL];
}

@end
