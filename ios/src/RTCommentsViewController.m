#import "RTCommentsViewController.h"
#import "RTAwemeAPI.h"
#import "RTImageLoader.h"
#import "RTTheme.h"

static const CGFloat kRTTextX = 58, kRTLikesW = 46;

@interface RTCommentCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *name;
@property (nonatomic, strong) UILabel *body;
@property (nonatomic, strong) UILabel *meta;
@property (nonatomic, strong) UILabel *likes;
@end

@implementation RTCommentCell

+ (UIFont *)bodyFont { return [UIFont systemFontOfSize:14]; }

+ (CGFloat)heightForComment:(NSDictionary *)c width:(CGFloat)width
{
    CGFloat textW = width - kRTTextX - kRTLikesW;
    CGFloat bodyH = ceil([RTStr(c[@"text"]) sizeWithFont:[self bodyFont] constrainedToSize:CGSizeMake(textW, 2000)
                                          lineBreakMode:NSLineBreakByWordWrapping].height);
    return MAX(60, 10 + 18 + 2 + bodyH + 4 + 15 + 10);
}

static UILabel *RTCellLabel(UIFont *font, UIColor *color)
{
    UILabel *l = [[UILabel alloc] init];
    l.backgroundColor = [UIColor whiteColor];
    l.font = font;
    l.textColor = color;
    return l;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _avatar = [[UIImageView alloc] initWithFrame:CGRectMake(12, 12, 36, 36)];
        _avatar.layer.cornerRadius = 18;
        _avatar.layer.masksToBounds = YES;
        _avatar.layer.shouldRasterize = YES;
        _avatar.layer.rasterizationScale = [UIScreen mainScreen].scale;
        _name = RTCellLabel([UIFont boldSystemFontOfSize:14], [UIColor colorWithWhite:0.15 alpha:1]);
        _body = RTCellLabel([RTCommentCell bodyFont], [UIColor colorWithWhite:0.2 alpha:1]);
        _body.numberOfLines = 0;
        _meta = RTCellLabel([UIFont systemFontOfSize:12], [UIColor colorWithWhite:0.55 alpha:1]);
        _likes = RTCellLabel([UIFont systemFontOfSize:11], [UIColor colorWithWhite:0.5 alpha:1]);
        _likes.textAlignment = NSTextAlignmentCenter;
        _likes.numberOfLines = 2;
        for (UIView *v in @[ _avatar, _name, _body, _meta, _likes ]) [self.contentView addSubview:v];
    }
    return self;
}

- (void)setComment:(NSDictionary *)c
{
    [[RTImageLoader shared] loadPath:RTStr(c[@"avatar_url"]) into:self.avatar placeholder:[RTTheme avatarPlaceholder]];
    NSString *nick = RTStr(c[@"nickname"]);
    self.name.text = nick.length ? nick : RTStr(c[@"author"]);
    self.body.text = RTStr(c[@"text"]);
    long long replies = RTNum(c[@"replies"]);
    NSString *ago = RTTimeAgo(RTNum(c[@"time"]));
    self.meta.text = replies ? [NSString stringWithFormat:@"%@  \u00B7  %lld %@", ago, replies, replies == 1 ? @"reply" : @"replies"] : ago;
    self.likes.text = [NSString stringWithFormat:@"\u2661\n%@", RTShortCount(RTNum(c[@"likes"]))];
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat textW = w - kRTTextX - kRTLikesW;
    self.name.frame = CGRectMake(kRTTextX, 10, textW, 18);
    CGFloat bodyH = ceil([self.body.text sizeWithFont:self.body.font constrainedToSize:CGSizeMake(textW, 2000)
                                        lineBreakMode:NSLineBreakByWordWrapping].height);
    self.body.frame = CGRectMake(kRTTextX, 30, textW, bodyH);
    self.meta.frame = CGRectMake(kRTTextX, 34 + bodyH, textW, 15);
    self.likes.frame = CGRectMake(w - kRTLikesW, 12, kRTLikesW - 6, 30);
}

@end

@interface RTCommentsViewController ()
@property (nonatomic, copy) NSDictionary *video;
@property (nonatomic, strong) NSMutableArray *comments;
@property (nonatomic, strong) NSMutableArray *heights;
@property (nonatomic, strong) NSMutableSet *commentIDs;
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, strong) NSError *lastError;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *footerLabel;
@end

@implementation RTCommentsViewController

- (instancetype)initWithItem:(NSDictionary *)item
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _video = [item copy];
        _comments = [NSMutableArray array];
        _heights = [NSMutableArray array];
        _commentIDs = [NSMutableSet set];
        self.title = [self titleForCount:RTNum(item[@"comments"])];
    }
    return self;
}

- (NSString *)titleForCount:(long long)n
{
    if (n <= 0) return @"Comments";
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    return [NSString stringWithFormat:@"%@ %@", [f stringFromNumber:@(n)], n == 1 ? @"Comment" : @"Comments"];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self action:@selector(done)];
    UIView *f = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 70)];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.center = CGPointMake(f.bounds.size.width / 2, 35);
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [f addSubview:self.spinner];
    self.footerLabel = [[UILabel alloc] initWithFrame:CGRectInset(f.bounds, 16, 8)];
    self.footerLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.footerLabel.backgroundColor = [UIColor clearColor];
    self.footerLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    self.footerLabel.font = [UIFont systemFontOfSize:14];
    self.footerLabel.textAlignment = NSTextAlignmentCenter;
    self.footerLabel.numberOfLines = 2;
    [f addSubview:self.footerLabel];
    [f addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(footerTapped)]];
    self.tableView.tableFooterView = f;
    [self loadMore];
}

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

- (void)done
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateFooter
{
    if (self.loading) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
    if (self.loading) self.footerLabel.text = @"";
    else if (self.lastError) self.footerLabel.text = @"Could not load comments. Tap to try again.";
    else if (self.finished && !self.comments.count) self.footerLabel.text = @"No comments yet.";
    else self.footerLabel.text = @"";
}

- (void)footerTapped
{
    if (self.lastError) [self loadMore];
}

- (void)loadMore
{
    if (self.loading || self.finished) return;
    self.loading = YES;
    self.lastError = nil;
    [self updateFooter];
    CGFloat width = self.tableView.bounds.size.width;
    [[RTAwemeAPI shared] loadComments:RTStr(self.video[@"id"]) cursor:self.cursor log:nil
                              handler:^(NSArray *comments, long long total, NSString *next, NSError *error) {
        self.loading = NO;
        if (error) {
            RTLog(@"comments failed: %@", error.localizedDescription);
            self.lastError = error;
        } else {
            if (total > 0) self.title = [self titleForCount:total];
            for (NSDictionary *c in comments) {
                NSString *cid = RTStr(c[@"id"]);
                if ([self.commentIDs containsObject:cid]) continue;
                [self.commentIDs addObject:cid];
                [self.comments addObject:c];
                [self.heights addObject:@([RTCommentCell heightForComment:c width:width])];
            }
            self.cursor = next;
            self.finished = next == nil;
            [self.tableView reloadData];
        }
        [self updateFooter];
    }];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGFloat h = scrollView.bounds.size.height;
    if (scrollView.contentOffset.y + h > scrollView.contentSize.height - h) [self loadMore];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.comments.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [self.heights[(NSUInteger)indexPath.row] floatValue];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    RTCommentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"comment"];
    if (!cell) cell = [[RTCommentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"comment"];
    [cell setComment:self.comments[(NSUInteger)indexPath.row]];
    return cell;
}

@end
