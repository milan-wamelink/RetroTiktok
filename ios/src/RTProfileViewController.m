#import "RTProfileViewController.h"
#import "RTAwemeAPI.h"
#import "RTFeedViewController.h"
#import "RTImageLoader.h"
#import "RTTheme.h"

static const CGFloat kRTGridGap = 1;

@interface RTGridTile : UIButton
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *plays;
@end

@implementation RTGridTile
@end

@interface RTGridCell : UITableViewCell
@property (nonatomic, strong) NSArray *tiles;   // RTGridTile; tile.tag = item index
@end

@implementation RTGridCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        NSMutableArray *tiles = [NSMutableArray array];
        for (int i = 0; i < 3; i++) {
            RTGridTile *b = [RTGridTile buttonWithType:UIButtonTypeCustom];
            b.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
            b.clipsToBounds = YES;
            b.cover = [[UIImageView alloc] init];
            b.cover.contentMode = UIViewContentModeScaleAspectFill;
            b.cover.clipsToBounds = YES;
            b.cover.userInteractionEnabled = NO;
            [b addSubview:b.cover];
            b.plays = [[UILabel alloc] init];
            b.plays.backgroundColor = [UIColor clearColor];
            b.plays.textColor = [UIColor whiteColor];
            b.plays.shadowColor = [UIColor colorWithWhite:0 alpha:0.8];
            b.plays.shadowOffset = CGSizeMake(0, 1);
            b.plays.font = [UIFont boldSystemFontOfSize:11];
            b.plays.userInteractionEnabled = NO;
            [b addSubview:b.plays];
            [self.contentView addSubview:b];
            [tiles addObject:b];
        }
        _tiles = tiles;
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat side = floor((self.contentView.bounds.size.width - 2 * kRTGridGap) / 3);
    for (NSUInteger i = 0; i < self.tiles.count; i++) {
        RTGridTile *b = self.tiles[i];
        b.frame = CGRectMake(i * (side + kRTGridGap), 0, side, side);
        b.cover.frame = b.bounds;
        b.plays.frame = CGRectMake(5, side - 19, side - 10, 16);
    }
}

@end

@interface RTProfileViewController () <RTFeedSource>
@property (nonatomic, copy) NSDictionary *seed;
@property (nonatomic, strong) NSDictionary *profile;
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, strong) NSMutableSet *itemIDs;
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, strong) NSError *lastError;
@property (nonatomic, strong) NSMutableArray *feedHandlers;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *userLabel;
@property (nonatomic, strong) UILabel *bioLabel;
@property (nonatomic, strong) NSArray *statLabels;
@property (nonatomic, strong) UIView *footer;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *footerLabel;
@end

@implementation RTProfileViewController

- (instancetype)initWithItem:(NSDictionary *)item
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _seed = [item copy];
        _items = [NSMutableArray array];
        _itemIDs = [NSMutableSet set];
        self.title = [@"@" stringByAppendingString:RTStr(item[@"author"]) ?: @""];
    }
    return self;
}

- (NSString *)secUID { return RTStr(self.seed[@"sec_uid"]); }

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self buildHeader];
    [self buildFooter];
    [self updateHeader];
    [self loadMore];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
}

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

#pragma mark Header / footer

static UILabel *RTHeaderLabel(CGFloat size, BOOL bold, UIColor *color)
{
    UILabel *l = [[UILabel alloc] init];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = color;
    l.shadowColor = [UIColor colorWithWhite:0 alpha:0.7];
    l.shadowOffset = CGSizeMake(0, -1);
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.textAlignment = NSTextAlignmentCenter;
    return l;
}

- (void)buildHeader
{
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 220)];
    h.backgroundColor = [RTTheme linenColor];

    self.avatarView = [[UIImageView alloc] init];
    self.avatarView.layer.cornerRadius = 42;
    self.avatarView.layer.masksToBounds = YES;
    self.avatarView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.avatarView.layer.borderWidth = 3;
    self.avatarView.layer.shouldRasterize = YES;
    self.avatarView.layer.rasterizationScale = [UIScreen mainScreen].scale;
    [h addSubview:self.avatarView];

    self.nameLabel = RTHeaderLabel(18, YES, [UIColor whiteColor]);
    self.userLabel = RTHeaderLabel(13, NO, [UIColor colorWithWhite:0.8 alpha:1]);
    self.bioLabel = RTHeaderLabel(13, NO, [UIColor colorWithWhite:0.92 alpha:1]);
    self.bioLabel.numberOfLines = 0;
    [h addSubview:self.nameLabel];
    [h addSubview:self.userLabel];
    [h addSubview:self.bioLabel];

    NSMutableArray *stats = [NSMutableArray array];
    for (NSString *caption in @[ @"Following", @"Followers", @"Likes" ]) {
        UILabel *value = RTHeaderLabel(17, YES, [UIColor whiteColor]);
        UILabel *cap = RTHeaderLabel(11, NO, [UIColor colorWithWhite:0.75 alpha:1]);
        cap.text = caption;
        value.tag = 1;
        UIView *box = [[UIView alloc] init];
        box.backgroundColor = [UIColor clearColor];
        [box addSubview:value];
        [box addSubview:cap];
        cap.tag = 2;
        [h addSubview:box];
        [stats addObject:box];
    }
    self.statLabels = stats;
    self.header = h;
}

- (void)updateHeader
{
    NSDictionary *p = self.profile ?: self.seed;
    CGFloat w = self.tableView.bounds.size.width;
    [[RTImageLoader shared] loadPath:RTStr(p[@"avatar_url"]) into:self.avatarView placeholder:[RTTheme avatarPlaceholder]];
    NSString *nick = RTStr(p[@"nickname"]);
    self.nameLabel.text = nick.length ? nick : RTStr(p[@"author"]);
    self.userLabel.text = [@"@" stringByAppendingString:RTStr(p[@"author"]) ?: @""];
    NSArray *values = @[ p[@"following"] ?: @0, p[@"followers"] ?: @0, p[@"hearts"] ?: @0 ];
    for (NSUInteger i = 0; i < 3; i++) {
        UILabel *v = (UILabel *)[self.statLabels[i] viewWithTag:1];
        v.text = self.profile ? RTShortCount(RTNum(values[i])) : @"-";
    }
    self.bioLabel.text = self.profile ? RTStr(self.profile[@"signature"]) : @"";

    self.avatarView.frame = CGRectMake(floor(w / 2 - 42), 16, 84, 84);
    self.nameLabel.frame = CGRectMake(10, 108, w - 20, 22);
    self.userLabel.frame = CGRectMake(10, 130, w - 20, 18);
    CGFloat colW = floor((w - 20) / 3);
    for (NSUInteger i = 0; i < 3; i++) {
        UIView *box = self.statLabels[i];
        box.frame = CGRectMake(10 + i * colW, 156, colW, 40);
        [box viewWithTag:1].frame = CGRectMake(0, 0, colW, 22);
        [box viewWithTag:2].frame = CGRectMake(0, 22, colW, 16);
    }
    CGFloat bioH = 0;
    if (self.bioLabel.text.length) {
        bioH = ceil([self.bioLabel.text sizeWithFont:self.bioLabel.font constrainedToSize:CGSizeMake(w - 40, 120)
                                       lineBreakMode:NSLineBreakByWordWrapping].height);
    }
    self.bioLabel.frame = CGRectMake(20, 204, w - 40, bioH);
    CGRect f = self.header.frame;
    f.size.height = 204 + bioH + (bioH ? 14 : 4);
    self.header.frame = f;
    self.tableView.tableHeaderView = self.header;   // re-set so the table picks up the new height
}

- (void)buildFooter
{
    UIView *f = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 70)];
    f.backgroundColor = [UIColor clearColor];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.center = CGPointMake(f.bounds.size.width / 2, 35);
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [f addSubview:self.spinner];
    self.footerLabel = RTHeaderLabel(13, NO, [UIColor colorWithWhite:0.7 alpha:1]);
    self.footerLabel.numberOfLines = 2;
    self.footerLabel.frame = CGRectInset(f.bounds, 16, 8);
    self.footerLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [f addSubview:self.footerLabel];
    [f addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(footerTapped)]];
    self.footer = f;
    self.tableView.tableFooterView = f;
}

- (void)updateFooter
{
    if (self.loading) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
    if (self.loading) self.footerLabel.text = @"";
    else if (self.lastError) self.footerLabel.text = @"Could not load videos. Tap to try again.";
    else if (self.finished && !self.items.count) self.footerLabel.text = @"No public videos.";
    else self.footerLabel.text = @"";
}

- (void)footerTapped
{
    if (self.lastError) [self loadMore];
}

#pragma mark Loading

- (void)loadMore
{
    if (self.loading || self.finished) return;
    self.loading = YES;
    self.lastError = nil;
    [self updateFooter];
    [[RTAwemeAPI shared] loadProfileVideos:self.secUID cursor:self.cursor log:nil
                                   handler:^(NSDictionary *profile, NSArray *items, NSString *next, NSError *error) {
        self.loading = NO;
        NSMutableArray *added = [NSMutableArray array];
        if (error) {
            RTLog(@"profile videos failed: %@", error.localizedDescription);
            self.lastError = error;
        } else {
            if (profile && !self.profile) {
                self.profile = profile;
                [self updateHeader];
            }
            for (NSDictionary *item in items) {
                NSString *vid = RTStr(item[@"id"]);
                if (!vid.length || [self.itemIDs containsObject:vid]) continue;
                [self.itemIDs addObject:vid];
                [self.items addObject:item];
                [added addObject:item];
            }
            self.cursor = next;
            self.finished = next == nil;
            [self.tableView reloadData];
        }
        [self updateFooter];
        NSArray *waiting = self.feedHandlers;
        self.feedHandlers = nil;
        for (RTFeedHandler h in waiting) h(added, error);
        // a page of only photo posts (skipped) adds nothing: go on to the next one
        if (!error && !added.count && !self.finished)
            dispatch_async(dispatch_get_main_queue(), ^{ [self loadMore]; });
    }];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGFloat h = scrollView.bounds.size.height;
    if (scrollView.contentOffset.y + h > scrollView.contentSize.height - h) [self loadMore];
}

#pragma mark RTFeedSource (for the player opened from the grid)

- (NSString *)sourceName { return @"TikTok web creator/item_list (direct)"; }

- (void)loadFeedRefresh:(BOOL)refresh log:(RTFeedLog)log handler:(RTFeedHandler)handler
{
    if ((refresh && self.items.count) || self.finished) {
        NSArray *list = refresh ? [self.items copy] : @[];
        dispatch_async(dispatch_get_main_queue(), ^{ handler(list, nil); });
        return;
    }
    if (!self.feedHandlers) self.feedHandlers = [NSMutableArray array];
    [self.feedHandlers addObject:[handler copy]];
    [self loadMore];
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)((self.items.count + 2) / 3);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return floor((tableView.bounds.size.width - 2 * kRTGridGap) / 3) + kRTGridGap;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    RTGridCell *cell = [tableView dequeueReusableCellWithIdentifier:@"grid"];
    if (!cell) cell = [[RTGridCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"grid"];
    for (NSUInteger col = 0; col < 3; col++) {
        RTGridTile *tile = cell.tiles[col];
        NSUInteger idx = (NSUInteger)indexPath.row * 3 + col;
        tile.hidden = idx >= self.items.count;
        if (tile.hidden) continue;
        NSDictionary *item = self.items[idx];
        tile.tag = (NSInteger)idx;
        [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [[RTImageLoader shared] loadPath:RTStr(item[@"thumb_url"]) into:tile.cover placeholder:nil];
        tile.plays.text = [@"\u25B8 " stringByAppendingString:RTShortCount(RTNum(item[@"plays"]))];
    }
    return cell;
}

- (void)tileTapped:(UIButton *)sender
{
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.items.count) return;
    RTFeedViewController *feed = [[RTFeedViewController alloc] initWithSource:self title:self.title startIndex:sender.tag];
    [self.navigationController pushViewController:feed animated:YES];
}

@end
