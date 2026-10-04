#import "RTAppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import "RTMilestoneViewController.h"
#import "RTSettingsViewController.h"
#import "RTTheme.h"

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

    [RTTheme applyGlobalAppearance];
    [application setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:NO];

    // V1 milestone 1: the on-device pipeline test. The paged feed (RTFeedViewController) is wired up after it passes.
    UINavigationController *test = [[UINavigationController alloc] initWithRootViewController:[[RTMilestoneViewController alloc] init]];
    UINavigationController *settings = [[UINavigationController alloc] initWithRootViewController:[[RTSettingsViewController alloc] init]];
    RTTabBarController *tabs = [[RTTabBarController alloc] init];
    tabs.viewControllers = @[ test, settings ];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
