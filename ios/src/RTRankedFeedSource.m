#import "RTRankedFeedSource.h"
#import "RTAwemeAPI.h"
#import "RTRanker.h"
#import "RTInterestProfile.h"
#import "RTSettings.h"

static const NSUInteger kRTBatch = 4;         // handed to the player per request: small, so learning shows up quickly
static const NSUInteger kRTRefillBelow = 24;  // keep filling in the background until this many candidates wait
static const NSUInteger kRTMaxPool = 60;
static const NSUInteger kRTMaxFills = 3;      // feed requests to wait for when nothing showable is left
static const NSUInteger kRTReduceWindow = 10; // a Reduced language gets at most 1 of every 10 videos, if others exist
static const NSTimeInterval kRTPoolMaxAge = 20 * 60;   // TikTok's CDN links expire; drop old candidates

@interface RTRankedFeedSource ()
@property (nonatomic, strong) NSMutableArray *pool;        // @{ item, added }
@property (nonatomic, strong) NSMutableSet *knownIDs;      // in the pool or already handed out this session
@property (nonatomic, strong) NSMutableArray *recent;      // items handed out, newest last
@property (nonatomic, strong) NSMutableArray *fillWaiters;
@property (nonatomic, assign) BOOL filling;
@property (nonatomic, assign) BOOL pullFresh;
@property (nonatomic, assign) NSUInteger generation;
@end

@implementation RTRankedFeedSource

+ (instancetype)shared
{
    static RTRankedFeedSource *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[RTRankedFeedSource alloc] init]; });
    return shared;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _pool = [NSMutableArray array];
        _knownIDs = [NSMutableSet set];
        _recent = [NSMutableArray array];
        _fillWaiters = [NSMutableArray array];
    }
    return self;
}

- (NSString *)sourceName { return @"For You (ranked on this iPhone)"; }

#pragma mark Pool

- (NSArray *)candidates
{
    NSDate *now = [NSDate date];
    NSIndexSet *stale = [self.pool indexesOfObjectsPassingTest:^BOOL(NSDictionary *e, NSUInteger idx, BOOL *stop) {
        return [now timeIntervalSinceDate:e[@"added"]] > kRTPoolMaxAge;
    }];
    [self.pool removeObjectsAtIndexes:stale];
    BOOL personalized = [RTSettings personalized];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *e in self.pool) {
        NSDictionary *item = e[@"item"];
        if ([RTRanker isBlocked:item]) continue;
        if (personalized && [[RTInterestProfile shared] hasSeen:RTStr(item[@"id"])]) continue;
        [out addObject:item];
    }
    return out;
}

- (void)fill:(void (^)(NSError *error))done
{
    if (done) [self.fillWaiters addObject:[done copy]];
    if (self.filling) return;
    self.filling = YES;
    NSUInteger generation = self.generation;
    BOOL fresh = self.pullFresh;
    self.pullFresh = NO;
    [[RTAwemeAPI shared] loadFeedRefresh:fresh log:nil handler:^(NSArray *items, NSError *error) {
        if (generation != self.generation) return;
        self.filling = NO;
        NSDate *now = [NSDate date];
        for (NSDictionary *item in items) {
            NSString *vid = RTStr(item[@"id"]);
            if (!vid.length || [self.knownIDs containsObject:vid]) continue;
            [self.knownIDs addObject:vid];
            [self.pool addObject:@{ @"item": item, @"added": now }];
        }
        if (self.pool.count > kRTMaxPool) [self.pool removeObjectsInRange:NSMakeRange(0, self.pool.count - kRTMaxPool)];
        NSArray *waiters = [self.fillWaiters copy];
        [self.fillWaiters removeAllObjects];
        for (void (^w)(NSError *) in waiters) w(error);
        [self topUpAfter:error ? 5.0 : 0.5];
    }];
}

// TikTok sends ~8-12 videos per successful request and often a few empty answers first, so keep a reserve ahead.
- (void)topUpAfter:(NSTimeInterval)delay
{
    if (self.filling || [self reserve] >= kRTRefillBelow) return;
    NSUInteger generation = self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation == self.generation && [self reserve] < kRTRefillBelow) [self fill:nil];
    });
}

// Candidates that can be shown freely; held-back Reduced-language videos don't count.
- (NSUInteger)reserve
{
    NSUInteger n = 0;
    for (NSDictionary *item in [self candidates]) if (![self isReduced:item]) n++;
    return n;
}

#pragma mark RTFeedSource

- (void)loadFeedRefresh:(BOOL)refresh log:(RTFeedLog)log handler:(RTFeedHandler)handler
{
    if (refresh) {
        self.generation++;
        self.filling = NO;
        [self.fillWaiters removeAllObjects];
        [self.pool removeAllObjects];
        self.pullFresh = YES;
    }
    [self serve:handler fills:0 lastError:nil generation:self.generation];
}

- (void)serve:(RTFeedHandler)handler fills:(NSUInteger)fills lastError:(NSError *)lastError generation:(NSUInteger)generation
{
    if (generation != self.generation) return;
    NSArray *candidates = [self candidates];
    // Serve whatever is showable now; only wait for TikTok when nothing is. RTAwemeAPI already retries empty answers,
    // so stop waiting after its first error. After the last fill, a Reduced language may fill the gap.
    BOOL lastTry = fills >= kRTMaxFills || lastError;
    NSArray *batch = [self pickFrom:candidates relaxed:lastTry];
    if (!batch.count && !lastTry) {
        [self fill:^(NSError *error) { [self serve:handler fills:fills + 1 lastError:error generation:generation]; }];
        return;
    }
    if (!batch.count) {
        handler(nil, lastError ?: RTMakeError(-1, @"TikTok only sent videos you have seen or blocked. Try again."));
        return;
    }
    NSMutableSet *picked = [NSMutableSet set];
    for (NSDictionary *item in batch) [picked addObject:RTStr(item[@"id"])];
    [self.pool filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, NSDictionary *bindings) {
        return ![picked containsObject:RTStr(e[@"item"][@"id"])];
    }]];
    [self.recent addObjectsFromArray:batch];
    if (self.recent.count > 20) [self.recent removeObjectsInRange:NSMakeRange(0, self.recent.count - 20)];
    handler(batch, nil);
    [self topUpAfter:0];
}

- (BOOL)isReduced:(NSDictionary *)item
{
    return [RTSettings levelForLanguage:RTStr(item[@"lang"]) ?: @"un"] == RTLevelReduce;
}

// Whether a Reduced-language video may come next: none among the last kRTReduceWindow - 1 shown.
- (BOOL)reducedAllowedAfter:(NSArray *)recent
{
    NSUInteger n = MIN(recent.count, kRTReduceWindow - 1);
    for (NSUInteger i = recent.count - n; i < recent.count; i++)
        if ([self isReduced:recent[i]]) return NO;
    return YES;
}

// Greedy: score everything, take the best (or, for exploration slots, a random one from the lower half), then rescore
// with that pick counted as recent so the next pick avoids the same creator/tags.
// relaxed: when TikTok sends nothing else, a Reduced language may break its cap rather than leave the feed empty.
- (NSArray *)pickFrom:(NSArray *)candidates relaxed:(BOOL)relaxed
{
    NSMutableArray *left = [candidates mutableCopy];
    NSMutableArray *batch = [NSMutableArray array];
    NSMutableArray *recent = [self.recent mutableCopy];
    BOOL personalized = [RTSettings personalized];
    double exploreChance = 0.1 + 0.25 * [RTSettings discovery];
    while (batch.count < kRTBatch && left.count) {
        NSArray *allowed = left;
        if (![self reducedAllowedAfter:recent]) {
            allowed = [left filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, NSDictionary *b) {
                return ![self isReduced:item];
            }]];
            if (!allowed.count) {
                if (!relaxed || batch.count) break;
                allowed = left;
            }
        }
        if (!personalized) {
            [batch addObject:allowed[0]];
            [recent addObject:allowed[0]];
            [left removeObjectIdenticalTo:allowed[0]];
            continue;
        }
        NSMutableArray *scored = [NSMutableArray array];
        for (NSDictionary *item in allowed) {
            NSString *why = nil;
            double score = [RTRanker scoreItem:item recent:recent reasons:&why];
            [scored addObject:@[ @(score), item, why ?: @"" ]];
        }
        [scored sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [b[0] compare:a[0]]; }];
        NSUInteger index = 0;
        NSString *mode = @"top";
        if (scored.count >= 4 && arc4random_uniform(1000) < exploreChance * 1000) {
            NSUInteger half = scored.count / 2;
            index = half + arc4random_uniform((u_int32_t)(scored.count - half));
            mode = @"explore";
        }
        NSArray *chosen = scored[index];
        NSMutableDictionary *item = [chosen[1] mutableCopy];
        item[@"rank_score"] = chosen[0];
        item[@"rank_why"] = chosen[2];
        item[@"rank_pick"] = mode;
        [batch addObject:item];
        [recent addObject:item];
        [left removeObjectIdenticalTo:chosen[1]];
    }
    return batch;
}

#pragma mark RTFeedLearning

// Watch share -> reward: a quick skip is a clear "no", finishing or replaying a clear "yes", the middle says little.
static double RTWatchReward(double seconds, double duration)
{
    double fraction = duration > 0 ? seconds / duration : 0;
    if (seconds < 2 || fraction < 0.15) return -0.6;
    if (fraction >= 1.3) return 1.0;
    if (fraction >= 0.9) return 0.8;
    if (fraction >= 0.5) return 0.4;
    return 0;
}

- (void)feedDidView:(NSDictionary *)item seconds:(double)seconds duration:(double)duration showedVideo:(BOOL)showed
{
    if (duration <= 0) duration = RTNum(item[@"duration"]);
    [[RTInterestProfile shared] recordView:item fraction:duration > 0 ? seconds / duration : 0];
    // A video that never got its picture (still downloading) says nothing about taste.
    if (!showed || ![RTSettings personalized]) return;
    double reward = RTWatchReward(seconds, duration);
    if (reward != 0) [[RTInterestProfile shared] learnItem:item reward:reward];
}

- (void)feedDidEngage:(NSDictionary *)item kind:(NSString *)kind
{
    if (![RTSettings personalized]) return;
    double reward = [kind isEqualToString:@"favorite"] ? 1.5 : [kind isEqualToString:@"profile"] ? 0.6 : 0.4;
    [[RTInterestProfile shared] learnItem:item reward:reward];
}

@end
