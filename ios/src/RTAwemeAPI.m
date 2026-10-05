#import "RTAwemeAPI.h"
#import "RTHTTPClient.h"

static NSString * const kRTAwemeHost = @"https://api19-core-c-useast1a.tiktokv.com";
static NSString * const kRTAwemeUA = @"com.zhiliaoapp.musically/2023600040 (Linux; U; Android 13; en_US; Pixel 7; Build/TQ3A.230805.001; Cronet/58.0.2991.0)";
static const int kRTAwemeAttempts = 6;

@interface RTAwemeAPI ()
@property (nonatomic, assign) BOOL loadedOnce;
@end

@implementation RTAwemeAPI

+ (instancetype)shared
{
    static RTAwemeAPI *api;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ api = [[RTAwemeAPI alloc] init]; });
    return api;
}

- (NSString *)sourceName { return @"TikTok aweme API (direct)"; }

- (NSString *)openUDID
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *s = [d stringForKey:@"openudid"];
    if (s.length != 16) {
        s = [NSString stringWithFormat:@"%08x%08x", arc4random(), arc4random()];
        [d setObject:s forKey:@"openudid"];
    }
    return s;
}

- (NSURL *)feedURLRefresh:(BOOL)refresh
{
    long long now = (long long)[[NSDate date] timeIntervalSince1970];
    NSString *q = [NSString stringWithFormat:
        @"type=0&count=8&pull_type=%d&aid=1233&app_name=musical_ly&version_code=360004&version_name=36.0.4"
        @"&manifest_version_code=2023600040&device_platform=android&os=android&os_version=13&device_type=Pixel+7"
        @"&device_brand=Google&language=en&region=US&app_language=en&channel=googleplay"
        @"&iid=7318518857994389254&device_id=7318517321748022790&openudid=%@&ts=%lld&_rticket=%lld",
        refresh ? 0 : 2, [self openUDID], now, now * 1000];
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@/aweme/v1/feed/?%@", kRTAwemeHost, q]];
}

- (void)loadFeedRefresh:(BOOL)refresh log:(RTFeedLog)log handler:(RTFeedHandler)handler
{
    [self attempt:1 refresh:(refresh || !self.loadedOnce) log:log handler:handler];
}

- (void)attempt:(int)n refresh:(BOOL)refresh log:(RTFeedLog)log handler:(RTFeedHandler)handler
{
    NSDictionary *headers = @{ @"User-Agent": kRTAwemeUA, @"Accept": @"application/json" };
    [[RTHTTPClient shared] GET:[self feedURLRefresh:refresh] headers:headers handler:^(RTHTTPResponse *resp, NSError *error) {
        // Parsing ~400 KB of JSON and normalizing it takes long enough on an A5 to stutter a swipe: do it off the main thread.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray *raw = nil;
            NSString *why = nil;
            if (error) why = error.localizedDescription;
            else if (resp.status != 200) why = [NSString stringWithFormat:@"HTTP %ld", (long)resp.status];
            else if (!resp.data.length) why = @"empty answer";
            else {
                id json = [NSJSONSerialization JSONObjectWithData:resp.data options:0 error:NULL];
                raw = RTArr(RTDict(json)[@"aweme_list"]);
                if (!json) why = @"not JSON";
                else if (!raw.count) why = [NSString stringWithFormat:@"no videos (status_code %lld)", RTNum(RTDict(json)[@"status_code"])];
            }
            NSMutableArray *items = [NSMutableArray array];
            if (!why) {
                for (id aweme in raw) {
                    NSDictionary *item = [RTAwemeAPI normalizeAweme:RTDict(aweme)];
                    if (item) [items addObject:item];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (log) log([NSString stringWithFormat:@"feed attempt %d: HTTP %ld, %lld bytes in %.1fs%@%@", n, (long)resp.status,
                              resp.bytes, resp.duration, resp.tlsInfo.length ? [@", " stringByAppendingString:resp.tlsInfo] : @"",
                              why ? [@" - " stringByAppendingString:why] : @""]);
                if (why) {
                    if (n >= kRTAwemeAttempts) {
                        handler(nil, RTMakeError(-1, [NSString stringWithFormat:@"TikTok sent no feed after %d tries (%@).", n, why]));
                        return;
                    }
                    double delay = resp.status == 429 ? 4.0 : 1.5;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [self attempt:n + 1 refresh:refresh log:log handler:handler];
                    });
                    return;
                }
                if (log) log([NSString stringWithFormat:@"parsed %lu of %lu entries as playable videos", (unsigned long)items.count, (unsigned long)raw.count]);
                self.loadedOnce = YES;
                handler(items, nil);
            });
        });
    }];
}

#pragma mark Normalizing

static NSArray *RTURLList(id addr)
{
    return RTArr(RTDict(addr)[@"url_list"]);
}

// iOS 6 cannot decode WebP, so prefer the JPEG variants TikTok lists next to them.
static NSString *RTPickJPEG(NSArray *lists)
{
    NSString *fallback = nil;
    for (NSArray *list in lists) {
        for (id u in list) {
            NSString *s = RTStr(u);
            if (!s.length) continue;
            NSString *path = [s componentsSeparatedByString:@"?"][0];
            if ([path hasSuffix:@".jpeg"] || [path hasSuffix:@".jpg"]) return s;
            if (!fallback && ![path hasSuffix:@".webp"] && ![path hasSuffix:@".heic"]) fallback = s;
        }
    }
    return fallback;
}

static NSArray *RTMirrorsFirst(NSArray *urls)
{
    // v16m.tiktokcdn.com served every test download directly; keep the others as fallbacks.
    NSMutableArray *best = [NSMutableArray array], *rest = [NSMutableArray array];
    for (id u in urls) {
        NSString *s = RTStr(u);
        if (!s.length) continue;
        [([s rangeOfString:@"//v16m"].location != NSNotFound ? best : rest) addObject:s];
    }
    [best addObjectsFromArray:rest];
    return best;
}

+ (NSDictionary *)normalizeAweme:(NSDictionary *)a
{
    NSString *vid = RTStr(a[@"aweme_id"]);
    NSDictionary *video = RTDict(a[@"video"]);
    if (!vid.length || !video || a[@"image_post_info"] || RTNum(a[@"aweme_type"]) == 150) return nil;

    // H.264 only: the A5 has no HEVC (bytevc1) decoder. The 4S screen is 640x960, so take the largest rendition
    // up to 576 wide (TikTok's "540p"), else the smallest one (720p/1080p files are 2-4x bigger),
    // and the smallest file among equal sizes.
    NSDictionary *chosen = nil;
    long long chosenW = 0, chosenSize = 0;
    for (id entry in RTArr(video[@"bit_rate"])) {
        NSDictionary *b = RTDict(entry);
        if (RTNum(b[@"is_bytevc1"]) || RTNum(b[@"is_h265"])) continue;
        NSDictionary *pa = RTDict(b[@"play_addr"]);
        long long w = MIN(RTNum(pa[@"width"]), RTNum(pa[@"height"]));
        if (!RTURLList(pa).count) continue;
        long long size = RTNum(pa[@"data_size"]);
        BOOL better = !chosen || (w <= 576 && (chosenW > 576 || w > chosenW)) || (w > 576 && chosenW > 576 && w < chosenW)
                   || (w == chosenW && size > 0 && size < chosenSize);
        if (better) { chosen = pa; chosenW = w; chosenSize = size; }
    }
    if (!chosen && !RTNum(video[@"is_bytevc1"]) && !RTNum(video[@"is_h265"])) chosen = RTDict(video[@"play_addr"]);
    NSArray *urls = RTMirrorsFirst(RTURLList(chosen));
    if (!urls.count) return nil;

    NSDictionary *author = RTDict(a[@"author"]);
    NSDictionary *stats = RTDict(a[@"statistics"]);
    NSDictionary *music = RTDict(a[@"music"]);
    NSString *user = RTStr(author[@"unique_id"]);
    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    item[@"id"] = vid;
    item[@"desc"] = RTStr(a[@"desc"]) ?: @"";
    item[@"author"] = user ?: @"";
    item[@"nickname"] = RTStr(author[@"nickname"]) ?: @"";
    item[@"video_urls"] = urls;
    item[@"width"] = @(RTNum(chosen[@"width"]) ?: RTNum(video[@"width"]));
    item[@"height"] = @(RTNum(chosen[@"height"]) ?: RTNum(video[@"height"]));
    item[@"duration"] = @(RTNum(video[@"duration"]) / 1000);
    item[@"likes"] = @(RTNum(stats[@"digg_count"]));
    item[@"comments"] = @(RTNum(stats[@"comment_count"]));
    item[@"shares"] = @(RTNum(stats[@"share_count"]));
    item[@"plays"] = @(RTNum(stats[@"play_count"]));
    item[@"music"] = RTStr(music[@"title"]) ?: @"";
    item[@"music_author"] = RTStr(music[@"author"]) ?: @"";
    item[@"web_url"] = [NSString stringWithFormat:@"https://www.tiktok.com/@%@/video/%@", user ?: @"_", vid];
    NSString *cover = RTPickJPEG(@[ RTURLList(video[@"cover"]), RTURLList(video[@"origin_cover"]) ]);
    if (cover) item[@"cover_url"] = cover;
    NSString *avatar = RTPickJPEG(@[ RTURLList(author[@"avatar_thumb"]), RTURLList(author[@"avatar_medium"]) ]);
    if (avatar) item[@"avatar_url"] = avatar;
    return item;
}

@end
