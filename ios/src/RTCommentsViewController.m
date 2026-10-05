#import "RTCommentsViewController.h"
#import "RTAwemeAPI.h"
#import "RTImageLoader.h"
#import "RTTheme.h"

static const CGFloat kRTTextX = 58, kRTLikesW = 46, kRTReplyIndent = 38;

static CGFloat RTTextX(BOOL reply) { return reply ? kRTTextX + kRTReplyIndent : kRTTextX; }

@interface RTCommentCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *name;
@property (nonatomic, strong) UILabel *body;
@property (nonatomic, strong) UILabel *meta;
@property (nonatomic, strong) UILabel *likes;
@property (nonatomic, assign) BOOL reply;
@end

@implementation RTCommentCell

+ (UIFont *)bodyFont { return [UIFont systemFontOfSize:14]; }

+ (CGFloat)heightForComment:(NSDictionary *)c width:(CGFloat)width reply:(BOOL)reply
{
    CGFloat textW = width - RTTextX(reply) - kRTLikesW;
    CGFloat bodyH = ceil([RTStr(c[@"text"]) sizeWithFont:[self bodyFont] constrainedToSize:CGSizeMake(textW, 2000)
                                          lineBreakMode:NSLineBreakByWordWrapping].height);
    return MAX(reply ? 48 : 60, 10 + 18 + 2 + bodyH + 4 + 15 + 10);
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
    CGFloat x = RTTextX(self.reply);
    CGFloat textW = w - x - kRTLikesW;
    CGFloat a = self.reply ? 28 : 36;
    self.avatar.frame = self.reply ? CGRectMake(kRTTextX, 10, a, a) : CGRectMake(12, 12, a, a);
    self.avatar.layer.cornerRadius = a / 2;
    self.name.frame = CGRectMake(x, 10, textW, 18);
    CGFloat bodyH = ceil([self.body.text sizeWithFont:self.body.font constrainedToSize:CGSizeMake(textW, 2000)
                                        lineBreakMode:NSLineBreakByWordWrapping].height);
    self.body.frame = CGRectMake(x, 30, textW, bodyH);
    self.meta.frame = CGRectMake(x, 34 + bodyH, textW, 15);
    self.likes.frame = CGRectMake(w - kRTLikesW, 12, kRTLikesW - 6, 30);
}

@end

// The replies loaded so far under one comment.
@interface RTReplyThread : NSObject
@property (nonatomic, strong) NSMutableArray *replies;
@property (nonatomic, strong) NSMutableSet *replyIDs;
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL failed;
@end

@implementation RTReplyThread
- (instancetype)init
{
    if ((self = [super init])) {
        _replies = [NSMutableArray array];
        _replyIDs = [NSMutableSet set];
    }
    return self;
}
@end

@interface RTCommentsViewController ()
@property (nonatomic, copy) NSDictionary *video;
@property (nonatomic, strong) NSMutableArray *comments;
@property (nonatomic, strong) NSMutableArray *rows;          // flat table: comment, its loaded replies, its "more" row
@property (nonatomic, strong) NSMutableArray *rowHeights;
@property (nonatomic, strong) NSMutableDictionary *heightCache;
@property (nonatomic, strong) NSMutableDictionary *threads;   // comment id -> RTReplyThread
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
        _rows = [NSMutableArray array];
        _rowHeights = [NSMutableArray array];
        _heightCache = [NSMutableDictionary dictionary];
        _threads = [NSMutableDictionary dictionary];
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
            }
            self.cursor = next;
            self.finished = next == nil;
            [self reloadRows];
        }
        [self updateFooter];
    }];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGFloat h = scrollView.bounds.size.height;
    if (scrollView.contentOffset.y + h > scrollView.contentSize.height - h) [self loadMore];
}

#pragma mark Replies

- (CGFloat)heightFor:(NSDictionary *)c reply:(BOOL)reply
{
    NSString *key = RTStr(c[@"id"]);
    NSNumber *h = self.heightCache[key];
    if (!h) {
        h = @([RTCommentCell heightForComment:c width:self.tableView.bounds.size.width reply:reply]);
        if (key.length) self.heightCache[key] = h;
    }
    return [h floatValue];
}

- (void)reloadRows
{
    [self.rows removeAllObjects];
    [self.rowHeights removeAllObjects];
    for (NSDictionary *c in self.comments) {
        [self.rows addObject:@{ @"kind": @"comment", @"comment": c }];
        [self.rowHeights addObject:@([self heightFor:c reply:NO])];
        RTReplyThread *t = self.threads[RTStr(c[@"id"])];
        for (NSDictionary *r in t.replies) {
            [self.rows addObject:@{ @"kind": @"reply", @"comment": c, @"reply": r }];
            [self.rowHeights addObject:@([self heightFor:r reply:YES])];
        }
        if (RTNum(c[@"replies"]) > 0 && !t.finished) {
            [self.rows addObject:@{ @"kind": @"more", @"comment": c }];
            [self.rowHeights addObject:@36];
        }
    }
    [self.tableView reloadData];
}

- (NSString *)moreTextFor:(NSDictionary *)c
{
    RTReplyThread *t = self.threads[RTStr(c[@"id"])];
    if (t.loading) return @"Loading replies\u2026";
    if (t.failed) return @"Could not load replies. Tap to try again.";
    long long total = RTNum(c[@"replies"]);
    if (!t.replies.count) return [NSString stringWithFormat:@"View %lld %@", total, total == 1 ? @"reply" : @"replies"];
    long long left = total - (long long)t.replies.count;
    return left > 0 ? [NSString stringWithFormat:@"Load More (%lld)", left] : @"Load More";
}

- (void)loadRepliesFor:(NSDictionary *)c
{
    NSString *cid = RTStr(c[@"id"]);
    RTReplyThread *t = self.threads[cid];
    if (!t) {
        t = [[RTReplyThread alloc] init];
        self.threads[cid] = t;
    }
    if (t.loading || t.finished) return;
    t.loading = YES;
    t.failed = NO;
    [self reloadRows];
    [[RTAwemeAPI shared] loadReplies:cid videoID:RTStr(self.video[@"id"]) cursor:t.cursor
                             handler:^(NSArray *replies, long long total, NSString *next, NSError *error) {
        t.loading = NO;
        if (error) {
            RTLog(@"replies failed: %@", error.localizedDescription);
            t.failed = YES;
        } else {
            // Pages can overlap by a reply or two.
            for (NSDictionary *r in replies) {
                NSString *rid = RTStr(r[@"id"]);
                if ([t.replyIDs containsObject:rid]) continue;
                [t.replyIDs addObject:rid];
                [t.replies addObject:r];
            }
            t.cursor = next;
            t.finished = next == nil;
        }
        [self reloadRows];
    }];
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.rows.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [self.rowHeights[(NSUInteger)indexPath.row] floatValue];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *row = self.rows[(NSUInteger)indexPath.row];
    NSString *kind = row[@"kind"];
    if ([kind isEqualToString:@"more"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"more"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"more"];
            cell.textLabel.font = [UIFont boldSystemFontOfSize:13];
            cell.textLabel.textColor = [UIColor colorWithRed:0.32 green:0.4 blue:0.57 alpha:1];
            cell.indentationWidth = kRTTextX - 10;
            cell.indentationLevel = 1;
            cell.selectionStyle = UITableViewCellSelectionStyleGray;
        }
        cell.textLabel.text = [self moreTextFor:row[@"comment"]];
        return cell;
    }
    BOOL reply = [kind isEqualToString:@"reply"];
    NSString *ident = reply ? @"reply" : @"comment";
    RTCommentCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) cell = [[RTCommentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
    cell.reply = reply;
    [cell setComment:reply ? row[@"reply"] : row[@"comment"]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = self.rows[(NSUInteger)indexPath.row];
    if ([row[@"kind"] isEqualToString:@"more"]) [self loadRepliesFor:row[@"comment"]];
}

@end
