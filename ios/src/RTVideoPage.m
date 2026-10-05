#import "RTVideoPage.h"
#import "RTFavorites.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import "RTVideoCache.h"
#import "RTImageLoader.h"
#import "RTSettings.h"
#import "RTTheme.h"

static void *RTItemStatusContext = &RTItemStatusContext;
static NSInteger RTLivePlayers;

@interface RTPlayerView : UIView
@end

@implementation RTPlayerView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

@interface RTVideoPage ()
@property (nonatomic, strong, readwrite) NSDictionary *item;
@property (nonatomic, assign, readwrite) BOOL active;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) BOOL preparing;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *playerItem;

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) RTPlayerView *playerView;
@property (nonatomic, strong) UILabel *debugLabel;
@property (nonatomic, strong) NSDate *attachedAt;
@property (nonatomic, strong) NSDate *readyAt;
@property (nonatomic, strong) NSDate *displayAt;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIImageView *playIcon;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIImageView *shade;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIImageView *noteView;
@property (nonatomic, strong) UILabel *musicLabel;
@property (nonatomic, strong) UIButton *avatarButton;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIButton *likeButton;
@property (nonatomic, strong) UIButton *commentButton;
@property (nonatomic, strong) UIButton *shareButton;
@property (nonatomic, strong) UILabel *likeLabel;
@property (nonatomic, strong) UILabel *commentLabel;
@property (nonatomic, strong) UILabel *shareLabel;
@end

@implementation RTVideoPage

static UILabel *RTOverlayLabel(CGFloat size, BOOL bold)
{
    UILabel *l = [[UILabel alloc] init];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [UIColor whiteColor];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.shadowColor = [UIColor colorWithWhite:0 alpha:0.75];
    l.shadowOffset = CGSizeMake(0, 1);
    return l;
}

- (UIButton *)iconButton:(UIImage *)image action:(SEL)action
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:image forState:UIControlStateNormal];
    b.showsTouchWhenHighlighted = YES;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    return b;
}

- (UILabel *)countLabel
{
    UILabel *l = RTOverlayLabel(12, YES);
    l.textAlignment = NSTextAlignmentCenter;
    [self addSubview:l];
    return l;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor blackColor];
        self.clipsToBounds = YES;
        // Show the whole frame (black bars where the aspect differs) instead of cropping to fill the screen.
        UIViewContentMode mode = UIViewContentModeScaleAspectFit;

        _coverView = [[UIImageView alloc] init];
        _coverView.contentMode = mode;
        _coverView.clipsToBounds = YES;
        [self addSubview:_coverView];

        _playerView = [[RTPlayerView alloc] init];
        _playerView.backgroundColor = [UIColor clearColor];
        _playerView.userInteractionEnabled = NO;
        ((AVPlayerLayer *)_playerView.layer).videoGravity = AVLayerVideoGravityResizeAspect;
        _playerView.alpha = 0;
        [self addSubview:_playerView];

        _shade = [[UIImageView alloc] initWithImage:[RTTheme bottomShadeImage]];
        [self addSubview:_shade];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];

        _playIcon = [[UIImageView alloc] initWithImage:[RTTheme bigPlayIcon]];
        _playIcon.hidden = YES;
        [self addSubview:_playIcon];

        _messageLabel = RTOverlayLabel(15, YES);
        _messageLabel.textAlignment = NSTextAlignmentCenter;
        _messageLabel.numberOfLines = 0;
        _messageLabel.hidden = YES;
        [self addSubview:_messageLabel];

        _authorLabel = RTOverlayLabel(16, YES);
        [self addSubview:_authorLabel];
        _captionLabel = RTOverlayLabel(14, NO);
        _captionLabel.numberOfLines = 3;
        [self addSubview:_captionLabel];
        _noteView = [[UIImageView alloc] initWithImage:[RTTheme musicNoteIcon]];
        [self addSubview:_noteView];
        _musicLabel = RTOverlayLabel(13, NO);
        [self addSubview:_musicLabel];

        _avatarButton = [self iconButton:nil action:@selector(profileTapped)];
        _avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(2, 2, 44, 44)];
        _avatarView.layer.cornerRadius = 22;
        _avatarView.layer.masksToBounds = YES;
        _avatarView.layer.borderColor = [UIColor whiteColor].CGColor;
        _avatarView.layer.borderWidth = 2;
        // a masked, rounded layer is re-rendered offscreen every frame while scrolling; cache it as a bitmap instead
        _avatarView.layer.shouldRasterize = YES;
        _avatarView.layer.rasterizationScale = [UIScreen mainScreen].scale;
        _avatarView.userInteractionEnabled = NO;
        [_avatarButton addSubview:_avatarView];

        _likeButton = [self iconButton:[RTTheme heartIconFilled:NO] action:@selector(likeTapped)];
        _commentButton = [self iconButton:[RTTheme commentIcon] action:@selector(commentsTapped)];
        _shareButton = [self iconButton:[RTTheme shareIcon] action:@selector(shareTapped)];
        _likeLabel = [self countLabel];
        _commentLabel = [self countLabel];
        _shareLabel = [self countLabel];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)dealloc
{
    [self unload];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat w = b.size.width, h = b.size.height;
    self.coverView.frame = b;
    self.playerView.frame = b;
    self.shade.frame = CGRectMake(0, h - 170, w, 170);
    self.spinner.center = CGPointMake(w / 2, h / 2);
    self.playIcon.center = CGPointMake(w / 2, h / 2);
    self.messageLabel.frame = CGRectMake(30, h / 2 - 60, w - 60, 120);

    CGFloat colX = w - 58;
    CGFloat y = h - 64;
    self.shareLabel.frame = CGRectMake(colX - 4, y + 36, 64, 16);
    self.shareButton.frame = CGRectMake(colX, y - 8, 56, 48);
    y -= 66;
    self.commentLabel.frame = CGRectMake(colX - 4, y + 36, 64, 16);
    self.commentButton.frame = CGRectMake(colX, y - 8, 56, 48);
    y -= 66;
    self.likeLabel.frame = CGRectMake(colX - 4, y + 36, 64, 16);
    self.likeButton.frame = CGRectMake(colX, y - 8, 56, 48);
    y -= 64;
    self.avatarButton.frame = CGRectMake(colX + 4, y, 48, 48);

    CGFloat textW = w - 84;
    self.noteView.frame = CGRectMake(10, h - 24, 14, 14);
    self.musicLabel.frame = CGRectMake(28, h - 27, textW - 18, 18);
    CGSize cap = [self.captionLabel.text sizeWithFont:self.captionLabel.font
                                    constrainedToSize:CGSizeMake(textW, 54)
                                        lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat capH = self.captionLabel.text.length ? ceilf(cap.height) : 0;
    self.captionLabel.frame = CGRectMake(10, h - 32 - capH, textW, capH);
    self.authorLabel.frame = CGRectMake(10, h - 34 - capH - 22, textW, 20);
}

#pragma mark Content

- (void)configureWithItem:(NSDictionary *)item
{
    if (self.item && [RTStr(self.item[@"id"]) isEqualToString:RTStr(item[@"id"])]) {
        self.item = item;
        [self updateCounts];
        return;
    }
    [self unload];
    self.item = item;
    self.coverView.image = nil;
    [[RTImageLoader shared] loadPath:RTStr(item[@"cover_url"]) into:self.coverView placeholder:nil];
    [[RTImageLoader shared] loadPath:RTStr(item[@"avatar_url"]) into:self.avatarView placeholder:[RTTheme avatarPlaceholder]];

    self.authorLabel.text = [@"@" stringByAppendingString:RTStr(item[@"author"])];
    self.captionLabel.text = RTStr(item[@"desc"]);
    NSString *music = RTStr(item[@"music"]);
    NSString *musicAuthor = RTStr(item[@"music_author"]);
    if (musicAuthor.length && music.length) music = [NSString stringWithFormat:@"%@ - %@", music, musicAuthor];
    self.musicLabel.text = music.length ? music : @"original sound";
    [self updateCounts];
    [self setNeedsLayout];
}

- (void)updateCounts
{
    BOOL liked = [[RTFavorites shared] containsID:RTStr(self.item[@"id"])];
    [self.likeButton setImage:[RTTheme heartIconFilled:liked] forState:UIControlStateNormal];
    self.likeLabel.text = RTShortCount(RTNum(self.item[@"likes"]));
    self.commentLabel.text = RTShortCount(RTNum(self.item[@"comments"]));
    self.shareLabel.text = RTShortCount(RTNum(self.item[@"shares"]));
}

- (void)showMessage:(NSString *)message
{
    self.messageLabel.text = message;
    self.messageLabel.hidden = message.length == 0;
}

#pragma mark Playback

- (void)preload
{
    if (self.player || self.preparing || !self.item) return;
    self.preparing = YES;
    [self showMessage:nil];
    if (self.active) [self.spinner startAnimating];
    NSUInteger generation = ++self.generation;
    __weak RTVideoPage *weakSelf = self;
    [[RTVideoCache shared] fetchItem:self.item handler:^(NSString *path, RTHTTPResponse *response, NSError *error) {
        RTVideoPage *page = weakSelf;
        if (!page || page.generation != generation) return;
        if (error || !path.length) {
            page.preparing = NO;
            [page.spinner stopAnimating];
            [page showMessage:[NSString stringWithFormat:@"%@\n\nTap to try again.", error.localizedDescription ?: @"This video could not be downloaded."]];
            return;
        }
        [page startPlayerWithURL:[NSURL fileURLWithPath:path]];
    }];
}

// Loading the asset's tracks synchronously (what AVPlayerItem / tracksWithMediaType: do) blocks the main thread for
// a noticeable moment on an A5, which shows up as a hitch mid-swipe. Load them in the background first.
- (void)startPlayerWithURL:(NSURL *)url
{
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    NSUInteger generation = self.generation;
    __weak RTVideoPage *weakSelf = self;
    [asset loadValuesAsynchronouslyForKeys:@[ @"tracks", @"playable" ] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            RTVideoPage *page = weakSelf;
            if (!page || page.generation != generation || page.player) return;
            page.preparing = NO;
            if ([asset statusOfValueForKey:@"tracks" error:NULL] != AVKeyValueStatusLoaded || !asset.playable) {
                [page.spinner stopAnimating];
                [page showMessage:@"This video will not play.\n\nTap to try again."];
                return;
            }
            [page attachPlayerForAsset:asset];
        });
    }];
}

- (void)attachPlayerForAsset:(AVAsset *)asset
{
    self.playerItem = [AVPlayerItem playerItemWithAsset:asset];
    [self.playerItem addObserver:self forKeyPath:@"status" options:0 context:RTItemStatusContext];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
    self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
    RTLivePlayers++;
    self.attachedAt = [NSDate date];
    self.readyAt = nil;
    self.displayAt = nil;
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    ((AVPlayerLayer *)self.playerView.layer).player = self.player;
    if (self.active && !self.paused) [self.player play];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != RTItemStatusContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    RTMain(^{
        if (object != self.playerItem) return;
        if (self.playerItem.status == AVPlayerItemStatusReadyToPlay) {
            if (!self.readyAt) self.readyAt = [NSDate date];
            [self applySound];
            [self.spinner stopAnimating];
            [UIView animateWithDuration:0.25 animations:^{ self.playerView.alpha = 1; }];
        } else if (self.playerItem.status == AVPlayerItemStatusFailed) {
            RTLog(@"player failed: %@", self.playerItem.error);
            [self.spinner stopAnimating];
            [self showMessage:@"This video will not play.\n\nTap to try again."];
            [self unload];
        }
    });
}

- (void)itemDidReachEnd:(NSNotification *)note
{
    [self.playerItem seekToTime:kCMTimeZero];
    if (self.active && !self.paused) [self.player play];
}

// AVPlayer.volume / muted are iOS 7+, so on iOS 6 sound is switched off with an audio mix on the item.
- (void)applySound
{
    AVPlayerItem *item = self.playerItem;
    NSArray *tracks = [item.asset tracksWithMediaType:AVMediaTypeAudio];
    if (!tracks.count) return;
    float volume = [RTSettings soundOn] ? 1.0f : 0.0f;
    NSMutableArray *params = [NSMutableArray array];
    for (AVAssetTrack *track in tracks) {
        AVMutableAudioMixInputParameters *p = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
        [p setVolume:volume atTime:kCMTimeZero];
        [params addObject:p];
    }
    AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
    mix.inputParameters = params;
    item.audioMix = mix;
}

- (void)activate
{
    self.active = YES;
    self.paused = NO;
    self.playIcon.hidden = YES;
    if (self.player) {
        if (self.playerItem.status != AVPlayerItemStatusReadyToPlay) [self.spinner startAnimating];
        [self.player play];
    } else {
        [self preload];
        if (self.preparing) [self.spinner startAnimating];
    }
}

- (void)deactivate
{
    self.active = NO;
    self.playIcon.hidden = YES;
    [self.spinner stopAnimating];
    [self.player pause];
    if (self.playerItem.status == AVPlayerItemStatusReadyToPlay) [self.playerItem seekToTime:kCMTimeZero];
}

- (void)unload
{
    self.generation++;
    self.preparing = NO;
    [self.player pause];
    if (self.playerItem) {
        [self.playerItem removeObserver:self forKeyPath:@"status" context:RTItemStatusContext];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
    }
    if (self.player) RTLivePlayers--;
    ((AVPlayerLayer *)self.playerView.layer).player = nil;
    self.playerView.alpha = 0;
    self.player = nil;
    self.playerItem = nil;
}

#pragma mark Player Debug

// Read-only: reports the player state, never changes it.
- (void)updateDebug
{
    if (![RTSettings playerDebug]) {
        self.debugLabel.hidden = YES;
        return;
    }
    if (!self.debugLabel) {
        UILabel *l = [[UILabel alloc] init];
        l.font = [UIFont fontWithName:@"Courier-Bold" size:10];
        l.textColor = [UIColor colorWithRed:0.4 green:1 blue:0.4 alpha:1];
        l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
        l.numberOfLines = 0;
        l.userInteractionEnabled = NO;
        [self addSubview:l];
        self.debugLabel = l;
    }
    [self bringSubviewToFront:self.debugLabel];
    self.debugLabel.hidden = NO;

    AVPlayerLayer *pl = (AVPlayerLayer *)self.playerView.layer;
    AVPlayerItem *it = self.playerItem;
    if (pl.readyForDisplay && !self.displayAt && self.attachedAt) self.displayAt = [NSDate date];
    NSString *status = !it ? (self.preparing ? @"loading" : @"none")
                     : it.status == AVPlayerItemStatusReadyToPlay ? @"ready"
                     : it.status == AVPlayerItemStatusFailed ? @"FAILED" : @"unknown";
    NSString *(^since)(NSDate *) = ^NSString *(NSDate *d) {
        return (d && self.attachedAt) ? [NSString stringWithFormat:@"%.1fs", [d timeIntervalSinceDate:self.attachedAt]] : @"-";
    };
    CGSize pres = it ? it.presentationSize : CGSizeZero;
    CGRect lf = pl.frame;
    double t = it ? CMTimeGetSeconds(it.currentTime) : 0;
    self.debugLabel.text = [NSString stringWithFormat:
        @"page %ld %@%@ live players %ld\n"
        @"item %@ rate %.1f t %.1f pres %.0fx%.0f\n"
        @"DISPLAY %@ layer.player %@ alpha %.2f hidden %d\n"
        @"layer %.0f,%.0f %.0fx%.0f win %d super %d\n"
        @"page y %.0f %.0fx%.0f attach>ready %@ >display %@",
        (long)self.index, self.active ? @"ACTIVE" : @"idle", self.paused ? @" paused" : @"", (long)RTLivePlayers,
        status, self.player.rate, isnan(t) ? 0 : t, pres.width, pres.height,
        pl.readyForDisplay ? @"YES" : @"NO", !pl.player ? @"nil" : (pl.player == self.player ? @"ok" : @"OTHER"),
        self.playerView.alpha, self.playerView.hidden,
        lf.origin.x, lf.origin.y, lf.size.width, lf.size.height, self.window != nil, self.superview != nil && !self.superview.hidden,
        self.frame.origin.y, self.frame.size.width, self.frame.size.height, since(self.readyAt), since(self.displayAt)];
    self.debugLabel.frame = CGRectMake(4, 4, self.bounds.size.width - 8, 66);
}

#pragma mark Touches

- (void)tapped
{
    if (!self.messageLabel.hidden) {
        [self showMessage:nil];
        if (self.active) [self activate];
        return;
    }
    if (!self.active || !self.player) return;
    self.paused = !self.paused;
    self.playIcon.hidden = !self.paused;
    if (self.paused) [self.player pause];
    else [self.player play];
}

- (void)likeTapped { [self.delegate videoPageWantsLike:self]; }
- (void)commentsTapped { [self.delegate videoPageWantsComments:self]; }
- (void)profileTapped { [self.delegate videoPageWantsProfile:self]; }
- (void)shareTapped { [self.delegate videoPageWantsShare:self]; }

@end
