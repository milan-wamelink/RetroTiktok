#import "RTAppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import "RTFeedViewController.h"
#import "RTSettingsViewController.h"
#import "RTFavoritesViewController.h"
#import "RTTheme.h"
#import "RTVideoCache.h"

@interface RTTabBarController : UITabBarController
@end

@implementation RTTabBarController
- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
@end

@implementation RTAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // play sound even with the ring/silent switch on silent, like the TikTok app
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];

    [[RTVideoCache shared] prune];
    [RTTheme applyGlobalAppearance];
    [application setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:NO];

    // The pipeline test (RTMilestoneViewController) lives under Settings.
    UINavigationController *feed = [[UINavigationController alloc] initWithRootViewController:[[RTFeedViewController alloc] init]];
    UINavigationController *favorites = [[UINavigationController alloc] initWithRootViewController:[[RTFavoritesViewController alloc] init]];
    UINavigationController *settings = [[UINavigationController alloc] initWithRootViewController:[[RTSettingsViewController alloc] init]];
    RTTabBarController *tabs = [[RTTabBarController alloc] init];
    tabs.viewControllers = @[ feed, favorites, settings ];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
