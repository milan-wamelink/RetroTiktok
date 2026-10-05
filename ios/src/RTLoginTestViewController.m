#import "RTLoginTestViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "RTCommon.h"
#import "RTAwemeAPI.h"

static const NSTimeInterval kRTPollSeconds = 3;
static const NSUInteger kRTMaxChecks = 100;
static const NSUInteger kRTMaxErrorStreak = 10;

@interface RTLoginTestViewController ()
@property (nonatomic, strong) UIImageView *qrView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) NSMutableString *log;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *lastState;
@property (nonatomic, strong) NSDate *started;
@property (nonatomic, assign) long long expire;
@property (nonatomic, assign) NSUInteger checks;
@property (nonatomic, assign) NSUInteger errorStreak;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) BOOL checking;
@end

@implementation RTLoginTestViewController

- (instancetype)init
{
    if ((self = [super init])) {
        self.title = @"Login Test";
        _log = [NSMutableString string];
    }
    return self;
}

- (void)loadView
{
    UIView *root = [[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    root.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    self.view = root;

    self.qrView = [[UIImageView alloc] init];
    self.qrView.backgroundColor = [UIColor whiteColor];
    self.qrView.contentMode = UIViewContentModeScaleAspectFit;
    self.qrView.layer.magnificationFilter = kCAFilterNearest;
    [root addSubview:self.qrView];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:14];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.adjustsFontSizeToFitWidth = YES;
    [root addSubview:self.statusLabel];

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
    UIBarButtonItem *again = [[UIBarButtonItem alloc] initWithTitle:@"New QR" style:UIBarButtonItemStyleBordered
                                                             target:self action:@selector(newCode)];
    UIBarButtonItem *copy = [[UIBarButtonItem alloc] initWithTitle:@"Copy Log" style:UIBarButtonItemStyleBordered
                                                            target:self action:@selector(copyLog)];
    self.navigationItem.rightBarButtonItems = @[ again, copy ];
    [self say:[NSString stringWithFormat:@"LegacyTikTok %@ login test - %@ iOS %@",
               [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
               [UIDevice currentDevice].model, [UIDevice currentDevice].systemVersion]];
    [self newCode];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) [self stop];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat side = floorf(MIN(b.size.width - 80, b.size.height * 0.45f));
    self.qrView.frame = CGRectMake(floorf((b.size.width - side) / 2), 12, side, side);
    self.statusLabel.frame = CGRectMake(10, CGRectGetMaxY(self.qrView.frame) + 6, b.size.width - 20, 24);
    CGFloat top = CGRectGetMaxY(self.statusLabel.frame) + 6;
    self.logView.frame = CGRectMake(0, top, b.size.width, b.size.height - top);
}

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

- (void)say:(NSString *)line
{
    RTLog(@"%@", line);
    [self.log appendFormat:@"%@\n", line];
    self.logView.text = self.log;
    if (self.logView.contentSize.height > self.logView.bounds.size.height)
        [self.logView setContentOffset:CGPointMake(0, self.logView.contentSize.height - self.logView.bounds.size.height) animated:NO];
}

- (void)copyLog
{
    [UIPasteboard generalPasteboard].string = self.log;
    RTAlert(@"Log copied", @"Paste it into a message to report the result.");
}

- (void)stop
{
    [self.timer invalidate];
    self.timer = nil;
    self.token = nil;
    self.generation++;
}

- (void)finish:(NSString *)status result:(NSString *)result
{
    [self stop];
    self.statusLabel.text = status;
    [self say:[@"RESULT: " stringByAppendingString:result]];
}

- (void)newCode
{
    [self stop];
    NSUInteger generation = self.generation;
    self.lastState = nil;
    self.checks = 0;
    self.errorStreak = 0;
    self.checking = NO;
    self.qrView.image = nil;
    self.statusLabel.text = @"Requesting QR code...";
    [self say:@"\n== QR code (passport/web/get_qrcode)"];
    __weak RTLoginTestViewController *weakSelf = self;
    [[RTAwemeAPI shared] loginQRCodeWithLog:^(NSString *line) { [weakSelf say:line]; }
                                    handler:^(NSDictionary *qr, NSError *error) {
        RTLoginTestViewController *me = weakSelf;
        if (!me || me.generation != generation) return;
        if (error) {
            [me finish:@"Could not get a QR code" result:[@"no QR code: " stringByAppendingString:error.localizedDescription]];
            return;
        }
        UIImage *image = [UIImage imageWithData:qr[@"png"]];
        me.qrView.image = image;
        me.token = qr[@"token"];
        me.expire = RTNum(qr[@"expire"]);
        me.started = [NSDate date];
        long long left = me.expire ? me.expire - (long long)[[NSDate date] timeIntervalSince1970] : 0;
        [me say:[NSString stringWithFormat:@"OK: %.0fx%.0f QR image, expires in %llds", image.size.width, image.size.height, left]];
        [me say:[NSString stringWithFormat:@"\n== Waiting for scan (passport/web/check_qrconnect every %.0fs)", kRTPollSeconds]];
        me.statusLabel.text = @"Scan with the TikTok app on another phone";
        me.timer = [NSTimer scheduledTimerWithTimeInterval:kRTPollSeconds target:me selector:@selector(tick) userInfo:nil repeats:YES];
        [me tick];
    }];
}

- (void)tick
{
    if (self.checking || !self.token.length) return;
    if (self.expire && [[NSDate date] timeIntervalSince1970] > self.expire) {
        [self finish:@"QR code expired - tap New QR" result:@"QR code expired before it was confirmed."];
        return;
    }
    if (self.checks >= kRTMaxChecks) {
        [self finish:@"Stopped - tap New QR" result:[NSString stringWithFormat:@"stopped after %lu checks.", (unsigned long)self.checks]];
        return;
    }
    self.checking = YES;
    self.checks++;
    NSUInteger generation = self.generation;
    __weak RTLoginTestViewController *weakSelf = self;
    [[RTAwemeAPI shared] checkLoginQR:self.token handler:^(NSDictionary *s, NSError *error) {
        RTLoginTestViewController *me = weakSelf;
        if (!me || me.generation != generation) return;
        me.checking = NO;
        NSString *status = RTStr(s[@"status"]);
        BOOL ok = !error && [RTStr(s[@"message"]) isEqualToString:@"success"];
        NSString *state;
        if (error) state = [@"request failed: " stringByAppendingString:error.localizedDescription];
        else if (ok) state = [NSString stringWithFormat:@"status \"%@\"%@", status, [s[@"has_redirect"] boolValue] ? @", redirect_url present" : @""];
        else state = [NSString stringWithFormat:@"error %lld: %@", RTNum(s[@"error_code"]), RTStr(s[@"description"])];
        if (![state isEqualToString:me.lastState]) {
            me.lastState = state;
            [me say:[NSString stringWithFormat:@"[check %lu, %.0fs] %@%@", (unsigned long)me.checks, -[me.started timeIntervalSinceNow], state,
                     error ? @"" : [NSString stringWithFormat:@" (fields: %@)", RTStr(s[@"keys"])]]];
        }
        if (!ok) {
            if (++me.errorStreak >= kRTMaxErrorStreak)
                [me finish:@"TikTok refused the check" result:[NSString stringWithFormat:@"%@ (%lu times in a row).", state, (unsigned long)me.errorStreak]];
            else
                me.statusLabel.text = @"TikTok refused the check, retrying...";
            return;
        }
        me.errorStreak = 0;
        if ([status isEqualToString:@"new"]) me.statusLabel.text = @"Waiting for scan...";
        else if ([status isEqualToString:@"scanned"]) me.statusLabel.text = @"Scanned - confirm on the other phone";
        else if ([status isEqualToString:@"confirmed"])
            [me finish:@"Confirmed - QR login works here" result:@"login confirmed (nothing was saved)."];
        else if ([status isEqualToString:@"expired"])
            [me finish:@"QR code expired - tap New QR" result:@"TikTok says the QR code expired."];
    }];
}

@end
