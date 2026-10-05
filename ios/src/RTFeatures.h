#import "RTCommon.h"

// Local recommendations: turns a raw aweme feed entry into feature keys the ranker and the interest profile use,
// e.g. "lang:nl", "tag:cars", "kw:vespa", "creator:name", "music:123", "len:mid", "size:small", "region:NL".
@interface RTFeatures : NSObject
+ (NSString *)languageForAweme:(NSDictionary *)aweme;    // ISO 639-1 code, "un" when unknown
+ (NSArray *)featuresForAweme:(NSDictionary *)aweme language:(NSString *)language;
+ (NSString *)typeOf:(NSString *)feature;                // the part before ':'
@end
