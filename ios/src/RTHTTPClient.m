#import "RTHTTPClient.h"
#import "rt_http.h"
#import <zlib.h>
#import <stdio.h>

@implementation RTHTTPResponse
@end

NSData *RTGunzipIfNeeded(NSData *data)
{
    const unsigned char *b = data.bytes;
    if (data.length < 18 || b[0] != 0x1f || b[1] != 0x8b) return data;
    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    if (inflateInit2(&zs, 16 + MAX_WBITS) != Z_OK) return nil;
    NSMutableData *out = [NSMutableData dataWithLength:data.length * 4];
    zs.next_in = (Bytef *)data.bytes;
    zs.avail_in = (uInt)data.length;
    int ret;
    do {
        if (zs.total_out >= out.length) out.length += data.length * 2;
        zs.next_out = (Bytef *)out.mutableBytes + zs.total_out;
        zs.avail_out = (uInt)(out.length - zs.total_out);
        ret = inflate(&zs, Z_NO_FLUSH);
    } while (ret == Z_OK);
    inflateEnd(&zs);
    if (ret != Z_STREAM_END) return nil;
    out.length = zs.total_out;
    return out;
}

static int RTSinkData(void *ctx, const unsigned char *d, size_t n)
{
    [(__bridge NSMutableData *)ctx appendBytes:d length:n];
    return 0;
}

static int RTSinkFile(void *ctx, const unsigned char *d, size_t n)
{
    return fwrite(d, 1, n, (FILE *)ctx) == n ? 0 : 1;
}

@interface RTHTTPClient ()
@property (nonatomic, strong) NSOperationQueue *queue;
@property (nonatomic, assign) NSInteger rootCount;
@end

@implementation RTHTTPClient

+ (instancetype)shared
{
    static RTHTTPClient *client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ client = [[RTHTTPClient alloc] init]; });
    return client;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 3;
        NSData *pem = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"]];
        int n = pem.length ? rt_http_set_roots(pem.bytes, pem.length) : -1;
        _rootCount = n > 0 ? n : 0;
        RTLog(@"loaded %ld root certificates", (long)_rootCount);
    }
    return self;
}

- (NSString *)headerBlock:(NSDictionary *)headers
{
    NSMutableString *s = [NSMutableString string];
    for (NSString *k in headers) [s appendFormat:@"%@: %@\r\n", k, headers[k]];
    return s;
}

- (void)run:(NSURL *)url headers:(NSDictionary *)headers file:(NSString *)path handler:(RTHTTPHandler)handler
{
    NSString *urlString = url.absoluteString;
    NSString *block = [self headerBlock:headers];
    [self.queue addOperationWithBlock:^{
        rt_http_result r;
        NSMutableData *data = path ? nil : [NSMutableData data];
        NSString *part = [path stringByAppendingString:@".part"];
        FILE *fp = NULL;
        if (path) {
            [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                                      withIntermediateDirectories:YES attributes:nil error:NULL];
            fp = fopen(part.fileSystemRepresentation, "wb");
        }
        NSDate *start = [NSDate date];
        int rc = -1;
        if (path && !fp) {
            memset(&r, 0, sizeof(r));
            snprintf(r.error, sizeof(r.error), "cannot write cache file");
        } else {
            rc = rt_http_get(urlString.UTF8String, block.UTF8String, 20000, 5,
                             path ? RTSinkFile : RTSinkData, path ? (void *)fp : (__bridge void *)data, NULL, &r);
        }
        if (fp) fclose(fp);

        RTHTTPResponse *resp = [[RTHTTPResponse alloc] init];
        resp.status = r.status;
        resp.bytes = r.body_bytes;
        resp.redirects = r.redirects;
        resp.duration = -[start timeIntervalSinceNow];
        resp.contentType = [NSString stringWithUTF8String:r.content_type];
        resp.tlsInfo = [NSString stringWithUTF8String:r.tls_info];
        resp.finalURL = [NSString stringWithUTF8String:r.final_url];
        NSError *error = nil;
        if (rc != 0) {
            error = RTMakeError(-1, [NSString stringWithUTF8String:r.error[0] ? r.error : "network error"]);
        } else if (path && (r.status < 200 || r.status >= 300)) {
            error = RTMakeError(r.status, [NSString stringWithFormat:@"HTTP %d", r.status]);
        }
        if (path) {
            NSFileManager *fm = [NSFileManager defaultManager];
            if (!error) {
                [fm removeItemAtPath:path error:NULL];
                if ([fm moveItemAtPath:part toPath:path error:NULL]) resp.filePath = path;
                else error = RTMakeError(-1, @"cannot store cache file");
            }
            if (error) [fm removeItemAtPath:part error:NULL];
        } else {
            resp.data = RTGunzipIfNeeded(data);
            if (!resp.data && !error) error = RTMakeError(-1, @"corrupt gzip body");
        }
        RTMain(^{ if (handler) handler(resp, error); });
    }];
}

- (void)GET:(NSURL *)url headers:(NSDictionary *)headers handler:(RTHTTPHandler)handler
{
    [self run:url headers:headers file:nil handler:handler];
}

- (void)download:(NSURL *)url headers:(NSDictionary *)headers toFile:(NSString *)path handler:(RTHTTPHandler)handler
{
    [self run:url headers:headers file:path handler:handler];
}

@end
