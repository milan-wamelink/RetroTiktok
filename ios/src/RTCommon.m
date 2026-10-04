#import "RTCommon.h"

NSString * const RTErrorDomain = @"RetroTok";
NSString * const RTSettingsDidChangeNotification = @"RTSettingsDidChange";
NSString * const RTFollowingDidChangeNotification = @"RTFollowingDidChange";
NSString * const RTLikesDidChangeNotification = @"RTLikesDidChange";

NSError *RTMakeError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:RTErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: message ?: @"Error" }];
}

NSString *RTStr(id value)
{
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return nil;
}

NSDictionary *RTDict(id value) { return [value isKindOfClass:[NSDictionary class]] ? value : nil; }
NSArray *RTArr(id value) { return [value isKindOfClass:[NSArray class]] ? value : nil; }

long long RTNum(id value)
{
    if ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]]) return [value longLongValue];
    return 0;
}

BOOL RTBool(id value)
{
    if ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]]) return [value boolValue];
    return NO;
}

NSString *RTShortCount(long long n)
{
    if (n < 1000) return [NSString stringWithFormat:@"%lld", n];
    double v; NSString *suffix;
    if (n < 1000000) { v = n / 1000.0; suffix = @"K"; }
    else if (n < 1000000000) { v = n / 1000000.0; suffix = @"M"; }
    else { v = n / 1000000000.0; suffix = @"B"; }
    NSString *s = v >= 100 ? [NSString stringWithFormat:@"%.0f", v] : [NSString stringWithFormat:@"%.1f", v];
    if ([s hasSuffix:@".0"]) s = [s substringToIndex:s.length - 2];
    return [s stringByAppendingString:suffix];
}

NSString *RTTimeAgo(long long unixTime)
{
    if (unixTime <= 0) return @"";
    NSTimeInterval d = [[NSDate date] timeIntervalSince1970] - unixTime;
    if (d < 3600) return [NSString stringWithFormat:@"%dm", MAX(1, (int)(d / 60))];
    if (d < 86400) return [NSString stringWithFormat:@"%dh", (int)(d / 3600)];
    if (d < 7 * 86400) return [NSString stringWithFormat:@"%dd", (int)(d / 86400)];
    if (d < 5 * 7 * 86400) return [NSString stringWithFormat:@"%dw", (int)(d / (7 * 86400))];
    static NSDateFormatter *f;
    if (!f) { f = [[NSDateFormatter alloc] init]; f.dateFormat = @"MMM d, yyyy"; }
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:unixTime]];
}

NSString *RTURLEncode(NSString *s)
{
    return CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (__bridge CFStringRef)(s ?: @""), NULL,
                                                                     CFSTR(":/?#[]@!$&'()*+,;="), kCFStringEncodingUTF8));
}

void RTAlert(NSString *title, NSString *message)
{
    RTMain(^{
        [[[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    });
}
