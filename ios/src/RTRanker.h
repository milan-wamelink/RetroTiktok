#import "RTCommon.h"

// Local For You scoring: learned affinities + language settings + popularity + novelty - repetition + jitter.
@interface RTRanker : NSObject
+ (BOOL)isBlocked:(NSDictionary *)item;            // the only hard rule: a language set to Block
// recent: items shown just before (newest last), for the repetition penalty. reasons: top terms, e.g. "+0.42 tag:cars".
+ (double)scoreItem:(NSDictionary *)item recent:(NSArray *)recent reasons:(NSString **)reasons;
@end
