#import "RTRankedFeedSource.h"
#import "RTAwemeAPI.h"
#import "RTRanker.h"
#import "RTInterestProfile.h"
#import "RTSettings.h"

static const NSUInteger kRTBatch = 4;         // handed to the player per request: small, so learning shows up quickly
static const NSUInteger kRTRefillBelow = 16;  // keep this many candidates ahead to choose from
static const NSUInteger kRTMaxPool = 48;
static const NSUInteger kRTMaxFills = 3;      // feed requests per batch when blocks/seen filter everything out
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
    }];
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
    // RTAwemeAPI already retries TikTok's empty answers, so stop filling after its first error.
    if (candidates.count < kRTBatch && fills < kRTMaxFills && !lastError) {
        [self fill:^(NSError *error) { [self serve:handler fills:fills + 1 lastError:error generation:generation]; }];
        return;
    }
    if (!candidates.count) {
        handler(nil, lastError ?: RTMakeError(-1, @"TikTok only sent videos you have seen or blocked. Try again."));
        return;
    }
    NSArray *batch = [self pickFrom:candidates];
    NSMutableSet *picked = [NSMutableSet set];
    for (NSDictionary *item in batch) [picked addObject:RTStr(item[@"id"])];
    [self.pool filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, NSDictionary *bindings) {
        return ![picked containsObject:RTStr(e[@"item"][@"id"])];
    }]];
    [self.recent addObjectsFromArray:batch];
    if (self.recent.count > 20) [self.recent removeObjectsInRange:NSMakeRange(0, self.recent.count - 20)];
    handler(batch, nil);
    if (candidates.count - batch.count < kRTRefillBelow) [self fill:nil];
}

// Greedy: score everything, take the best (or, for exploration slots, a random one from the lower half), then rescore
// with that pick counted as recent so the next pick avoids the same creator/tags.
- (NSArray *)pickFrom:(NSArray *)candidates
{
    NSMutableArray *left = [candidates mutableCopy];
    NSMutableArray *batch = [NSMutableArray array];
    if (![RTSettings personalized]) {
        [batch addObjectsFromArray:[left subarrayWithRange:NSMakeRange(0, MIN(kRTBatch, left.count))]];
        return batch;
    }
    double exploreChance = 0.1 + 0.25 * [RTSettings discovery];
    NSMutableArray *recent = [self.recent mutableCopy];
    while (batch.count < kRTBatch && left.count) {
        NSMutableArray *scored = [NSMutableArray array];
        for (NSDictionary *item in left) {
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
