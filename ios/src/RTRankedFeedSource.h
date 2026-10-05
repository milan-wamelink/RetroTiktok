#import "RTFeedSource.h"

// The For You source with local recommendations: keeps a pool of unseen aweme feed videos, hands the player the best
// few by RTRanker (with some exploration), and learns from what was watched. Personalization off = TikTok's order.
@interface RTRankedFeedSource : NSObject <RTFeedSource, RTFeedLearning>
+ (instancetype)shared;
@end
