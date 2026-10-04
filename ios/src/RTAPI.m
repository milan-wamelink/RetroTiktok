#import "RTAPI.h"
#import "RTSettings.h"

@interface RTAPI ()
@property (nonatomic, strong) NSOperationQueue *queue;
@end

@implementation RTAPI

+ (instancetype)shared
{
    static RTAPI *api;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ api = [[RTAPI alloc] init]; });
    return api;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 6;
    }
    return self;
}

- (BOOL)hasServer { return [RTSettings serverURL] != nil; }

- (NSURL *)URLForPath:(NSString *)path
{
    NSString *base = [RTSettings serverURL];
    if (!base || !path) return nil;
    NSString *s = [path hasPrefix:@"http"] ? path : [base stringByAppendingString:path];
    NSString *key = [RTSettings accessKey];
    if (key.length) {
        s = [s stringByAppendingFormat:@"%@key=%@", [s rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&", RTURLEncode(key)];
    }
    return [NSURL URLWithString:s];
}

- (id)requestWithURL:(NSURL *)url method:(NSString *)method timeout:(NSTimeInterval)timeout
{
    NSMutableURLRequest *req = [RTURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:timeout];
    req.HTTPMethod = method;
    [req setValue:@"RetroTok/1.0 (iOS 6)" forHTTPHeaderField:@"User-Agent"];
    NSString *key = [RTSettings accessKey];
    if (key.length) [req setValue:key forHTTPHeaderField:@"X-RetroTok-Key"];
    return req;
}

- (void)send:(NSMutableURLRequest *)req handler:(RTJSONHandler)handler
{
    if (!req) {
        if (handler) handler(nil, RTMakeError(-1, @"Set the RetroTok server address in Settings first."));
        return;
    }
    [RTURLConnection sendAsynchronousRequest:req queue:self.queue completionHandler:^(id response, NSData *data, NSError *error) {
        id json = nil;
        NSError *err = nil;
        NSInteger status = [response respondsToSelector:@selector(statusCode)] ? [response statusCode] : 0;
        if (error) {
            err = RTMakeError(error.code, [NSString stringWithFormat:@"Can't reach the RetroTok server (%@).", error.localizedDescription]);
        } else {
            json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            NSString *apiError = RTStr(RTDict(json)[@"error"]);
            if (apiError || status >= 400) {
                err = RTMakeError(status, apiError ?: [NSString stringWithFormat:@"Server error %ld", (long)status]);
                json = nil;
            }
        }
        RTMain(^{ if (handler) handler(json, err); });
    }];
}

- (void)GET:(NSString *)path handler:(RTJSONHandler)handler
{
    [self GET:path timeout:60 handler:handler];
}

- (void)GET:(NSString *)path timeout:(NSTimeInterval)timeout handler:(RTJSONHandler)handler
{
    NSURL *url = [self URLForPath:path];
    [self send:url ? [self requestWithURL:url method:@"GET" timeout:timeout] : nil handler:handler];
}

- (void)POST:(NSString *)path body:(NSDictionary *)body handler:(RTJSONHandler)handler
{
    NSURL *url = [self URLForPath:path];
    NSMutableURLRequest *req = url ? [self requestWithURL:url method:@"POST" timeout:60] : nil;
    if (req && body) {
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    [self send:req handler:handler];
}

- (void)DELETE:(NSString *)path handler:(RTJSONHandler)handler
{
    NSURL *url = [self URLForPath:path];
    [self send:url ? [self requestWithURL:url method:@"DELETE" timeout:60] : nil handler:handler];
}

- (void)dataAtURL:(NSURL *)url handler:(RTDataHandler)handler
{
    if (!url) { if (handler) handler(nil, RTMakeError(-1, @"No URL")); return; }
    NSMutableURLRequest *req = [self requestWithURL:url method:@"GET" timeout:60];
    [RTURLConnection sendAsynchronousRequest:req queue:self.queue completionHandler:^(id response, NSData *data, NSError *error) {
        NSInteger status = [response respondsToSelector:@selector(statusCode)] ? [response statusCode] : 0;
        NSError *err = error ?: (status >= 400 ? RTMakeError(status, @"HTTP error") : nil);
        RTMain(^{ if (handler) handler(err ? nil : data, err); });
    }];
}

- (void)forYou:(RTJSONHandler)handler
{
    [self GET:@"/api/feed/foryou?count=12" handler:handler];
}

- (void)prepareVideo:(NSString *)videoID handler:(RTJSONHandler)handler
{
    [self GET:[NSString stringWithFormat:@"/api/prepare/%@", videoID] timeout:180 handler:handler];
}

- (void)prefetchVideos:(NSArray *)videoIDs
{
    if (videoIDs.count) [self POST:@"/api/prefetch" body:@{ @"ids": videoIDs } handler:nil];
}

@end
