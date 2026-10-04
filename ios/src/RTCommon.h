// Shared helpers. Everything here must be iOS 6.0 safe.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Any API newer than the iOS 6.0 deployment target is a hard error in files that include this header.
#pragma clang diagnostic error "-Wunguarded-availability"

#define RTLog(fmt, ...) NSLog((@"[RetroTok] " fmt), ##__VA_ARGS__)
#define RTIsPad() (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)

// The iOS 9.3 SDK puts NSURLConnection / NSURLRequest in CFNetwork, iOS 6 has them in Foundation. Looking the
// classes up by name keeps the binary free of CFNetwork class references, so dyld finds them on iOS 6.
#define RTURLRequest ((Class)NSClassFromString(@"NSMutableURLRequest"))
#define RTURLConnection ((Class)NSClassFromString(@"NSURLConnection"))

static inline void RTMain(dispatch_block_t block)
{
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

extern NSString * const RTErrorDomain;
extern NSString * const RTSettingsDidChangeNotification;
extern NSString * const RTFollowingDidChangeNotification;
extern NSString * const RTLikesDidChangeNotification;

NSError *RTMakeError(NSInteger code, NSString *message);

NSString *RTStr(id value);
NSDictionary *RTDict(id value);
NSArray *RTArr(id value);
long long RTNum(id value);
BOOL RTBool(id value);

NSString *RTShortCount(long long n);        // 1234 -> 1.2K, 96100000 -> 96.1M
NSString *RTTimeAgo(long long unixTime);    // "3d", "2w", "Jan 4"
NSString *RTURLEncode(NSString *s);
void RTAlert(NSString *title, NSString *message);
