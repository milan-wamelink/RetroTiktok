#import "RTSettings.h"

@implementation RTSettings

+ (NSString *)serverURL
{
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:@"serverURL"];
    return s.length ? s : nil;
}

+ (void)setServerURL:(NSString *)url
{
    NSString *s = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length && [s rangeOfString:@"://"].location == NSNotFound) s = [@"http://" stringByAppendingString:s];
    while ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    if (s.length && [[s componentsSeparatedByString:@":"] count] < 3) s = [s stringByAppendingString:@":8460"];
    [[NSUserDefaults standardUserDefaults] setObject:s ?: @"" forKey:@"serverURL"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:RTSettingsDidChangeNotification object:nil];
}

+ (NSString *)accessKey
{
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:@"accessKey"];
    return s.length ? s : nil;
}

+ (void)setAccessKey:(NSString *)key
{
    [[NSUserDefaults standardUserDefaults] setObject:key ?: @"" forKey:@"accessKey"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:RTSettingsDidChangeNotification object:nil];
}

+ (BOOL)soundOn
{
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"soundOn"];
    return v ? [v boolValue] : YES;
}

+ (void)setSoundOn:(BOOL)on
{
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"soundOn"];
    [[NSNotificationCenter defaultCenter] postNotificationName:RTSettingsDidChangeNotification object:nil];
}

+ (NSInteger)cacheLimitMB
{
    NSInteger mb = [[NSUserDefaults standardUserDefaults] integerForKey:@"cacheLimitMB"];
    return mb > 0 ? mb : 25;
}

+ (void)setCacheLimitMB:(NSInteger)mb
{
    [[NSUserDefaults standardUserDefaults] setInteger:mb forKey:@"cacheLimitMB"];
}

+ (BOOL)playerDebug
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"playerDebug"];
}
+ (void)setPlayerDebug:(BOOL)on
{
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"playerDebug"];
    [[NSNotificationCenter defaultCenter] postNotificationName:RTSettingsDidChangeNotification object:nil];
}
@end
