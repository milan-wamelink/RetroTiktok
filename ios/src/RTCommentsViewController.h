#import "RTCommon.h"

// The comments of one video, as a classic iOS 6 table. Present it inside a UINavigationController.
@interface RTCommentsViewController : UITableViewController
- (instancetype)initWithItem:(NSDictionary *)item;   // a normalized feed item
@end
