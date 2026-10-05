#import "RTVideoCache.h"
#import "RTAwemeAPI.h"
#import "RTSettings.h"

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
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    if ([RTVideoCache isWebPage:path]) {   // left by builds before 0.6.3
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        return nil;
    }
    return path;
}

// Some regions answer a video link with a TikTok web page (HTTP 200, text/html) instead of the MP4.
+ (BOOL)isWebPage:(NSString *)path
{
    NSData *head = [[NSFileHandle fileHandleForReadingAtPath:path] readDataOfLength:1];
    return head.length == 1 && ((const char *)head.bytes)[0] == '<';
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
    NSArray *urls = RTArr(item[@"video_urls"]);
    if (!RTBool(item[@"needs_fresh_links"])) { [self tryURLs:urls index:0 videoID:vid lastError:nil]; return; }
    // Hashtag results: links from the creator's own video list play everywhere; the item's own links are the fallback.
    [[RTAwemeAPI shared] refreshItem:item handler:^(NSDictionary *fresh, NSError *error) {
        NSArray *first = RTArr(fresh[@"video_urls"]) ?: @[];
        if (!fresh) RTLog(@"fresh links for %@ failed: %@", vid, error.localizedDescription);
        [self tryURLs:[first arrayByAddingObjectsFromArray:urls] index:0 videoID:vid lastError:nil];
    }];
}

- (void)tryURLs:(NSArray *)urls index:(NSUInteger)i videoID:(NSString *)vid lastError:(NSError *)lastError
{
    if (i >= urls.count) {
        [self finish:vid path:nil response:nil error:lastError ?: RTMakeError(-1, @"no playable video address")];
        return;
    }
    NSURL *url = [NSURL URLWithString:RTStr(urls[i])];
    if (!url) { [self tryURLs:urls index:i + 1 videoID:vid lastError:lastError]; return; }
    // Profile videos (v16-webapp-prime) answer 403 without the Referer; the feed CDN does not mind it.
    NSDictionary *headers = @{ @"User-Agent": kRTCDNUserAgent, @"Referer": @"https://www.tiktok.com/" };
    [[RTHTTPClient shared] download:url headers:headers toFile:[self pathForID:vid]
                            handler:^(RTHTTPResponse *resp, NSError *error) {
        if (!error && resp.bytes < 1024) {
            [[NSFileManager defaultManager] removeItemAtPath:resp.filePath error:NULL];
            error = RTMakeError(-1, @"CDN sent an empty file");
        } else if (!error && ([resp.contentType hasPrefix:@"text/"] || [RTVideoCache isWebPage:resp.filePath])) {
            [[NSFileManager defaultManager] removeItemAtPath:resp.filePath error:NULL];
            error = RTMakeError(-1, @"CDN sent a web page instead of the video");
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
    NSSet *keep = self.protectedIDs ?: [NSSet set];
    unsigned long long limit = (unsigned long long)[RTSettings cacheLimitMB] * 1024 * 1024;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{ [self pruneKeeping:keep limit:limit]; });
}

- (void)pruneKeeping:(NSSet *)keep limit:(unsigned long long)limit
{
    NSString *dir = [RTVideoCache cacheDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
        NSString *p = [dir stringByAppendingPathComponent:name];
        NSDictionary *attrs = [fm attributesOfItemAtPath:p error:NULL];
        NSDate *m = attrs[NSFileModificationDate];
        if (!m) continue;
        if ([name hasSuffix:@".part"]) {
            // leftovers of downloads cut off by the app being killed
            if (-[m timeIntervalSinceNow] > 600) [fm removeItemAtPath:p error:NULL];
            continue;
        }
        if ([name hasSuffix:@".mp4"]) [files addObject:@[ m, p, @([attrs fileSize]), [name stringByDeletingPathExtension] ]];
    }
    [files sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [b[0] compare:a[0]]; }];
    unsigned long long total = 0;
    for (NSArray *f in files) {
        unsigned long long size = [f[2] unsignedLongLongValue];
        if ([keep containsObject:f[3]] || total + size <= limit) total += size;
        else [fm removeItemAtPath:f[1] error:NULL];
    }
}

@end
