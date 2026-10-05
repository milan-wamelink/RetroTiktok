#import "RTCommon.h"

// V3 local favorites. Only the item details are kept (a few KB each, in Library/<bundle id>/favorites.plist), never
// the video: playing a favorite downloads it again through RTVideoCache. Posts RTLikesDidChangeNotification on change.
@interface RTFavorites : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray *items;     // newest first
- (BOOL)containsID:(NSString *)videoID;
- (BOOL)toggleItem:(NSDictionary *)item;            // returns YES when the item is now a favorite
- (void)removeID:(NSString *)videoID;
@end
