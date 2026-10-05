#import "RTCommon.h"

// What the local For You ranking has learned: an affinity in -1...+1 per feature ("tag:cars", "lang:es", ...),
// the IDs already shown, and a short watch history. Main thread only; saved to Library/<bundle id>/interests.plist.
@interface RTInterestProfile : NSObject
+ (instancetype)shared;
- (double)affinity:(NSString *)feature known:(BOOL *)known;    // decayed toward 0 over time; 0 when never seen
- (void)learnItem:(NSDictionary *)item reward:(double)reward;  // nudges every feature of the item toward reward
- (BOOL)hasSeen:(NSString *)videoID;
- (void)recordView:(NSDictionary *)item fraction:(double)fraction;
@property (nonatomic, readonly) NSUInteger featureCount;
@property (nonatomic, readonly) NSUInteger viewCount;
- (void)reset;
@end
