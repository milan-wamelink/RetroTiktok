#import "RTFavoritesViewController.h"
#import "RTFavorites.h"
#import "RTFeedSource.h"
#import "RTFeedViewController.h"
#import "RTAwemeAPI.h"
#import "RTVideoCache.h"
#import "RTImageLoader.h"
#import "RTTheme.h"

static const NSUInteger kRTFavoritesPage = 4;

// Feeds the player the favorites from the tapped one on. Saved CDN links expire, so each page first asks TikTok for
// fresh links (one request per video, in parallel); videos still in the cache and failed lookups keep their saved item.
@interface RTFavoritesSource : NSObject <RTFeedSource>
- (instancetype)initWithItems:(NSArray *)items;
@end

@implementation RTFavoritesSource {
    NSArray *_items;
    NSUInteger _next;
}

- (instancetype)initWithItems:(NSArray *)items
{
    if ((self = [super init])) _items = [items copy];
    return self;
}

- (NSString *)sourceName { return @"Favorites"; }

- (void)loadFeedRefresh:(BOOL)refresh log:(RTFeedLog)log handler:(RTFeedHandler)handler
{
    if (refresh) _next = 0;
    NSUInteger start = _next, end = MIN(start + kRTFavoritesPage, _items.count);
    _next = MAX(start, end);
    if (start >= end) {
        dispatch_async(dispatch_get_main_queue(), ^{ handler(@[], nil); });
        return;
    }
    NSMutableArray *batch = [[_items subarrayWithRange:NSMakeRange(start, end - start)] mutableCopy];
    dispatch_group_t group = dispatch_group_create();
    for (NSUInteger i = 0; i < batch.count; i++) {
        NSDictionary *item = batch[i];
        if ([[RTVideoCache shared] cachedPathForID:RTStr(item[@"id"])]) continue;
        dispatch_group_enter(group);
        [[RTAwemeAPI shared] refreshItem:item handler:^(NSDictionary *fresh, NSError *error) {
            if (fresh) batch[i] = fresh;
            else RTLog(@"favorite %@ keeps its saved links: %@", RTStr(item[@"id"]), error.localizedDescription);
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{ handler(batch, nil); });
}

@end

@interface RTFavoriteCell : UITableViewCell
@end

@implementation RTFavoriteCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier])) {
        self.imageView.contentMode = UIViewContentModeScaleAspectFill;
        self.imageView.clipsToBounds = YES;
        self.imageView.backgroundColor = [UIColor blackColor];
        self.textLabel.font = [UIFont boldSystemFontOfSize:15];
        self.detailTextLabel.font = [UIFont systemFontOfSize:12];
        self.detailTextLabel.numberOfLines = 2;
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat h = self.contentView.bounds.size.height;
    self.imageView.frame = CGRectMake(6, 4, roundf((h - 8) * 0.75f), h - 8);
    CGFloat x = CGRectGetMaxX(self.imageView.frame) + 10, w = self.contentView.bounds.size.width - x - 4;
    self.textLabel.frame = CGRectMake(x, 10, w, 20);
    self.detailTextLabel.frame = CGRectMake(x, 31, w, h - 38);
}

@end

@interface RTFavoritesViewController ()
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIImage *placeholder;
@property (nonatomic, assign) BOOL editingList;
@end

@implementation RTFavoritesViewController

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Favorites";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Favorites" image:[RTTheme tabIconFavorites] tag:1];
        _items = [RTFavorites shared].items;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(favoritesChanged)
                                                     name:RTLikesDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.rowHeight = 80;
    self.tableView.tableFooterView = [[UIView alloc] init];
    self.navigationItem.rightBarButtonItem = self.editButtonItem;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(54, 72), YES, 1);
    [[UIColor blackColor] setFill];
    UIRectFill(CGRectMake(0, 0, 54, 72));
    self.placeholder = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.text = @"No favorites yet.\n\nTap the heart on a video to save it here. Only the details are kept on "
                            "the phone; the video is downloaded again when you play it.";
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1];
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.backgroundColor = [UIColor clearColor];
    self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIView *background = [[UIView alloc] initWithFrame:self.tableView.bounds];
    self.emptyLabel.frame = CGRectInset(background.bounds, 30, 0);
    [background addSubview:self.emptyLabel];
    self.tableView.backgroundView = background;
    [self updateEmpty];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
}

- (void)updateEmpty
{
    self.emptyLabel.hidden = self.items.count > 0;
    self.navigationItem.rightBarButtonItem.enabled = self.items.count > 0 || self.editing;
}

- (void)favoritesChanged
{
    if (self.editingList) return;
    self.items = [RTFavorites shared].items;
    if (self.isViewLoaded) {
        [self.tableView reloadData];
        [self updateEmpty];
    }
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    RTFavoriteCell *cell = [tableView dequeueReusableCellWithIdentifier:@"fav"];
    if (!cell) cell = [[RTFavoriteCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"fav"];
    NSDictionary *item = self.items[(NSUInteger)indexPath.row];
    NSString *nick = RTStr(item[@"nickname"]), *user = RTStr(item[@"author"]);
    cell.textLabel.text = nick.length ? nick : [@"@" stringByAppendingString:user ?: @""];
    NSString *desc = RTStr(item[@"desc"]);
    cell.detailTextLabel.text = desc.length ? [NSString stringWithFormat:@"@%@ - %@", user ?: @"", desc]
                                            : [@"@" stringByAppendingString:user ?: @""];
    NSString *thumb = RTStr(item[@"thumb_url"]).length ? RTStr(item[@"thumb_url"]) : RTStr(item[@"cover_url"]);
    [[RTImageLoader shared] loadPath:thumb into:cell.imageView placeholder:self.placeholder];
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
                                            forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.row >= (NSInteger)self.items.count) return;
    NSString *vid = RTStr(self.items[(NSUInteger)indexPath.row][@"id"]);
    self.editingList = YES;
    [[RTFavorites shared] removeID:vid];
    self.editingList = NO;
    self.items = [RTFavorites shared].items;
    [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationFade];
    [self updateEmpty];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSUInteger row = (NSUInteger)indexPath.row;
    if (row >= self.items.count) return;
    NSArray *from = [self.items subarrayWithRange:NSMakeRange(row, self.items.count - row)];
    RTFeedViewController *player = [[RTFeedViewController alloc] initWithSource:[[RTFavoritesSource alloc] initWithItems:from]
                                                                          title:@"Favorites" startIndex:0];
    [self.navigationController pushViewController:player animated:YES];
}

@end
