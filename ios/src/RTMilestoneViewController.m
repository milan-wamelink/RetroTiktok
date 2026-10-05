#import "RTMilestoneViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "RTHTTPClient.h"
#import "RTAwemeAPI.h"
#import "RTVideoCache.h"
#import "RTTheme.h"

static void *RTMilestoneStatusContext = &RTMilestoneStatusContext;

@interface RTMilestonePlayerView : UIView
@end
@implementation RTMilestonePlayerView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

@interface RTMilestoneViewController ()
@property (nonatomic, strong) id<RTFeedSource> source;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) RTMilestonePlayerView *playerView;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) NSMutableString *log;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *item;
@property (nonatomic, strong) NSDate *stepStart;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) NSUInteger loops;
@end

@implementation RTMilestoneViewController

- (instancetype)init
{
    if ((self = [super init])) {
        self.title = @"Pipeline Test";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Test" image:[RTTheme tabIconHome] tag:0];
        _source = [RTAwemeAPI shared];
        _log = [NSMutableString string];
    }
    return self;
}

- (void)dealloc
{
    [self stopPlayer];
}

- (void)loadView
{
    UIView *root = [[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    root.backgroundColor = [UIColor blackColor];
    self.view = root;

    self.coverView = [[UIImageView alloc] init];
    self.coverView.contentMode = UIViewContentModeScaleAspectFit;
    self.coverView.backgroundColor = [UIColor blackColor];
    [root addSubview:self.coverView];

    self.playerView = [[RTMilestonePlayerView alloc] init];
    self.playerView.backgroundColor = [UIColor clearColor];
    ((AVPlayerLayer *)self.playerView.layer).videoGravity = AVLayerVideoGravityResizeAspect;
    [root addSubview:self.playerView];

    self.logView = [[UITextView alloc] init];
    self.logView.editable = NO;
    self.logView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    self.logView.textColor = [UIColor colorWithRed:0.55 green:1 blue:0.55 alpha:1];
    self.logView.font = [UIFont fontWithName:@"Courier" size:11];
    [root addSubview:self.logView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    UIBarButtonItem *run = [[UIBarButtonItem alloc] initWithTitle:@"Run" style:UIBarButtonItemStyleBordered
                                                           target:self action:@selector(run)];
    UIBarButtonItem *copy = [[UIBarButtonItem alloc] initWithTitle:@"Copy Log" style:UIBarButtonItemStyleBordered
                                                            target:self action:@selector(copyLog)];
    self.navigationItem.rightBarButtonItems = @[ run, copy ];
    [self run];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat videoH = floorf(b.size.height * 0.55f);
    self.coverView.frame = CGRectMake(0, 0, b.size.width, videoH);
    self.playerView.frame = self.coverView.frame;
    self.logView.frame = CGRectMake(0, videoH, b.size.width, b.size.height - videoH);
}

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

#pragma mark Log

- (void)say:(NSString *)line
{
    RTLog(@"%@", line);
    [self.log appendFormat:@"%@\n", line];
    self.logView.text = self.log;
    if (self.logView.contentSize.height > self.logView.bounds.size.height)
        [self.logView setContentOffset:CGPointMake(0, self.logView.contentSize.height - self.logView.bounds.size.height) animated:NO];
}

- (void)step:(NSString *)title
{
    self.stepStart = [NSDate date];
    [self say:[NSString stringWithFormat:@"\n== %@", title]];
}

- (NSString *)elapsed { return [NSString stringWithFormat:@"%.1fs", -[self.stepStart timeIntervalSinceNow]]; }

- (void)fail:(NSString *)message
{
    [self say:[NSString stringWithFormat:@"FAILED after %@: %@", [self elapsed], message]];
    self.running = NO;
}

- (void)copyLog
{
    [UIPasteboard generalPasteboard].string = self.log;
    RTAlert(@"Log copied", @"Paste it into a message to report the result.");
}

#pragma mark Steps

- (void)run
{
    if (self.running) return;
    self.running = YES;
    [self stopPlayer];
    self.coverView.image = nil;
    [self.log setString:@""];
    UIDevice *dev = [UIDevice currentDevice];
    [self say:[NSString stringWithFormat:@"LegacyTikTok %@ - %@ iOS %@",
               [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"], dev.model, dev.systemVersion]];
    [self stepTLS];
}

// 1. TLS: handshake with the API host through mbedTLS and the bundled roots.
- (void)stepTLS
{
    [self step:@"1. TLS handshake (mbedTLS)"];
    NSInteger roots = [RTHTTPClient shared].rootCount;
    [self say:[NSString stringWithFormat:@"bundled root certificates: %ld", (long)roots]];
    if (!roots) { [self fail:@"roots.pem missing or unreadable"]; return; }
    [[RTHTTPClient shared] GET:[NSURL URLWithString:@"https://api19-core-c-useast1a.tiktokv.com/"] headers:nil
                       handler:^(RTHTTPResponse *resp, NSError *error) {
        if (error) { [self fail:error.localizedDescription]; return; }
        [self say:[NSString stringWithFormat:@"OK in %@: %@, certificate verified, HTTP %ld", [self elapsed], resp.tlsInfo, (long)resp.status]];
        [self stepFeed];
    }];
}

// 2 + 3. Feed request and JSON parsing (inside the feed source).
- (void)stepFeed
{
    [self step:[NSString stringWithFormat:@"2. Feed request + 3. JSON parse via %@", [self.source sourceName]]];
    __weak RTMilestoneViewController *weakSelf = self;
    [self.source loadFeedRefresh:YES log:^(NSString *line) { [weakSelf say:line]; } handler:^(NSArray *items, NSError *error) {
        if (error) { [self fail:error.localizedDescription]; return; }
        [self say:[NSString stringWithFormat:@"OK in %@: %lu videos", [self elapsed], (unsigned long)items.count]];
        [self stepPick:items];
    }];
}

// 4. One video: prefer a short one so the first download is small.
- (void)stepPick:(NSArray *)items
{
    [self step:@"4. Extract one video URL"];
    NSDictionary *pick = nil;
    for (NSDictionary *item in items) if (RTNum(item[@"duration"]) > 0 && RTNum(item[@"duration"]) <= 60) { pick = item; break; }
    if (!pick && items.count) pick = items[0];
    if (!pick) { [self fail:@"feed had no playable video"]; return; }
    NSArray *urls = RTArr(pick[@"video_urls"]);
    NSURL *first = urls.count ? [NSURL URLWithString:RTStr(urls[0])] : nil;
    [self say:[NSString stringWithFormat:@"@%@: %@", RTStr(pick[@"author"]), RTStr(pick[@"desc"])]];
    [self say:[NSString stringWithFormat:@"id %@, %@x%@, %llds, %lu mirrors, first host %@", pick[@"id"], pick[@"width"], pick[@"height"],
               RTNum(pick[@"duration"]), (unsigned long)urls.count, first.host]];
    NSString *cover = RTStr(pick[@"cover_url"]);
    if (cover) {
        [[RTHTTPClient shared] GET:[NSURL URLWithString:cover] headers:nil handler:^(RTHTTPResponse *resp, NSError *error) {
            UIImage *img = resp.data ? [UIImage imageWithData:resp.data] : nil;
            if (img && !self.player) self.coverView.image = img;
            [self say:img ? [NSString stringWithFormat:@"thumbnail: %.0fx%.0f JPEG, %lld bytes", img.size.width, img.size.height, resp.bytes]
                          : [NSString stringWithFormat:@"thumbnail failed: %@", error.localizedDescription ?: @"not an image"]];
        }];
    }
    [self stepDownload:pick];
}

// 5. Download from TikTok's CDN into the local cache.
- (void)stepDownload:(NSDictionary *)item
{
    [self step:@"5. Download to local cache"];
    NSString *cached = [[RTVideoCache shared] cachedPathForID:RTStr(item[@"id"])];
    if (cached) [[NSFileManager defaultManager] removeItemAtPath:cached error:NULL];
    [[RTVideoCache shared] fetchItem:item handler:^(NSString *path, RTHTTPResponse *resp, NSError *error) {
        if (error) { [self fail:error.localizedDescription]; return; }
        double secs = MAX(resp.duration, 0.01);
        [self say:[NSString stringWithFormat:@"OK in %@: %.2f MB from %@ (%@), %.0f KB/s, %ld redirects",
                   [self elapsed], resp.bytes / 1048576.0, [NSURL URLWithString:resp.finalURL].host, resp.tlsInfo,
                   resp.bytes / 1024.0 / secs, (long)resp.redirects]];
        [self say:[NSString stringWithFormat:@"file: %@", path]];
        [self stepPlay:path];
    }];
}

// 6. AVPlayer from the cached file, looping.
- (void)stepPlay:(NSString *)path
{
    [self step:@"6. AVPlayer playback (local file, loop)"];
    self.loops = 0;
    self.item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
    [self.item addObserver:self forKeyPath:@"status" options:0 context:RTMilestoneStatusContext];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
    self.player = [AVPlayer playerWithPlayerItem:self.item];
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    ((AVPlayerLayer *)self.playerView.layer).player = self.player;
    [self.player play];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != RTMilestoneStatusContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    RTMain(^{
        if (object != self.item) return;
        if (self.item.status == AVPlayerItemStatusReadyToPlay) {
            CGSize size = CGSizeZero;
            NSArray *tracks = [self.item.asset tracksWithMediaType:AVMediaTypeVideo];
            if (tracks.count) size = [tracks[0] naturalSize];
            [self say:[NSString stringWithFormat:@"OK in %@: playing %.0fx%.0f, %.1fs long", [self elapsed], size.width, size.height,
                       CMTimeGetSeconds(self.item.asset.duration)]];
            self.coverView.image = nil;
            self.running = NO;
        } else if (self.item.status == AVPlayerItemStatusFailed) {
            [self fail:[NSString stringWithFormat:@"AVPlayer: %@", self.item.error.localizedDescription]];
        }
    });
}

- (void)didReachEnd:(NSNotification *)note
{
    [self.item seekToTime:kCMTimeZero];
    [self.player play];
    if (++self.loops == 1) [self say:@"looped back to the start - milestone 1 complete"];
}

- (void)stopPlayer
{
    [self.player pause];
    if (self.item) {
        [self.item removeObserver:self forKeyPath:@"status" context:RTMilestoneStatusContext];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
    }
    ((AVPlayerLayer *)self.playerView.layer).player = nil;
    self.player = nil;
    self.item = nil;
}

@end
