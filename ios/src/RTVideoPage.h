#import "RTCommon.h"

@class RTVideoPage;

@protocol RTVideoPageDelegate <NSObject>
- (void)videoPageWantsComments:(RTVideoPage *)page;
- (void)videoPageWantsProfile:(RTVideoPage *)page;
- (void)videoPageWantsShare:(RTVideoPage *)page;
- (void)videoPageWantsLike:(RTVideoPage *)page;
@end

// One full-screen page of the feed: the cover as thumbnail, then the MP4 from the local cache (downloaded
// straight from TikTok's CDN by RTVideoCache), looping.
@interface RTVideoPage : UIView
@property (nonatomic, weak) id<RTVideoPageDelegate> delegate;
@property (nonatomic, readonly) NSDictionary *item;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, readonly) BOOL active;

- (void)configureWithItem:(NSDictionary *)item;   // tears the old player down when the video changes
- (void)preload;          // download the MP4 into the cache and buffer it, without playing (the next page)
- (void)activate;         // play (preloading first when needed)
- (void)deactivate;       // pause and rewind
- (void)unload;           // drop the player, keep the cover
- (void)applySound;
- (void)updateCounts;
- (void)updateDebug;       // Settings > Player Debug overlay      // counts and the favorite heart
@end
