#import "RTCommon.h"

// A creator's profile (or a hashtag's videos): header (avatar, name, counts, bio) and a 3-column grid of their videos. Tapping a video opens
// them in an RTFeedViewController, for which this screen is the RTFeedSource (so both share one list and its paging).
@interface RTProfileViewController : UITableViewController
- (instancetype)initWithItem:(NSDictionary *)item;   // a normalized feed item; needs sec_uid
- (instancetype)initWithHashtag:(NSDictionary *)tag;  // V4: a hashtag from RTAwemeAPI lookupHashtag, same grid + player
@property (nonatomic, readonly) NSString *secUID;
@end
