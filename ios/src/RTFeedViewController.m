#import "RTFeedViewController.h"
#import "RTAwemeAPI.h"
#import "RTVideoCache.h"
#import "RTSettings.h"
#import "RTTheme.h"
#import "RTVideoPage.h"
#import "RTProfileViewController.h"
#import "RTCommentsViewController.h"
#import "RTFavorites.h"

@interface RTFeedViewController () <UIScrollViewDelegate, RTVideoPageDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) NSArray *pages;
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, strong) NSMutableSet *itemIDs;
@property (nonatomic, assign) NSInteger current;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) BOOL visible;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIButton *emptyButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSDictionary *shareItem;
@property (nonatomic, strong) id<RTFeedSource> source;
@property (nonatomic, assign) NSInteger startIndex;
@property (nonatomic, assign) BOOL subFeed;
@property (nonatomic, assign) BOOL releasedPlayers;
@end

@implementation RTFeedViewController

- (instancetype)init
{
    if ((self = [super init])) {
        self.title = @"For You";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"For You" image:[RTTheme tabIconHome] tag:0];
        _items = [NSMutableArray array];
        _itemIDs = [NSMutableSet set];
        _source = [RTAwemeAPI shared];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(settingsChanged) name:RTSettingsDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(favoritesChanged) name:RTLikesDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(pausePlayback) name:UIApplicationWillResignActiveNotification object:nil];
        [nc addObserver:self selector:@selector(resumePlayback) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (instancetype)initWithSource:(id<RTFeedSource>)source title:(NSString *)title startIndex:(NSInteger)startIndex
{
    if ((self = [self init])) {
        self.title = title;
        _source = source;
        _startIndex = startIndex;
        _subFeed = YES;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _scroll.delegate = nil;
}

- (void)loadView
{
    UIView *root = [[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    root.backgroundColor = [RTTheme linenColor];
    self.view = root;

    self.scroll = [[UIScrollView alloc] initWithFrame:root.bounds];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scroll.pagingEnabled = YES;
    self.scroll.showsVerticalScrollIndicator = NO;
    self.scroll.scrollsToTop = NO;
    self.scroll.backgroundColor = [UIColor blackColor];
    self.scroll.delegate = self;
    self.scroll.hidden = YES;
    [root addSubview:self.scroll];

    NSMutableArray *pages = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        RTVideoPage *page = [[RTVideoPage alloc] initWithFrame:root.bounds];
        page.delegate = self;
        page.index = -1;
        [self.scroll addSubview:page];
        [pages addObject:page];
    }
    self.pages = pages;

    self.emptyView = [[UIView alloc] initWithFrame:root.bounds];
    self.emptyView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.emptyView.backgroundColor = [UIColor clearColor];
    [root addSubview:self.emptyView];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.backgroundColor = [UIColor clearColor];
    self.emptyLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    self.emptyLabel.shadowColor = [UIColor blackColor];
    self.emptyLabel.shadowOffset = CGSizeMake(0, -1);
    self.emptyLabel.font = [UIFont boldSystemFontOfSize:16];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    [self.emptyView addSubview:self.emptyLabel];

    self.emptyButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.emptyButton setBackgroundImage:[RTTheme glossyButtonWithTop:[UIColor colorWithRed:1 green:0.35 blue:0.45 alpha:1]
                                                               bottom:[RTTheme accentColor]] forState:UIControlStateNormal];
    self.emptyButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.emptyButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
    [self.emptyButton setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.4] forState:UIControlStateNormal];
    [self.emptyButton addTarget:self action:@selector(emptyButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.emptyView addSubview:self.emptyButton];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.hidesWhenStopped = YES;
    [self.emptyView addSubview:self.spinner];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (!self.subFeed)
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                               target:self action:@selector(refresh)];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    self.visible = YES;
    if (self.releasedPlayers) {
        self.releasedPlayers = NO;
        [self pageSettled];
        return;
    }
    [self protectUpcoming];
    [self resumePlayback];
}

// A profile (and its player) was pushed over this feed, or another tab (Favorites has its own player) was chosen. The A5 only renders a few AVPlayer videos at once, so a
// pushed player that has to share with our paused ones can stay black. Release ours; the files stay cached.
- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    UINavigationController *nav = self.navigationController;
    BOOL otherTab = nav.tabBarController && nav.tabBarController.selectedViewController != nav;
    if (nav && (nav.topViewController != self || otherTab)) {
        for (RTVideoPage *page in self.pages) [page unload];
        self.releasedPlayers = YES;
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    self.visible = NO;
    [self pausePlayback];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    self.emptyLabel.frame = CGRectMake(24, b.size.height / 2 - 90, b.size.width - 48, 110);
    self.emptyButton.frame = CGRectMake(b.size.width / 2 - 90, b.size.height / 2 + 30, 180, 44);
    self.spinner.center = CGPointMake(b.size.width / 2, b.size.height / 2);
    [self layoutPages:YES];
    self.scroll.contentOffset = CGPointMake(0, self.current * self.scroll.bounds.size.height);
}

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

#pragma mark Loading

- (void)showEmpty:(NSString *)text button:(NSString *)button
{
    self.emptyView.hidden = NO;
    self.scroll.hidden = YES;
    self.emptyLabel.text = text;
    self.emptyButton.hidden = button == nil;
    [self.emptyButton setTitle:button forState:UIControlStateNormal];
}

- (void)emptyButtonTapped
{
    [self refresh];
}

- (void)settingsChanged
{
    for (RTVideoPage *page in self.pages) [page applySound];
}

- (void)favoritesChanged
{
    for (RTVideoPage *page in self.pages) [page updateCounts];
}

- (void)refresh
{
    for (RTVideoPage *page in self.pages) {
        [page unload];
        page.index = -1;
    }
    [self.items removeAllObjects];
    [self.itemIDs removeAllObjects];
    self.current = 0;
    self.scroll.contentOffset = CGPointZero;
    self.loading = NO;
    self.generation++;
    [self showEmpty:@"" button:nil];
    [self.spinner startAnimating];
    [self loadMore];
}

- (void)loadMore
{
    if (self.loading) return;
    self.loading = YES;
    NSUInteger generation = self.generation;
    [self.source loadFeedRefresh:(self.items.count == 0) log:nil handler:^(NSArray *items, NSError *error) {
        if (generation != self.generation) return;
        self.loading = NO;
        [self.spinner stopAnimating];
        NSUInteger before = self.items.count;
        for (NSDictionary *item in items) {
            NSString *vid = RTStr(RTDict(item)[@"id"]);
            if (!vid.length || [self.itemIDs containsObject:vid]) continue;
            [self.itemIDs addObject:vid];
            [self.items addObject:item];
        }
        if (!self.items.count) {
            NSString *why = error.localizedDescription ?: @"TikTok sent no videos this time.";
            [self showEmpty:[NSString stringWithFormat:@"Could not load the feed.\n\n%@", why] button:@"Try Again"];
            return;
        }
        if (error) RTLog(@"loading more failed: %@", error);
        self.emptyView.hidden = YES;
        self.scroll.hidden = NO;
        if (before == 0 && self.startIndex > 0 && self.startIndex < (NSInteger)self.items.count) {
            self.current = self.startIndex;
            self.startIndex = 0;
            [self layoutPages:NO];
            self.scroll.contentOffset = CGPointMake(0, self.current * self.scroll.bounds.size.height);
        }
        [self layoutPages:NO];
        if (before == 0) [self pageSettled];
    }];
}

#pragma mark Paging

- (RTVideoPage *)pageForIndex:(NSInteger)index
{
    return self.pages[(NSUInteger)(index % 3)];
}

- (void)layoutPages:(BOOL)force
{
    CGSize size = self.scroll.bounds.size;
    if (size.height <= 0) return;
    self.scroll.contentSize = CGSizeMake(size.width, size.height * self.items.count);
    for (NSInteger i = self.current - 1; i <= self.current + 1; i++) {
        if (i < 0 || i >= (NSInteger)self.items.count) continue;
        RTVideoPage *page = [self pageForIndex:i];
        if (page.index != i || force) {
            if (page.index != i) [page deactivate];
            page.index = i;
            [page configureWithItem:self.items[(NSUInteger)i]];
            page.frame = CGRectMake(0, i * size.height, size.width, size.height);
        }
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGFloat h = scrollView.bounds.size.height;
    if (h <= 0 || !self.items.count) return;
    NSInteger index = (NSInteger)floor(scrollView.contentOffset.y / h + 0.5);
    index = MAX(0, MIN(index, (NSInteger)self.items.count - 1));
    if (index != self.current) {
        self.current = index;
        [self layoutPages:NO];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView { [self pageSettled]; }
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView { [self pageSettled]; }
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!decelerate) [self pageSettled];
}

- (void)pageSettled
{
    if (!self.items.count) return;
    [self layoutPages:NO];
    // Not on screen yet (e.g. a pushed profile player still animating in): start the current video's download
    // before the next ones, instead of waiting for viewDidAppear.
    RTVideoPage *currentPage = [self pageForIndex:self.current];
    if (!self.visible && currentPage.index == self.current) [currentPage preload];
    for (RTVideoPage *page in self.pages) {
        if (page.index == self.current) {
            if (self.visible) [page activate];
        } else if (page.index == self.current + 1) {
            [page deactivate];
            [page preload];
        } else {
            [page deactivate];
            [page unload];
        }
    }
    [self protectUpcoming];
    // The next page downloads its own video (preload above); fetch the one after that into the cache too.
    NSInteger ahead = self.current + 2;
    if (ahead < (NSInteger)self.items.count)
        [[RTVideoCache shared] fetchItem:self.items[(NSUInteger)ahead] handler:^(NSString *path, RTHTTPResponse *r, NSError *e) {}];
    if (self.current >= (NSInteger)self.items.count - 3) [self loadMore];
}

- (void)protectUpcoming
{
    NSMutableSet *keep = [NSMutableSet set];
    for (NSInteger i = self.current; i <= self.current + 2 && i < (NSInteger)self.items.count; i++)
        [keep addObject:RTStr(self.items[(NSUInteger)i][@"id"])];
    [RTVideoCache shared].protectedIDs = keep;
}

- (void)pausePlayback
{
    for (RTVideoPage *page in self.pages) if (page.active) [page deactivate];
}

- (void)resumePlayback
{
    if (!self.visible || !self.items.count || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    RTVideoPage *page = [self pageForIndex:self.current];
    if (page.index == self.current) {
        [page applySound];
        [page activate];
    }
}

#pragma mark Page actions

- (void)videoPageWantsLike:(RTVideoPage *)page
{
    if (page.item) [[RTFavorites shared] toggleItem:page.item];
}

- (void)videoPageWantsComments:(RTVideoPage *)page
{
    if (!page.item) return;
    UINavigationController *nav = [[UINavigationController alloc]
        initWithRootViewController:[[RTCommentsViewController alloc] initWithItem:page.item]];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)videoPageWantsProfile:(RTVideoPage *)page
{
    if (!page.item) return;
    NSString *secUID = RTStr(page.item[@"sec_uid"]);
    // Opened from that same profile's grid: go back to it instead of stacking another copy.
    NSArray *stack = self.navigationController.viewControllers;
    NSUInteger i = [stack indexOfObject:self];
    if (i != NSNotFound && i > 0 && [stack[i - 1] isKindOfClass:[RTProfileViewController class]]
        && [[(RTProfileViewController *)stack[i - 1] secUID] isEqualToString:secUID]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self.navigationController pushViewController:[[RTProfileViewController alloc] initWithItem:page.item] animated:YES];
}

- (void)videoPageWantsShare:(RTVideoPage *)page
{
    self.shareItem = page.item;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"Cancel"
                                         destructiveButtonTitle:nil otherButtonTitles:@"Copy Link", nil];
    sheet.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
    [sheet showFromTabBar:self.tabBarController.tabBar];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.firstOtherButtonIndex) {
        [UIPasteboard generalPasteboard].string = RTStr(self.shareItem[@"web_url"]);
    }
    self.shareItem = nil;
}

@end
