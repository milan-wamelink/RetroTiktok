#import "RTFeedViewController.h"
#import "RTAPI.h"
#import "RTSettings.h"
#import "RTTheme.h"
#import "RTVideoPage.h"

@interface RTFeedViewController () <UIScrollViewDelegate, RTVideoPageDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) NSArray *pages;
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, strong) NSMutableSet *itemIDs;
@property (nonatomic, assign) NSInteger current;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL visible;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIButton *emptyButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSDictionary *shareItem;
@end

@implementation RTFeedViewController

- (instancetype)init
{
    if ((self = [super init])) {
        self.title = @"For You";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"For You" image:[RTTheme tabIconHome] tag:0];
        _items = [NSMutableArray array];
        _itemIDs = [NSMutableSet set];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(settingsChanged) name:RTSettingsDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(pausePlayback) name:UIApplicationWillResignActiveNotification object:nil];
        [nc addObserver:self selector:@selector(resumePlayback) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
    [self resumePlayback];
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
    if (![[RTAPI shared] hasServer]) self.tabBarController.selectedIndex = 1;
    else [self refresh];
}

- (void)settingsChanged
{
    if (!self.isViewLoaded) return;
    [self refresh];
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

    if (![[RTAPI shared] hasServer]) {
        [self showEmpty:@"RetroTok needs its server.\n\nStart it on your computer, then enter its address in Settings." button:@"Settings"];
        return;
    }
    [self showEmpty:@"" button:nil];
    [self.spinner startAnimating];
    [self loadMore];
}

- (void)loadMore
{
    if (self.loading) return;
    self.loading = YES;
    [[RTAPI shared] forYou:^(id json, NSError *error) {
        self.loading = NO;
        [self.spinner stopAnimating];
        NSUInteger before = self.items.count;
        for (NSDictionary *item in RTArr(RTDict(json)[@"items"])) {
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
    NSMutableArray *ahead = [NSMutableArray array];
    for (NSInteger i = self.current + 2; i < (NSInteger)self.items.count && i <= self.current + 3; i++)
        [ahead addObject:RTStr(self.items[(NSUInteger)i][@"id"])];
    if (ahead.count) [[RTAPI shared] prefetchVideos:ahead];
    if (self.current >= (NSInteger)self.items.count - 3) [self loadMore];
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
    RTAlert(@"Likes", @"Likes and favorites arrive in version 3.");
}

- (void)videoPageWantsComments:(RTVideoPage *)page
{
    RTAlert(@"Comments", @"Comments arrive in version 2.");
}

- (void)videoPageWantsProfile:(RTVideoPage *)page
{
    RTAlert([@"@" stringByAppendingString:RTStr(page.item[@"author"])], @"Profiles arrive in version 2.");
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
