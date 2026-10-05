#import "RTAwemeAPI.h"
#import "RTFeatures.h"
#import "rt_xbogus.h"
#include <time.h>
#import "RTHTTPClient.h"

static NSString * const kRTAwemeHost = @"https://api19-core-c-useast1a.tiktokv.com";
static NSString * const kRTAwemeUA = @"com.zhiliaoapp.musically/2023600040 (Linux; U; Android 13; en_US; Pixel 7; Build/TQ3A.230805.001; Cronet/58.0.2991.0)";
static const int kRTAwemeAttempts = 6;
static NSString * const kRTWebHost = @"https://www.tiktok.com";
static NSString * const kRTWebUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 6_1_3 like Mac OS X) AppleWebKit/536.26 (KHTML, like Gecko) Version/6.0 Mobile/10B329 Safari/8536.25";
static const int kRTWebAttempts = 3;

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
    NSString *secUID = RTStr(author[@"sec_uid"]);
    if (secUID.length) item[@"sec_uid"] = secUID;
    item[@"create_time"] = @(RTNum(a[@"create_time"]));
    NSString *lang = [RTFeatures languageForAweme:a];
    item[@"lang"] = lang;
    item[@"features"] = [RTFeatures featuresForAweme:a language:lang];
    return item;
}

#pragma mark Web endpoints (profiles, comments)

// parse runs off the main thread and returns the result, or an NSString saying why the answer is unusable (retried).
- (void)web:(NSString *)pathAndQuery attempt:(int)n log:(RTFeedLog)log parse:(id (^)(NSDictionary *json))parse
    handler:(void (^)(id result, NSError *error))handler
{
    NSURL *url = [NSURL URLWithString:[kRTWebHost stringByAppendingString:pathAndQuery]];
    NSDictionary *headers = @{ @"User-Agent": kRTWebUA, @"Referer": @"https://www.tiktok.com/", @"Accept": @"application/json" };
    [[RTHTTPClient shared] GET:url headers:headers handler:^(RTHTTPResponse *resp, NSError *error) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            id result = nil;
            NSString *why = nil;
            if (error) why = error.localizedDescription;
            else if (resp.status != 200) why = [NSString stringWithFormat:@"HTTP %ld", (long)resp.status];
            else if (!resp.data.length) why = @"empty answer";
            else {
                NSDictionary *json = RTDict([NSJSONSerialization JSONObjectWithData:resp.data options:0 error:NULL]);
                if (!json) why = @"not JSON";
                else {
                    result = parse(json);
                    if ([result isKindOfClass:[NSString class]]) { why = result; result = nil; }
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (log) log([NSString stringWithFormat:@"%@ attempt %d: HTTP %ld, %lld bytes in %.1fs%@%@", url.path, n, (long)resp.status,
                              resp.bytes, resp.duration, resp.tlsInfo.length ? [@", " stringByAppendingString:resp.tlsInfo] : @"",
                              why ? [@" - " stringByAppendingString:why] : @""]);
                if (!why) { handler(result, nil); return; }
                if (n >= kRTWebAttempts) {
                    handler(nil, RTMakeError(-1, [NSString stringWithFormat:@"TikTok sent nothing usable after %d tries (%@).", n, why]));
                    return;
                }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self web:pathAndQuery attempt:n + 1 log:log parse:parse handler:handler];
                });
            });
        });
    }];
}

// www.tiktok.com/api/creator/item_list: newest first, paged backwards by creation time (milliseconds). The cursor is
// inclusive, so the next page repeats the last video; screens dedupe by id.
- (void)loadProfileVideos:(NSString *)secUID cursor:(NSString *)cursor log:(RTFeedLog)log handler:(RTProfileHandler)handler
{
    if (!secUID.length) { handler(nil, nil, nil, RTMakeError(-1, @"TikTok sent no profile id for this video.")); return; }
    NSString *c = cursor.length ? cursor : [NSString stringWithFormat:@"%lld", (long long)([[NSDate date] timeIntervalSince1970] * 1000)];
    NSString *q = [NSString stringWithFormat:@"/api/creator/item_list/?aid=1988&count=12&type=1&secUid=%@&cursor=%@", RTURLEncode(secUID), c];
    [self web:q attempt:1 log:log parse:^id(NSDictionary *json) {
        long long status = RTNum(json[@"statusCode"]) ?: RTNum(json[@"status_code"]);
        if (status) return [NSString stringWithFormat:@"status %lld %@", status, RTStr(json[@"status_msg"]) ?: @""];
        NSArray *list = RTArr(json[@"itemList"]);
        NSMutableArray *items = [NSMutableArray array];
        NSDictionary *profile = nil;
        for (id raw in list) {
            NSDictionary *it = RTDict(raw);
            if (!profile) profile = [RTAwemeAPI normalizeWebProfile:it];
            NSDictionary *item = [RTAwemeAPI normalizeWebItem:it];
            if (item) [items addObject:item];
        }
        long long last = list.count ? RTNum(RTDict(list[list.count - 1])[@"createTime"]) : 0;
        NSString *next = (last && RTBool(json[@"hasMorePrevious"])) ? [NSString stringWithFormat:@"%lld", last * 1000] : nil;
        if ([next isEqualToString:c]) next = nil;
        NSMutableDictionary *r = [NSMutableDictionary dictionary];
        r[@"items"] = items;
        if (profile) r[@"profile"] = profile;
        if (next) r[@"next"] = next;
        return r;
    } handler:^(id result, NSError *error) {
        NSDictionary *r = RTDict(result);
        handler(r[@"profile"], RTArr(r[@"items"]) ?: @[], r[@"next"], error);
    }];
}

// Saved video links expire. creator/item_list pages backwards from an inclusive cursor in milliseconds, so a cursor just
// after the video's creation time returns that video first, with fresh links.
- (void)refreshItem:(NSDictionary *)item handler:(void (^)(NSDictionary *fresh, NSError *error))handler
{
    NSString *vid = RTStr(item[@"id"]), *sec = RTStr(item[@"sec_uid"]);
    long long created = RTNum(item[@"create_time"]);
    if (!vid.length || !sec.length || !created) {
        RTMain(^{ handler(nil, RTMakeError(-1, @"not enough details saved to look this video up")); });
        return;
    }
    NSString *q = [NSString stringWithFormat:@"/api/creator/item_list/?aid=1988&count=3&type=1&secUid=%@&cursor=%lld",
                   RTURLEncode(sec), (created + 1) * 1000];
    [self web:q attempt:kRTWebAttempts - 1 log:nil parse:^id(NSDictionary *json) {
        for (id raw in RTArr(json[@"itemList"])) {
            NSDictionary *it = RTDict(raw);
            if ([RTStr(it[@"id"]) isEqualToString:vid]) return [RTAwemeAPI normalizeWebItem:it] ?: @"video is no longer playable";
        }
        return @"video is not in the creator's list";
    } handler:handler];
}

- (void)loadComments:(NSString *)videoID cursor:(NSString *)cursor log:(RTFeedLog)log handler:(RTCommentsHandler)handler
{
    NSString *q = [NSString stringWithFormat:@"/api/comment/list/?aid=1988&count=20&aweme_id=%@&cursor=%@", RTURLEncode(videoID),
                   cursor.length ? cursor : @"0"];
    [self web:q attempt:1 log:log parse:^id(NSDictionary *json) {
        if (RTNum(json[@"status_code"])) return [NSString stringWithFormat:@"status %lld %@", RTNum(json[@"status_code"]), RTStr(json[@"status_msg"]) ?: @""];
        NSArray *list = RTArr(json[@"comments"]);
        NSMutableArray *comments = [NSMutableArray array];
        for (id raw in list) {
            NSDictionary *c = [RTAwemeAPI normalizeComment:RTDict(raw)];
            if (c) [comments addObject:c];
        }
        NSString *next = (list.count && RTBool(json[@"has_more"])) ? RTStr(json[@"cursor"]) : nil;
        NSMutableDictionary *r = [NSMutableDictionary dictionary];
        r[@"comments"] = comments;
        r[@"total"] = @(RTNum(json[@"total"]));
        if (next.length) r[@"next"] = next;
        return r;
    } handler:^(id result, NSError *error) {
        NSDictionary *r = RTDict(result);
        handler(RTArr(r[@"comments"]) ?: @[], RTNum(r[@"total"]), r[@"next"], error);
    }];
}

- (void)loadReplies:(NSString *)commentID videoID:(NSString *)videoID cursor:(NSString *)cursor handler:(RTCommentsHandler)handler
{
    NSString *q = [NSString stringWithFormat:@"/api/comment/list/reply/?aid=1988&count=5&item_id=%@&comment_id=%@&cursor=%@",
                   RTURLEncode(videoID), RTURLEncode(commentID), cursor.length ? cursor : @"0"];
    [self web:q attempt:1 log:nil parse:^id(NSDictionary *json) {
        if (RTNum(json[@"status_code"])) return [NSString stringWithFormat:@"status %lld %@", RTNum(json[@"status_code"]), RTStr(json[@"status_msg"]) ?: @""];
        NSArray *list = RTArr(json[@"comments"]);
        NSMutableArray *replies = [NSMutableArray array];
        for (id raw in list) {
            NSDictionary *c = [RTAwemeAPI normalizeComment:RTDict(raw)];
            if (c) [replies addObject:c];
        }
        NSString *next = (list.count && RTBool(json[@"has_more"])) ? RTStr(json[@"cursor"]) : nil;
        NSMutableDictionary *r = [NSMutableDictionary dictionary];
        r[@"comments"] = replies;
        r[@"total"] = @(RTNum(json[@"total"]));
        if (next.length) r[@"next"] = next;
        return r;
    } handler:^(id result, NSError *error) {
        NSDictionary *r = RTDict(result);
        handler(RTArr(r[@"comments"]) ?: @[], RTNum(r[@"total"]), r[@"next"], error);
    }];
}

#pragma mark V4 search

- (NSString *)webDeviceID
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *s = [d stringForKey:@"web_device_id"];
    if (s.length != 19) {
        NSMutableString *m = [NSMutableString stringWithString:@"73"];
        for (int i = 0; i < 17; i++) [m appendFormat:@"%u", arc4random_uniform(10)];
        s = m;
        [d setObject:s forKey:@"web_device_id"];
    }
    return s;
}

// The hashtag endpoints answer with an empty body unless the request looks like the web app: its full parameter set
// plus an X-Bogus signature over exactly this query string and User-Agent.
- (NSString *)signedPath:(NSString *)path params:(NSDictionary *)extra
{
    NSMutableDictionary *all = [@{
        @"aid": @"1988", @"app_language": @"en", @"app_name": @"tiktok_web", @"browser_language": @"en-US",
        @"browser_name": @"Mozilla", @"browser_online": @"true", @"browser_platform": @"iPhone",
        @"browser_version": [kRTWebUA substringFromIndex:8], @"channel": @"tiktok_web", @"cookie_enabled": @"true",
        @"device_id": [self webDeviceID], @"device_platform": @"web_mobile", @"focus_state": @"true", @"history_len": @"3",
        @"is_fullscreen": @"false", @"is_page_visible": @"true", @"os": @"ios", @"priority_region": @"", @"referer": @"",
        @"region": @"US", @"screen_height": @"480", @"screen_width": @"320", @"tz_name": @"Europe/Amsterdam",
        @"webcast_language": @"en"
    } mutableCopy];
    [all addEntriesFromDictionary:extra];
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *k in [[all allKeys] sortedArrayUsingSelector:@selector(compare:)])
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", k, RTURLEncode(RTStr(all[k]) ?: @"")]];
    NSString *q = [pairs componentsJoinedByString:@"&"];
    char sig[29];
    rt_xbogus(q.UTF8String, kRTWebUA.UTF8String, (unsigned long)time(NULL), sig);
    return [NSString stringWithFormat:@"%@?%@&X-Bogus=%s", path, q, sig];
}

- (void)loadSuggestions:(NSString *)text handler:(void (^)(NSArray *words, NSError *error))handler
{
    NSString *q = [@"/api/search/general/preview/?aid=1988&keyword=" stringByAppendingString:RTURLEncode(text)];
    [self web:q attempt:kRTWebAttempts log:nil parse:^id(NSDictionary *json) {
        NSMutableArray *words = [NSMutableArray array];
        for (id raw in RTArr(json[@"sug_list"])) {
            NSString *w = RTStr(RTDict(raw)[@"content"]);
            if (w.length && ![words containsObject:w]) [words addObject:w];
        }
        return words;
    } handler:^(id result, NSError *error) { handler(RTArr(result) ?: @[], error); }];
}

- (void)lookupHashtag:(NSString *)name handler:(void (^)(NSDictionary *tag, NSError *error))handler
{
    NSString *q = [self signedPath:@"/api/challenge/detail/" params:@{ @"challengeName": name }];
    [self web:q attempt:1 log:nil parse:^id(NSDictionary *json) {
        NSDictionary *info = RTDict(json[@"challengeInfo"]);
        NSDictionary *ch = RTDict(info[@"challenge"]);
        NSString *tid = RTStr(ch[@"id"]);
        if (!tid.length) return @{};   // an answer without a hashtag: it doesn't exist (no point retrying)
        NSDictionary *stats = RTDict(info[@"statsV2"]) ?: RTDict(info[@"stats"]);
        NSMutableDictionary *t = [NSMutableDictionary dictionary];
        t[@"hashtag_id"] = tid;
        t[@"title"] = RTStr(ch[@"title"]) ?: name;
        t[@"desc"] = RTStr(ch[@"desc"]) ?: @"";
        t[@"videos"] = @(RTNum(stats[@"videoCount"]));
        t[@"views"] = @(RTNum(stats[@"viewCount"]));
        return t;
    } handler:^(id result, NSError *error) {
        NSDictionary *t = RTDict(result);
        if (!error && !RTStr(t[@"hashtag_id"]).length)
            error = RTMakeError(-1, [NSString stringWithFormat:@"TikTok has no hashtag #%@.", name]);
        handler(error ? nil : t, error);
    }];
}

- (void)loadHashtagVideos:(NSString *)tagID cursor:(NSString *)cursor handler:(RTProfileHandler)handler
{
    NSString *q = [self signedPath:@"/api/challenge/item_list/"
                            params:@{ @"challengeID": tagID ?: @"", @"count": @"12", @"cursor": cursor.length ? cursor : @"0" }];
    [self web:q attempt:1 log:nil parse:^id(NSDictionary *json) {
        long long status = RTNum(json[@"statusCode"]) ?: RTNum(json[@"status_code"]);
        if (status) return [NSString stringWithFormat:@"status %lld %@", status, RTStr(json[@"status_msg"]) ?: @""];
        NSArray *list = RTArr(json[@"itemList"]);
        NSMutableArray *items = [NSMutableArray array];
        for (id raw in list) {
            NSDictionary *item = [RTAwemeAPI normalizeWebItem:RTDict(raw)];
            if (item) [items addObject:[RTAwemeAPI preferPlayURL:item]];
        }
        NSString *next = (list.count && RTBool(json[@"hasMore"])) ? RTStr(json[@"cursor"]) : nil;
        if ([next isEqualToString:(cursor.length ? cursor : @"0")]) next = nil;
        NSMutableDictionary *r = [NSMutableDictionary dictionary];
        r[@"items"] = items;
        if (next.length) r[@"next"] = next;
        return r;
    } handler:^(id result, NSError *error) {
        NSDictionary *r = RTDict(result);
        handler(nil, RTArr(r[@"items"]) ?: @[], r[@"next"], error);
    }];
}

// Hashtag results' v16/v19-webapp-prime links answer 403, and their www.tiktok.com/aweme/v1/play/ link gives an MP4 in
// some regions but a web page in others. RTVideoCache first fetches fresh links from the creator's list (needs_fresh_links).
+ (NSDictionary *)preferPlayURL:(NSDictionary *)item
{
    NSMutableArray *play = [NSMutableArray array], *rest = [NSMutableArray array];
    for (id u in RTArr(item[@"video_urls"]))
        [([RTStr(u) rangeOfString:@"/aweme/v1/play/"].location != NSNotFound ? play : rest) addObject:u];
    NSMutableDictionary *m = [item mutableCopy];
    m[@"video_urls"] = [play arrayByAddingObjectsFromArray:rest];
    m[@"needs_fresh_links"] = @YES;
    return m;
}

// No JSON endpoint answers unsigned for a username, but the creator's page embeds its profile (with secUid) as JSON.
- (void)lookupUser:(NSString *)uniqueID handler:(void (^)(NSDictionary *profile, NSError *error))handler
{
    [self userPage:uniqueID attempt:1 handler:handler];
}

- (void)userPage:(NSString *)uniqueID attempt:(int)n handler:(void (^)(NSDictionary *profile, NSError *error))handler
{
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/@%@", kRTWebHost, RTURLEncode(uniqueID)]];
    NSDictionary *headers = @{ @"User-Agent": kRTWebUA, @"Accept": @"text/html", @"Accept-Language": @"en-US" };
    [[RTHTTPClient shared] GET:url headers:headers handler:^(RTHTTPResponse *resp, NSError *error) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSDictionary *profile = nil;
            BOOL missing = NO;
            if (!error && resp.status == 200 && resp.data.length) {
                NSString *html = [[NSString alloc] initWithData:resp.data encoding:NSUTF8StringEncoding];
                NSRange tag = [html rangeOfString:@"__UNIVERSAL_DATA_FOR_REHYDRATION__"];
                NSRange open = tag.location == NSNotFound ? tag
                             : [html rangeOfString:@">" options:0 range:NSMakeRange(NSMaxRange(tag), html.length - NSMaxRange(tag))];
                NSRange close = open.location == NSNotFound ? open
                              : [html rangeOfString:@"</script>" options:0 range:NSMakeRange(NSMaxRange(open), html.length - NSMaxRange(open))];
                if (close.location != NSNotFound) {
                    NSString *js = [html substringWithRange:NSMakeRange(NSMaxRange(open), close.location - NSMaxRange(open))];
                    NSDictionary *json = RTDict([NSJSONSerialization JSONObjectWithData:[js dataUsingEncoding:NSUTF8StringEncoding]
                                                                                options:0 error:NULL]);
                    NSDictionary *detail = RTDict(RTDict(json[@"__DEFAULT_SCOPE__"])[@"webapp.user-detail"]);
                    NSDictionary *info = RTDict(detail[@"userInfo"]);
                    NSDictionary *user = RTDict(info[@"user"]);
                    if (RTStr(user[@"secUid"]).length)
                        profile = [RTAwemeAPI normalizeWebProfile:@{ @"author": user, @"authorStats": RTDict(info[@"stats"]) ?: @{} }];
                    else if (detail) missing = YES;   // the page loaded, but there is no such (public) account
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (profile) { handler(profile, nil); return; }
                if (missing) { handler(nil, RTMakeError(-1, [NSString stringWithFormat:@"TikTok has no account @%@.", uniqueID])); return; }
                if (n < kRTWebAttempts) { [self userPage:uniqueID attempt:n + 1 handler:handler]; return; }
                handler(nil, error ?: RTMakeError(-1, [NSString stringWithFormat:@"Could not load @%@ (HTTP %ld).", uniqueID,
                                                                                    (long)resp.status]));
            });
        });
    }];
}

+ (NSDictionary *)normalizeWebProfile:(NSDictionary *)it
{
    NSDictionary *author = RTDict(it[@"author"]);
    NSDictionary *stats = RTDict(it[@"authorStats"]);
    if (!author) return nil;
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    p[@"author"] = RTStr(author[@"uniqueId"]) ?: @"";
    p[@"nickname"] = RTStr(author[@"nickname"]) ?: @"";
    p[@"signature"] = RTStr(author[@"signature"]) ?: @"";
    NSString *sec = RTStr(author[@"secUid"]);
    if (sec) p[@"sec_uid"] = sec;
    NSString *avatar = RTPickJPEG(@[ @[ RTStr(author[@"avatarMedium"]) ?: @"" ], @[ RTStr(author[@"avatarThumb"]) ?: @"" ] ]);
    if (avatar) p[@"avatar_url"] = avatar;
    p[@"followers"] = @(RTNum(stats[@"followerCount"]));
    p[@"following"] = @(RTNum(stats[@"followingCount"]));
    p[@"hearts"] = @(RTNum(stats[@"heartCount"]) ?: RTNum(stats[@"heart"]));
    p[@"videos"] = @(RTNum(stats[@"videoCount"]));
    return p;
}

// Same rules as normalizeAweme: H.264 only, the largest rendition up to 576 wide.
+ (NSDictionary *)normalizeWebItem:(NSDictionary *)it
{
    NSString *vid = RTStr(it[@"id"]);
    NSDictionary *video = RTDict(it[@"video"]);
    if (!vid.length || !video || it[@"imagePost"]) return nil;

    NSArray *urls = nil;
    long long chosenW = 0, chosenSize = 0, width = 0, height = 0;
    for (id entry in RTArr(video[@"bitrateInfo"])) {
        NSDictionary *b = RTDict(entry);
        if ([[RTStr(b[@"CodecType"]) lowercaseString] rangeOfString:@"h264"].location == NSNotFound) continue;
        NSDictionary *pa = RTDict(b[@"PlayAddr"]);
        NSMutableArray *list = [NSMutableArray array];
        for (id u in RTArr(pa[@"UrlList"])) if (RTStr(u).length) [list addObject:RTStr(u)];
        if (!list.count) continue;
        long long w = MIN(RTNum(pa[@"Width"]), RTNum(pa[@"Height"]));
        long long size = RTNum(pa[@"DataSize"]);
        BOOL better = !urls || (w <= 576 && (chosenW > 576 || w > chosenW)) || (w > 576 && chosenW > 576 && w < chosenW)
                   || (w == chosenW && size > 0 && size < chosenSize);
        if (better) { urls = list; chosenW = w; chosenSize = size; width = RTNum(pa[@"Width"]); height = RTNum(pa[@"Height"]); }
    }
    if (!urls && [[RTStr(video[@"codecType"]) lowercaseString] isEqualToString:@"h264"] && RTStr(video[@"playAddr"]).length)
        urls = @[ RTStr(video[@"playAddr"]) ];
    if (!urls.count) return nil;

    NSDictionary *author = RTDict(it[@"author"]);
    NSDictionary *stats = RTDict(it[@"stats"]);
    NSDictionary *music = RTDict(it[@"music"]);
    NSString *user = RTStr(author[@"uniqueId"]);
    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    item[@"id"] = vid;
    item[@"desc"] = RTStr(it[@"desc"]) ?: @"";
    item[@"author"] = user ?: @"";
    item[@"nickname"] = RTStr(author[@"nickname"]) ?: @"";
    NSString *sec = RTStr(author[@"secUid"]);
    if (sec) item[@"sec_uid"] = sec;
    item[@"create_time"] = @(RTNum(it[@"createTime"]));
    item[@"video_urls"] = urls;
    item[@"width"] = @(width ?: RTNum(video[@"width"]));
    item[@"height"] = @(height ?: RTNum(video[@"height"]));
    item[@"duration"] = @(RTNum(video[@"duration"]));
    item[@"likes"] = @(RTNum(stats[@"diggCount"]));
    item[@"comments"] = @(RTNum(stats[@"commentCount"]));
    item[@"shares"] = @(RTNum(stats[@"shareCount"]));
    item[@"plays"] = @(RTNum(stats[@"playCount"]));
    item[@"music"] = RTStr(music[@"title"]) ?: @"";
    item[@"music_author"] = RTStr(music[@"authorName"]) ?: @"";
    item[@"web_url"] = [NSString stringWithFormat:@"https://www.tiktok.com/@%@/video/%@", user ?: @"_", vid];
    // the web covers end in ".image" but are served as JPEG; originCover is 540x960, plenty for the 4S
    NSString *cover = RTStr(video[@"originCover"]).length ? RTStr(video[@"originCover"]) : RTStr(video[@"cover"]);
    if (cover.length) item[@"cover_url"] = cover;
    NSDictionary *zoom = RTDict(video[@"zoomCover"]);   // "480" is 270x480: sharp in a 3-column grid on Retina
    NSString *thumb = RTStr(zoom[@"480"]).length ? RTStr(zoom[@"480"]) : RTStr(zoom[@"240"]);
    item[@"thumb_url"] = thumb.length ? thumb : (cover ?: @"");
    NSString *avatar = RTStr(author[@"avatarThumb"]);
    if (avatar.length) item[@"avatar_url"] = avatar;
    return item;
}

+ (NSDictionary *)normalizeComment:(NSDictionary *)c
{
    NSString *cid = RTStr(c[@"cid"]);
    if (!cid.length) return nil;
    NSDictionary *user = RTDict(c[@"user"]);
    NSString *text = RTStr(c[@"text"]);
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    r[@"id"] = cid;
    r[@"text"] = text.length ? text : @"(sticker)";
    r[@"author"] = RTStr(user[@"unique_id"]) ?: @"";
    r[@"nickname"] = RTStr(user[@"nickname"]) ?: @"";
    NSString *avatar = RTPickJPEG(@[ RTURLList(user[@"avatar_thumb"]) ]);
    if (avatar) r[@"avatar_url"] = avatar;
    r[@"likes"] = @(RTNum(c[@"digg_count"]));
    r[@"replies"] = @(RTNum(c[@"reply_comment_total"]));
    r[@"time"] = @(RTNum(c[@"create_time"]));
    return r;
}

@end
