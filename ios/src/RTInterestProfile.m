#import "RTInterestProfile.h"
#import "RTFeatures.h"

static const NSUInteger kRTMaxFeatures = 3000, kRTMaxSeen = 3000, kRTMaxHistory = 1000;
static const double kRTHalfLife = 14 * 24 * 3600.0;

@interface RTInterestProfile ()
@property (nonatomic, strong) NSMutableDictionary *affinities;   // feature -> @[affinity, last update (unix)]
@property (nonatomic, strong) NSMutableArray *seenList;
@property (nonatomic, strong) NSMutableSet *seenSet;
@property (nonatomic, strong) NSMutableArray *history;           // newest first
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@property (nonatomic, assign) BOOL saveScheduled;
@end

@implementation RTInterestProfile

+ (instancetype)shared
{
    static RTInterestProfile *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[RTInterestProfile alloc] init]; });
    return shared;
}

- (instancetype)init
{
    if ((self = [super init])) {
        NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).lastObject;
        NSString *dir = [library stringByAppendingPathComponent:[NSBundle mainBundle].bundleIdentifier ?: @"nl.retrotok.legacytiktok"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        _path = [dir stringByAppendingPathComponent:@"interests.plist"];
        _ioQueue = dispatch_queue_create("nl.retrotok.interests", DISPATCH_QUEUE_SERIAL);
        NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:_path];
        _affinities = [RTDict(saved[@"affinities"]) mutableCopy] ?: [NSMutableDictionary dictionary];
        _seenList = [RTArr(saved[@"seen"]) mutableCopy] ?: [NSMutableArray array];
        _seenSet = [NSMutableSet setWithArray:_seenList];
        _history = [RTArr(saved[@"history"]) mutableCopy] ?: [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveNow)
                                                     name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}

- (NSUInteger)featureCount { return self.affinities.count; }
- (NSUInteger)viewCount { return self.history.count; }

static double RTDecayed(NSArray *entry, double now)
{
    if (entry.count < 2) return 0;
    double age = MAX(0, now - [entry[1] doubleValue]);
    return [entry[0] doubleValue] * pow(0.5, age / kRTHalfLife);
}

- (double)affinity:(NSString *)feature known:(BOOL *)known
{
    NSArray *entry = RTArr(self.affinities[feature]);
    if (known) *known = entry != nil;
    return entry ? RTDecayed(entry, [[NSDate date] timeIntervalSince1970]) : 0;
}

// Small steps: one video only nudges, repeated behaviour moves things. Creators learn slower than topics so a single
// great video doesn't flood the feed with that creator.
static double RTLearningRate(NSString *type)
{
    static NSDictionary *rates;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rates = @{ @"tag": @0.12, @"lang": @0.10, @"creator": @0.08, @"kw": @0.08, @"music": @0.08,
                   @"region": @0.06, @"len": @0.05, @"size": @0.05, @"aigc": @0.05 };
    });
    return [rates[type] doubleValue] ?: 0.05;
}

- (void)learnItem:(NSDictionary *)item reward:(double)reward
{
    double now = [[NSDate date] timeIntervalSince1970];
    for (id raw in RTArr(item[@"features"])) {
        NSString *f = RTStr(raw);
        if (!f.length) continue;
        double a = RTDecayed(RTArr(self.affinities[f]), now);
        a += RTLearningRate([RTFeatures typeOf:f]) * (reward - a);
        a = MAX(-1.0, MIN(1.0, a));
        self.affinities[f] = @[ @(a), @(now) ];
    }
    if (self.affinities.count > kRTMaxFeatures) [self prune];
    [self scheduleSave];
}

// Drop the features that matter least: weakest and least recently updated first.
- (void)prune
{
    double now = [[NSDate date] timeIntervalSince1970];
    NSArray *keys = [self.affinities keysSortedByValueUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        double x = fabs(RTDecayed(a, now)), y = fabs(RTDecayed(b, now));
        return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
    }];
    NSUInteger drop = self.affinities.count - kRTMaxFeatures * 9 / 10;
    [self.affinities removeObjectsForKeys:[keys subarrayWithRange:NSMakeRange(0, MIN(drop, keys.count))]];
}

- (BOOL)hasSeen:(NSString *)videoID { return videoID.length && [self.seenSet containsObject:videoID]; }

- (void)recordView:(NSDictionary *)item fraction:(double)fraction
{
    NSString *vid = RTStr(item[@"id"]);
    if (!vid.length) return;
    if (![self.seenSet containsObject:vid]) {
        [self.seenSet addObject:vid];
        [self.seenList addObject:vid];
        if (self.seenList.count > kRTMaxSeen) {
            NSRange old = NSMakeRange(0, self.seenList.count - kRTMaxSeen);
            for (NSString *gone in [self.seenList subarrayWithRange:old]) [self.seenSet removeObject:gone];
            [self.seenList removeObjectsInRange:old];
        }
    }
    NSString *desc = RTStr(item[@"desc"]) ?: @"";
    if (desc.length > 100) desc = [desc substringToIndex:100];
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"id"] = vid;
    entry[@"time"] = @((long long)[[NSDate date] timeIntervalSince1970]);
    entry[@"watched"] = @(round(fraction * 100) / 100);
    entry[@"author"] = RTStr(item[@"author"]) ?: @"";
    entry[@"desc"] = desc;
    if (RTStr(item[@"cover_url"])) entry[@"cover_url"] = RTStr(item[@"cover_url"]);
    if (RTStr(item[@"sec_uid"])) entry[@"sec_uid"] = RTStr(item[@"sec_uid"]);
    entry[@"create_time"] = @(RTNum(item[@"create_time"]));
    [self.history insertObject:entry atIndex:0];
    if (self.history.count > kRTMaxHistory) [self.history removeObjectsInRange:NSMakeRange(kRTMaxHistory, self.history.count - kRTMaxHistory)];
    [self scheduleSave];
}

- (void)reset
{
    [self.affinities removeAllObjects];
    [self.seenList removeAllObjects];
    [self.seenSet removeAllObjects];
    [self.history removeAllObjects];
    [self saveNow];
}

// Writing ~0.5 MB after every swipe would be wasteful on the A5: batch the writes.
- (void)scheduleSave
{
    if (self.saveScheduled) return;
    self.saveScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self saveNow]; });
}

- (void)saveNow
{
    self.saveScheduled = NO;
    NSDictionary *snapshot = @{ @"version": @1, @"affinities": [self.affinities copy],
                                @"seen": [self.seenList copy], @"history": [self.history copy] };
    NSString *path = self.path;
    dispatch_async(self.ioQueue, ^{
        if (![snapshot writeToFile:path atomically:YES]) RTLog(@"could not save interests to %@", path);
    });
}

@end
