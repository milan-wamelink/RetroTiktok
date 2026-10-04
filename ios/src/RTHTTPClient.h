#import "RTCommon.h"

// Objective-C front end for rt_http.c (mbedTLS). All TikTok traffic goes through here; nothing uses the system
// TLS stack, whose iOS 6 root store does not know the DigiCert G2/G3 roots TikTok uses.
@interface RTHTTPResponse : NSObject
@property (nonatomic, assign) NSInteger status;
@property (nonatomic, strong) NSData *data;            // memory requests, gzip already undone
@property (nonatomic, copy) NSString *filePath;        // download requests
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic, copy) NSString *tlsInfo;
@property (nonatomic, copy) NSString *finalURL;
@property (nonatomic, assign) long long bytes;
@property (nonatomic, assign) NSInteger redirects;
@property (nonatomic, assign) NSTimeInterval duration;
@end

typedef void (^RTHTTPHandler)(RTHTTPResponse *response, NSError *error);

@interface RTHTTPClient : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSInteger rootCount;   // trusted roots parsed from roots.pem
- (void)GET:(NSURL *)url headers:(NSDictionary *)headers handler:(RTHTTPHandler)handler;
// Streams the body to path (via path.part); only a complete 2xx response is moved into place.
- (void)download:(NSURL *)url headers:(NSDictionary *)headers toFile:(NSString *)path handler:(RTHTTPHandler)handler;
@end

NSData *RTGunzipIfNeeded(NSData *data);
