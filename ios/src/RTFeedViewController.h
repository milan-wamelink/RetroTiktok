#import "RTCommon.h"

// The For You feed: a vertical, paging scroll view with three recycled video pages.
@protocol RTFeedSource;

@interface RTFeedViewController : UIViewController
// A pushed player over another list (a profile's videos), opening at startIndex. The plain init is the For You feed.
- (instancetype)initWithSource:(id<RTFeedSource>)source title:(NSString *)title startIndex:(NSInteger)startIndex;
- (void)pausePlayback;
- (void)resumePlayback;
@end
