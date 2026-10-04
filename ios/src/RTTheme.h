#import "RTCommon.h"

// Colours and code-drawn iOS 6 artwork (glossy, embossed), so the app ships no image files besides the icon.
@interface RTTheme : NSObject
+ (UIColor *)accentColor;        // TikTok pink
+ (UIColor *)accent2Color;       // TikTok cyan
+ (UIColor *)linenColor;         // the iOS 6 linen behind the feed
+ (void)applyGlobalAppearance;

+ (UIImage *)tabIconHome;
+ (UIImage *)tabIconDiscover;
+ (UIImage *)tabIconSettings;
+ (UIImage *)heartIconFilled:(BOOL)filled;   // 36 pt, white with a soft shadow (red + gloss when filled)
+ (UIImage *)commentIcon;
+ (UIImage *)shareIcon;
+ (UIImage *)bigPlayIcon;                    // translucent play triangle shown while paused
+ (UIImage *)musicNoteIcon;
+ (UIImage *)avatarPlaceholder;
+ (UIImage *)glossyButtonWithTop:(UIColor *)top bottom:(UIColor *)bottom;   // stretchable
+ (UIImage *)bottomShadeImage;               // black fade behind the caption
@end
