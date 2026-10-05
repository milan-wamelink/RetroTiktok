#import "RTTheme.h"

static UIColor *RGB(int r, int g, int b) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1]; }

static UIImage *RTDraw(CGSize size, void (^draw)(CGContextRef ctx))
{
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    draw(UIGraphicsGetCurrentContext());
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static void RTGradient(CGContextRef ctx, CGRect rect, UIColor *top, UIColor *bottom)
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[ (id)top.CGColor, (id)bottom.CGColor ];
    CGGradientRef g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(ctx, g, CGPointMake(0, CGRectGetMinY(rect)), CGPointMake(0, CGRectGetMaxY(rect)), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(space);
}

static UIBezierPath *RTHeartPath(CGRect r)
{
    CGFloat w = r.size.width, h = r.size.height, x = r.origin.x, y = r.origin.y;
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(x + w / 2, y + h)];
    [p addCurveToPoint:CGPointMake(x, y + h * 0.3) controlPoint1:CGPointMake(x + w * 0.2, y + h * 0.78) controlPoint2:CGPointMake(x, y + h * 0.55)];
    [p addCurveToPoint:CGPointMake(x + w / 2, y + h * 0.18) controlPoint1:CGPointMake(x, y - h * 0.05) controlPoint2:CGPointMake(x + w * 0.42, y - h * 0.02)];
    [p addCurveToPoint:CGPointMake(x + w, y + h * 0.3) controlPoint1:CGPointMake(x + w * 0.58, y - h * 0.02) controlPoint2:CGPointMake(x + w, y - h * 0.05)];
    [p addCurveToPoint:CGPointMake(x + w / 2, y + h) controlPoint1:CGPointMake(x + w, y + h * 0.55) controlPoint2:CGPointMake(x + w * 0.8, y + h * 0.78)];
    [p closePath];
    return p;
}

// A white glyph with the soft black shadow the overlay icons need over bright video.
static UIImage *RTOverlayIcon(CGFloat side, void (^shape)(CGContextRef ctx, CGRect box))
{
    return RTDraw(CGSizeMake(side, side), ^(CGContextRef ctx) {
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 3, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
        shape(ctx, CGRectInset(CGRectMake(0, 0, side, side), 4, 4));
    });
}

@implementation RTTheme

+ (UIColor *)accentColor { return RGB(254, 44, 85); }
+ (UIColor *)accent2Color { return RGB(37, 244, 238); }

+ (UIColor *)linenColor
{
    static UIColor *linen;
    if (!linen) {
        // a small procedural linen tile: dark grey with crossing light/dark fibres
        UIImage *tile = RTDraw(CGSizeMake(64, 64), ^(CGContextRef ctx) {
            [RGB(32, 33, 36) setFill];
            CGContextFillRect(ctx, CGRectMake(0, 0, 64, 64));
            srandom(7);
            for (int i = 0; i < 260; i++) {
                CGFloat a = (random() % 100) / 1000.0 + 0.02;
                BOOL light = random() % 2;
                CGContextSetRGBStrokeColor(ctx, light, light, light, a);
                CGContextSetLineWidth(ctx, 0.5);
                CGFloat p = random() % 64, s = random() % 64, len = 6 + random() % 20;
                if (i % 2) { CGContextMoveToPoint(ctx, s, p); CGContextAddLineToPoint(ctx, s + len, p); }
                else { CGContextMoveToPoint(ctx, p, s); CGContextAddLineToPoint(ctx, p, s + len); }
                CGContextStrokePath(ctx);
            }
        });
        linen = [UIColor colorWithPatternImage:tile];
    }
    return linen;
}

+ (void)applyGlobalAppearance
{
    [[UINavigationBar appearance] setTintColor:RGB(28, 28, 30)];
    [[UIToolbar appearance] setTintColor:RGB(28, 28, 30)];
    [[UISearchBar appearance] setTintColor:RGB(40, 40, 44)];
    [[UITabBar appearance] setSelectedImageTintColor:[self accent2Color]];
    [[UISegmentedControl appearance] setTintColor:RGB(48, 48, 52)];
    [[UISwitch appearance] setOnTintColor:[self accentColor]];
}

#pragma mark Tab icons (alpha masks; the tab bar adds the glossy blue/grey itself)

+ (UIImage *)tabIconHome
{
    return RTDraw(CGSizeMake(30, 30), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(15, 3)];
        [p addLineToPoint:CGPointMake(28, 15)];
        [p addLineToPoint:CGPointMake(24, 15)];
        [p addLineToPoint:CGPointMake(24, 27)];
        [p addLineToPoint:CGPointMake(18, 27)];
        [p addLineToPoint:CGPointMake(18, 19)];
        [p addLineToPoint:CGPointMake(12, 19)];
        [p addLineToPoint:CGPointMake(12, 27)];
        [p addLineToPoint:CGPointMake(6, 27)];
        [p addLineToPoint:CGPointMake(6, 15)];
        [p addLineToPoint:CGPointMake(2, 15)];
        [p closePath];
        [[UIColor blackColor] setFill];
        [p fill];
    });
}

+ (UIImage *)tabIconDiscover
{
    return RTDraw(CGSizeMake(30, 30), ^(CGContextRef ctx) {
        [[UIColor blackColor] set];
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(4, 4, 16, 16)];
        circle.lineWidth = 3.5;
        [circle stroke];
        UIBezierPath *handle = [UIBezierPath bezierPath];
        [handle moveToPoint:CGPointMake(18, 18)];
        [handle addLineToPoint:CGPointMake(26, 26)];
        handle.lineWidth = 5;
        handle.lineCapStyle = kCGLineCapRound;
        [handle stroke];
    });
}

+ (UIImage *)tabIconFavorites
{
    return RTDraw(CGSizeMake(30, 30), ^(CGContextRef ctx) {
        [[UIColor blackColor] setFill];
        [RTHeartPath(CGRectMake(3, 4, 24, 22)) fill];
    });
}

+ (UIImage *)tabIconSettings
{
    return RTDraw(CGSizeMake(30, 30), ^(CGContextRef ctx) {
        [[UIColor blackColor] setFill];
        CGContextTranslateCTM(ctx, 15, 15);
        for (int i = 0; i < 8; i++) {
            CGContextFillRect(ctx, CGRectMake(-2.5, -13, 5, 6));
            CGContextRotateCTM(ctx, M_PI / 4);
        }
        UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-9, -9, 18, 18)];
        [ring appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-4, -4, 8, 8)]];
        ring.usesEvenOddFillRule = YES;
        [ring fill];
    });
}

#pragma mark Overlay icons

+ (UIImage *)heartIconFilled:(BOOL)filled
{
    return RTOverlayIcon(40, ^(CGContextRef ctx, CGRect box) {
        UIBezierPath *heart = RTHeartPath(CGRectInset(box, 1, 3));
        if (!filled) {
            [[UIColor whiteColor] setFill];
            [heart fill];
            return;
        }
        [RGB(254, 44, 85) setFill];
        [heart fill];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
        CGContextSaveGState(ctx);
        [heart addClip];
        RTGradient(ctx, CGRectMake(0, box.origin.y, 40, box.size.height * 0.55),
                   [UIColor colorWithWhite:1 alpha:0.65], [UIColor colorWithWhite:1 alpha:0.08]);
        CGContextRestoreGState(ctx);
    });
}

+ (UIImage *)commentIcon
{
    return RTOverlayIcon(40, ^(CGContextRef ctx, CGRect box) {
        UIBezierPath *bubble = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(box.origin.x, box.origin.y + 2, box.size.width, box.size.height * 0.78)];
        UIBezierPath *tail = [UIBezierPath bezierPath];
        [tail moveToPoint:CGPointMake(box.origin.x + 8, box.origin.y + box.size.height * 0.6)];
        [tail addLineToPoint:CGPointMake(box.origin.x + 4, CGRectGetMaxY(box))];
        [tail addLineToPoint:CGPointMake(box.origin.x + 17, box.origin.y + box.size.height * 0.74)];
        [tail closePath];
        [bubble appendPath:tail];
        [[UIColor whiteColor] setFill];
        [bubble fill];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
        [RGB(60, 60, 64) setFill];
        CGFloat cy = box.origin.y + 2 + box.size.height * 0.39;
        for (int i = -1; i <= 1; i++) CGContextFillEllipseInRect(ctx, CGRectMake(CGRectGetMidX(box) + i * 8 - 2.5, cy - 2.5, 5, 5));
    });
}

+ (UIImage *)shareIcon
{
    return RTOverlayIcon(40, ^(CGContextRef ctx, CGRect box) {
        UIBezierPath *arrow = [UIBezierPath bezierPath];
        CGFloat x = box.origin.x, y = box.origin.y, w = box.size.width, h = box.size.height;
        [arrow moveToPoint:CGPointMake(x + w, y + h * 0.42)];
        [arrow addLineToPoint:CGPointMake(x + w * 0.56, y + h * 0.05)];
        [arrow addLineToPoint:CGPointMake(x + w * 0.56, y + h * 0.26)];
        [arrow addCurveToPoint:CGPointMake(x, y + h * 0.92) controlPoint1:CGPointMake(x + w * 0.15, y + h * 0.3) controlPoint2:CGPointMake(x, y + h * 0.6)];
        [arrow addCurveToPoint:CGPointMake(x + w * 0.56, y + h * 0.58) controlPoint1:CGPointMake(x + w * 0.18, y + h * 0.65) controlPoint2:CGPointMake(x + w * 0.38, y + h * 0.58)];
        [arrow addLineToPoint:CGPointMake(x + w * 0.56, y + h * 0.8)];
        [arrow closePath];
        [[UIColor whiteColor] setFill];
        [arrow fill];
    });
}

+ (UIImage *)bigPlayIcon
{
    return RTDraw(CGSizeMake(80, 80), ^(CGContextRef ctx) {
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, 2), 6, [UIColor colorWithWhite:0 alpha:0.5].CGColor);
        UIBezierPath *tri = [UIBezierPath bezierPath];
        [tri moveToPoint:CGPointMake(24, 14)];
        [tri addLineToPoint:CGPointMake(66, 40)];
        [tri addLineToPoint:CGPointMake(24, 66)];
        [tri closePath];
        [[UIColor colorWithWhite:1 alpha:0.75] setFill];
        [tri fill];
    });
}

+ (UIImage *)musicNoteIcon
{
    return RTDraw(CGSizeMake(14, 14), ^(CGContextRef ctx) {
        [[UIColor whiteColor] setFill];
        CGContextFillEllipseInRect(ctx, CGRectMake(1, 9, 5, 4));
        CGContextFillEllipseInRect(ctx, CGRectMake(8, 7.5, 5, 4));
        CGContextFillRect(ctx, CGRectMake(5, 2, 1.3, 9));
        CGContextFillRect(ctx, CGRectMake(12, 0.5, 1.3, 9));
        CGContextFillRect(ctx, CGRectMake(5, 1, 8.3, 2.2));
    });
}

+ (UIImage *)avatarPlaceholder
{
    return RTDraw(CGSizeMake(48, 48), ^(CGContextRef ctx) {
        RTGradient(ctx, CGRectMake(0, 0, 48, 48), RGB(120, 124, 132), RGB(70, 72, 78));
        [[UIColor colorWithWhite:1 alpha:0.7] setFill];
        CGContextFillEllipseInRect(ctx, CGRectMake(16, 9, 16, 16));
        CGContextFillEllipseInRect(ctx, CGRectMake(8, 28, 32, 28));
    });
}

+ (UIImage *)glossyButtonWithTop:(UIColor *)top bottom:(UIColor *)bottom
{
    UIImage *img = RTDraw(CGSizeMake(24, 32), ^(CGContextRef ctx) {
        UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5, 0.5, 23, 31) cornerRadius:6];
        CGContextSaveGState(ctx);
        [shape addClip];
        RTGradient(ctx, CGRectMake(0, 0, 24, 32), top, bottom);
        [[UIColor colorWithWhite:1 alpha:0.2] setFill];
        CGContextFillRect(ctx, CGRectMake(0, 0, 24, 16));
        CGContextRestoreGState(ctx);
        [[UIColor colorWithWhite:0 alpha:0.45] setStroke];
        [shape stroke];
    });
    return [img resizableImageWithCapInsets:UIEdgeInsetsMake(10, 10, 10, 10)];
}

+ (UIImage *)bottomShadeImage
{
    UIImage *img = RTDraw(CGSizeMake(2, 160), ^(CGContextRef ctx) {
        RTGradient(ctx, CGRectMake(0, 0, 2, 160), [UIColor colorWithWhite:0 alpha:0], [UIColor colorWithWhite:0 alpha:0.65]);
    });
    return [img resizableImageWithCapInsets:UIEdgeInsetsMake(0, 0, 0, 0)];
}

@end
