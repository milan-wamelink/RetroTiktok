#import "RTFavorites.h"

@interface RTFavorites ()
@property (nonatomic, strong) NSMutableArray *list;
@property (nonatomic, strong) NSMutableSet *ids;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@end

// Normalized items only hold strings, numbers and string arrays; keep exactly those so the plist always writes.
static NSDictionary *RTPlistSafe(NSDictionary *item)
{
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    [item enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]]) return;
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) out[key] = value;
        else if ([value isKindOfClass:[NSArray class]]) {
            NSMutableArray *strings = [NSMutableArray array];
            for (id v in value) if ([v isKindOfClass:[NSString class]]) [strings addObject:v];
            out[key] = strings;
        }
    }];
    return out;
}

@implementation RTFavorites

+ (instancetype)shared
{
    static RTFavorites *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[RTFavorites alloc] init]; });
    return shared;
}

- (instancetype)init
{
    if ((self = [super init])) {
        NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).lastObject;
        NSString *dir = [library stringByAppendingPathComponent:[NSBundle mainBundle].bundleIdentifier ?: @"nl.retrotok.legacytiktok"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        _path = [dir stringByAppendingPathComponent:@"favorites.plist"];
        _ioQueue = dispatch_queue_create("nl.retrotok.favorites", DISPATCH_QUEUE_SERIAL);
        _list = [NSMutableArray array];
        _ids = [NSMutableSet set];
        for (id raw in [NSArray arrayWithContentsOfFile:_path]) {
            NSDictionary *item = RTDict(raw);
            NSString *vid = RTStr(item[@"id"]);
            if (!vid.length || [_ids containsObject:vid]) continue;
            [_ids addObject:vid];
            [_list addObject:item];
        }
    }
    return self;
}

- (NSArray *)items { return [self.list copy]; }

- (BOOL)containsID:(NSString *)videoID { return videoID.length && [self.ids containsObject:videoID]; }

- (BOOL)toggleItem:(NSDictionary *)item
{
    NSString *vid = RTStr(item[@"id"]);
    if (!vid.length) return NO;
    if ([self.ids containsObject:vid]) {
        [self removeID:vid];
        return NO;
    }
    [self.ids addObject:vid];
    [self.list insertObject:RTPlistSafe(item) atIndex:0];
    [self changed];
    return YES;
}

- (void)removeID:(NSString *)videoID
{
    if (![self.ids containsObject:videoID]) return;
    [self.ids removeObject:videoID];
    NSIndexSet *gone = [self.list indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return [RTStr(RTDict(obj)[@"id"]) isEqualToString:videoID];
    }];
    [self.list removeObjectsAtIndexes:gone];
    [self changed];
}

- (void)changed
{
    NSArray *snapshot = [self.list copy];
    NSString *path = self.path;
    dispatch_async(self.ioQueue, ^{
        if (![snapshot writeToFile:path atomically:YES]) RTLog(@"could not save favorites to %@", path);
    });
    [[NSNotificationCenter defaultCenter] postNotificationName:RTLikesDidChangeNotification object:self];
}

@end
