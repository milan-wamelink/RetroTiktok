#import "RTAppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import "RTAPI.h"
#import "RTFeedViewController.h"
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

    UINavigationController *feed = [[UINavigationController alloc] initWithRootViewController:[[RTFeedViewController alloc] init]];
    UINavigationController *settings = [[UINavigationController alloc] initWithRootViewController:[[RTSettingsViewController alloc] init]];
    RTTabBarController *tabs = [[RTTabBarController alloc] init];
    tabs.viewControllers = @[ feed, settings ];
    if (![[RTAPI shared] hasServer]) tabs.selectedIndex = 1;

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
