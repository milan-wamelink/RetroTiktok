#import "RTFeatures.h"

static const NSUInteger kRTMaxTags = 8, kRTMaxWords = 8;

@implementation RTFeatures

+ (NSString *)typeOf:(NSString *)feature
{
    NSRange r = [feature rangeOfString:@":"];
    return r.location == NSNotFound ? feature : [feature substringToIndex:r.location];
}

static NSString *RTLangCode(NSString *s)
{
    s = [[RTStr(s) lowercaseString] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_"]][0];
    if ([s isEqualToString:@"in"]) return @"id";
    if ([s isEqualToString:@"iw"]) return @"he";
    if ([s isEqualToString:@"fil"]) return @"tl";
    return (s.length == 2 && ![s isEqualToString:@"un"]) ? s : nil;
}

// The caption's writing system, when it clearly isn't Latin (TikTok leaves a third of captions "un").
static NSString *RTScriptLanguage(NSString *text)
{
    NSUInteger latin = 0, arabic = 0, cyrillic = 0, hebrew = 0, thai = 0, devanagari = 0, hangul = 0, kana = 0, han = 0;
    NSUInteger n = MIN(text.length, (NSUInteger)400);
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [text characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= 0xC0 && c <= 0x24F)) latin++;
        else if ((c >= 0x0600 && c <= 0x06FF) || (c >= 0x0750 && c <= 0x077F) || (c >= 0xFB50 && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF)) arabic++;
        else if (c >= 0x0400 && c <= 0x04FF) cyrillic++;
        else if (c >= 0x0590 && c <= 0x05FF) hebrew++;
        else if (c >= 0x0E00 && c <= 0x0E7F) thai++;
        else if (c >= 0x0900 && c <= 0x097F) devanagari++;
        else if ((c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x1100 && c <= 0x11FF)) hangul++;
        else if (c >= 0x3040 && c <= 0x30FF) kana++;
        else if (c >= 0x4E00 && c <= 0x9FFF) han++;
    }
    struct { NSUInteger count; const char *code; } scripts[] = {
        { arabic, "ar" }, { cyrillic, "ru" }, { hebrew, "he" }, { thai, "th" }, { devanagari, "hi" },
        { hangul, "ko" }, { kana + (kana ? han : 0), "ja" }, { kana ? 0 : han, "zh" },
    };
    NSUInteger best = 0;
    const char *code = NULL;
    for (size_t i = 0; i < sizeof scripts / sizeof scripts[0]; i++)
        if (scripts[i].count > best) { best = scripts[i].count; code = scripts[i].code; }
    return (code && best >= 3 && best >= latin) ? @(code) : nil;
}

+ (NSString *)languageForAweme:(NSDictionary *)a
{
    return RTLangCode(a[@"desc_language"]) ?: RTScriptLanguage(RTStr(a[@"desc"]) ?: @"")
        ?: RTLangCode(RTDict(a[@"author"])[@"language"]) ?: @"un";
}

// Tags on nearly every video say nothing about it.
static BOOL RTGenericTag(NSString *t)
{
    static NSSet *generic;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        generic = [NSSet setWithObjects:@"fy", @"viral", @"viralvideo", @"viralvideos", @"trending", @"trend", @"tiktok",
                   @"parati", @"paratii", @"pourtoi", @"perte", @"fürdich", @"fyi", @"xyzbca", @"explore", @"explorepage",
                   @"capcut", @"recommendations", @"рекомендации", @"рек", @"اكسبلور", @"keşfet", @"keşfetteyiz", nil];
    });
    return t.length < 2 || [t hasPrefix:@"fyp"] || [t hasPrefix:@"foryou"] || [t hasPrefix:@"foru"] || [generic containsObject:t];
}

static NSSet *RTStopwords(void)
{
    static NSSet *words;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        words = [NSSet setWithArray:[@"this that with from have your what when just like they them their there then than "
            @"been were will would about into only some more most very much really also here make made does dont "
            @"cant isnt para pero como esto esta este todo todos cuando porque solo donde sobre tiene hace "
            @"voor niet maar zijn deze ook naar heeft wordt gewoon mijn jouw echt voor".lowercaseString
            componentsSeparatedByString:@" "]];
    });
    return words;
}

static void RTAddUnique(NSMutableArray *list, NSString *f)
{
    if (f.length && ![list containsObject:f]) [list addObject:f];
}

+ (NSArray *)featuresForAweme:(NSDictionary *)a language:(NSString *)language
{
    NSMutableArray *f = [NSMutableArray array];
    RTAddUnique(f, [@"lang:" stringByAppendingString:language ?: @"un"]);
    NSString *region = [RTStr(a[@"region"]) uppercaseString];
    if (region.length == 2) RTAddUnique(f, [@"region:" stringByAppendingString:region]);

    NSDictionary *author = RTDict(a[@"author"]);
    NSString *creator = [RTStr(author[@"unique_id"]) lowercaseString];
    if (creator.length) RTAddUnique(f, [@"creator:" stringByAppendingString:creator]);
    long long followers = RTNum(author[@"follower_count"]);
    RTAddUnique(f, followers < 10000 ? @"size:small" : followers < 500000 ? @"size:mid" : @"size:big");

    NSMutableArray *tags = [NSMutableArray array];
    for (id raw in RTArr(a[@"text_extra"])) [tags addObject:RTStr(RTDict(raw)[@"hashtag_name"]) ?: @""];
    for (id raw in RTArr(a[@"cha_list"])) [tags addObject:RTStr(RTDict(raw)[@"cha_name"]) ?: @""];
    NSUInteger tagCount = 0;
    for (NSString *raw in tags) {
        NSString *t = [raw.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (RTGenericTag(t) || tagCount >= kRTMaxTags) continue;
        NSString *key = [@"tag:" stringByAppendingString:t];
        if ([f containsObject:key]) continue;
        [f addObject:key];
        tagCount++;
    }

    NSUInteger wordCount = 0;
    NSCharacterSet *notLetters = [[NSCharacterSet letterCharacterSet] invertedSet];
    for (NSString *token in [RTStr(a[@"desc"]) ?: @"" componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
        if (wordCount >= kRTMaxWords) break;
        if ([token hasPrefix:@"#"] || [token hasPrefix:@"@"]) continue;
        for (NSString *part in [token.lowercaseString componentsSeparatedByCharactersInSet:notLetters]) {
            if (part.length < 4 || part.length > 20 || [RTStopwords() containsObject:part]) continue;
            NSString *key = [@"kw:" stringByAppendingString:part];
            if ([f containsObject:key] || [f containsObject:[@"tag:" stringByAppendingString:part]]) continue;
            [f addObject:key];
            if (++wordCount >= kRTMaxWords) break;
        }
    }

    NSDictionary *music = RTDict(a[@"music"]);
    NSString *musicID = RTStr(music[@"id_str"]) ?: (RTNum(music[@"id"]) ? [NSString stringWithFormat:@"%lld", RTNum(music[@"id"])] : nil);
    if (musicID.length && !RTBool(music[@"is_original"])) RTAddUnique(f, [@"music:" stringByAppendingString:musicID]);

    long long seconds = RTNum(RTDict(a[@"video"])[@"duration"]) / 1000;
    if (seconds > 0) RTAddUnique(f, seconds < 15 ? @"len:short" : seconds < 35 ? @"len:mid" : seconds < 70 ? @"len:long" : @"len:xlong");
    if (RTNum(RTDict(a[@"aigc_info"])[@"aigc_label_type"])) RTAddUnique(f, @"aigc:yes");
    return f;
}

@end
