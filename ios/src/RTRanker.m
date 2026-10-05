#import "RTRanker.h"
#import "RTFeatures.h"
#import "RTInterestProfile.h"
#import "RTSettings.h"

static const NSUInteger kRTRecentWindow = 10;

@implementation RTRanker

+ (BOOL)isBlocked:(NSDictionary *)item
{
    return [RTSettings levelForLanguage:RTStr(item[@"lang"]) ?: @"un"] == RTLevelBlock;
}

static double RTTypeWeight(NSString *type)
{
    static NSDictionary *weights;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        weights = @{ @"creator": @1.0, @"tag": @0.8, @"lang": @0.8, @"kw": @0.5, @"music": @0.4,
                     @"len": @0.3, @"region": @0.3, @"aigc": @0.3, @"size": @0.2 };
    });
    return [weights[type] doubleValue];
}

static NSString *RTCreator(NSDictionary *item) { return [RTStr(item[@"author"]) lowercaseString]; }

static NSSet *RTTags(NSDictionary *item)
{
    NSMutableSet *tags = [NSMutableSet set];
    for (id f in RTArr(item[@"features"])) if ([RTStr(f) hasPrefix:@"tag:"]) [tags addObject:f];
    return tags;
}

+ (double)scoreItem:(NSDictionary *)item recent:(NSArray *)recent reasons:(NSString **)reasons
{
    RTInterestProfile *profile = [RTInterestProfile shared];
    double explore = [RTSettings discovery];
    NSMutableArray *terms = [NSMutableArray array];   // @[value, label]

    // Behaviour: per feature type the mean affinity; tags and caption words are many, so sum/sqrt(n) clamped,
    // which lets one strongly liked tag count without many unknown ones drowning it.
    NSMutableDictionary *sums = [NSMutableDictionary dictionary], *counts = [NSMutableDictionary dictionary];
    NSMutableDictionary *strongest = [NSMutableDictionary dictionary];
    BOOL creatorKnown = YES;
    for (id raw in RTArr(item[@"features"])) {
        NSString *f = RTStr(raw), *type = [RTFeatures typeOf:f];
        BOOL known = NO;
        double a = [profile affinity:f known:&known];
        if ([type isEqualToString:@"creator"]) creatorKnown = known;
        sums[type] = @([sums[type] doubleValue] + a);
        counts[type] = @([counts[type] integerValue] + 1);
        if (fabs(a) > fabs([RTArr(strongest[type])[0] doubleValue])) strongest[type] = @[ @(a), f ];
    }
    for (NSString *type in sums) {
        double sum = [sums[type] doubleValue], n = [counts[type] doubleValue];
        double v = ([type isEqualToString:@"tag"] || [type isEqualToString:@"kw"]) ? MAX(-1.0, MIN(1.0, sum / sqrt(n))) : sum / n;
        v *= RTTypeWeight(type);
        if (fabs(v) >= 0.005) [terms addObject:@[ @(v), RTStr(RTArr(strongest[type])[1]) ?: type ]];
    }

    // Settings: starting guidance that behaviour can outweigh (Block never gets here).
    RTLevel level = [RTSettings levelForLanguage:RTStr(item[@"lang"]) ?: @"un"];
    if (level == RTLevelPrefer) [terms addObject:@[ @0.6, [NSString stringWithFormat:@"prefer %@", item[@"lang"]] ]];
    if (level == RTLevelReduce) [terms addObject:@[ @-0.8, [NSString stringWithFormat:@"reduce %@", item[@"lang"]] ]];

    double plays = RTNum(item[@"plays"]), likes = RTNum(item[@"likes"]);
    double pop = 0.15 * MIN(1.0, log10(plays + 1) / 7) + 0.15 * MIN(1.0, (likes / MAX(plays, 1.0)) / 0.12);
    [terms addObject:@[ @(pop), @"popularity" ]];

    if (!creatorKnown && explore > 0) [terms addObject:@[ @(0.3 * explore), @"new creator" ]];

    NSString *creator = RTCreator(item);
    NSSet *tags = RTTags(item);
    double repeat = 0;
    NSUInteger start = recent.count > kRTRecentWindow ? recent.count - kRTRecentWindow : 0;
    for (NSUInteger i = start; i < recent.count; i++) {
        NSDictionary *r = RTDict(recent[i]);
        if (creator.length && [RTCreator(r) isEqualToString:creator]) repeat -= 0.6;
        NSMutableSet *shared = [RTTags(r) mutableCopy];
        [shared intersectSet:tags];
        repeat -= 0.15 * MIN(shared.count, (NSUInteger)3);
    }
    if (repeat < 0) [terms addObject:@[ @(repeat), @"seen similar" ]];

    double score = (arc4random_uniform(10000) / 10000.0) * (0.15 + 0.5 * explore);
    for (NSArray *t in terms) score += [t[0] doubleValue];

    if (reasons) {
        NSArray *top = [terms sortedArrayUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
            double x = fabs([a[0] doubleValue]), y = fabs([b[0] doubleValue]);
            return x > y ? NSOrderedAscending : x < y ? NSOrderedDescending : NSOrderedSame;
        }];
        NSMutableArray *parts = [NSMutableArray array];
        for (NSArray *t in [top subarrayWithRange:NSMakeRange(0, MIN(top.count, (NSUInteger)3))])
            [parts addObject:[NSString stringWithFormat:@"%+.2f %@", [t[0] doubleValue], t[1]]];
        *reasons = [parts componentsJoinedByString:@", "];
    }
    return score;
}

@end
