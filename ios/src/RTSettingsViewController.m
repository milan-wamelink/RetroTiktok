#import "RTSettingsViewController.h"
#import "RTAwemeAPI.h"
#import "RTHTTPClient.h"
#import "RTMilestoneViewController.h"
#import "RTSettings.h"
#import "RTTheme.h"
#import "RTVideoCache.h"
#import "RTInterestProfile.h"
#import "RTLanguagesViewController.h"

enum { RTSectionSource, RTSectionForYou, RTSectionPlayback, RTSectionAbout, RTSectionCount };
enum { RTSheetCacheLimit = 1, RTSheetDiscovery, RTSheetRegion, RTAlertClearCache, RTAlertResetLearning };

static NSArray *RTFeedRegions(void)
{
    return @[ @[@"NL", @"Netherlands"], @[@"BE", @"Belgium"], @[@"DE", @"Germany"], @[@"GB", @"United Kingdom"], @[@"US", @"United States"] ];
}

@interface RTSettingsViewController () <UIAlertViewDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UISwitch *soundSwitch;
@property (nonatomic, strong) UISwitch *debugSwitch;
@property (nonatomic, strong) UISwitch *personalizedSwitch;
@end

@implementation RTSettingsViewController

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Settings";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings" image:[RTTheme tabIconSettings] tag:1];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.soundSwitch = [[UISwitch alloc] init];
    self.soundSwitch.on = [RTSettings soundOn];
    [self.soundSwitch addTarget:self action:@selector(soundChanged) forControlEvents:UIControlEventValueChanged];
    self.debugSwitch = [[UISwitch alloc] init];
    self.debugSwitch.on = [RTSettings playerDebug];
    [self.debugSwitch addTarget:self action:@selector(debugChanged) forControlEvents:UIControlEventValueChanged];
    self.personalizedSwitch = [[UISwitch alloc] init];
    self.personalizedSwitch.on = [RTSettings personalized];
    [self.personalizedSwitch addTarget:self action:@selector(personalizedChanged) forControlEvents:UIControlEventValueChanged];
}

- (void)personalizedChanged
{
    [RTSettings setPersonalized:self.personalizedSwitch.on];
    [self.tableView reloadData];
}

- (NSString *)discoveryName
{
    double d = [RTSettings discovery];
    return d < 0.25 ? @"Familiar" : d > 0.75 ? @"Experimental" : @"Balanced";
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    [self.tableView reloadData];
}

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

- (void)debugChanged
{
    [RTSettings setPlayerDebug:self.debugSwitch.on];
}

- (void)soundChanged
{
    [RTSettings setSoundOn:self.soundSwitch.on];
}

- (NSString *)cacheSummary
{
    NSString *dir = [RTVideoCache cacheDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    unsigned long long bytes = 0;
    NSUInteger count = 0;
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
        if (![name hasSuffix:@".mp4"]) continue;
        bytes += [[fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:name] error:NULL] fileSize];
        count++;
    }
    return [NSString stringWithFormat:@"%lu videos, %.1f MB", (unsigned long)count, bytes / 1048576.0];
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return RTSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case RTSectionSource: return 4;
        case RTSectionForYou: return 5;
        case RTSectionPlayback: return 2;
        default: return 2;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case RTSectionSource: return @"TikTok";
        case RTSectionForYou: return @"For You";
        case RTSectionPlayback: return @"Playback";
        default: return @"About";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == RTSectionSource)
        return @"LegacyTikTok talks to TikTok directly with its own TLS. No server or computer is needed. "
               @"The pipeline test checks every step and shows a log you can copy.";
    if (section == RTSectionForYou) {
        RTInterestProfile *p = [RTInterestProfile shared];
        return [NSString stringWithFormat:@"For You is ranked on this iPhone from what you watch, finish, replay, save or skip. "
                @"Nothing leaves the phone. Learned so far: %lu signals from %lu videos.",
                (unsigned long)p.featureCount, (unsigned long)p.viewCount];
    }
    if (section == RTSectionPlayback)
        return @"Player Debug shows each video's player state on screen, and in For You why it was picked.";
    if (section == RTSectionAbout)
        return @"LegacyTikTok is not affiliated with TikTok or ByteDance. It only shows public videos.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == RTSectionSource) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Feed";
            cell.detailTextLabel.text = @"Direct (aweme)";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Pipeline Test";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Video Cache";
            cell.detailTextLabel.text = [self cacheSummary];
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        } else {
            cell.textLabel.text = @"Cache Limit";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld MB", (long)[RTSettings cacheLimitMB]];
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        }
    } else if (indexPath.section == RTSectionForYou) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Personalized";
            cell.accessoryView = self.personalizedSwitch;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Discovery";
            cell.detailTextLabel.text = [self discoveryName];
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Languages";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Feed Region";
            cell.detailTextLabel.text = [RTSettings feedRegion];
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        } else {
            cell.textLabel.text = @"Reset Learning";
            cell.textLabel.textColor = [UIColor colorWithRed:0.8 green:0.1 blue:0.1 alpha:1];
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        }
    } else if (indexPath.section == RTSectionPlayback) {
        cell.textLabel.text = indexPath.row == 0 ? @"Sound" : @"Player Debug";
        cell.accessoryView = indexPath.row == 0 ? self.soundSwitch : self.debugSwitch;
    } else if (indexPath.row == 0) {
        cell.textLabel.text = @"Version";
        cell.detailTextLabel.text = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    } else {
        cell.textLabel.text = @"Coming Next";
        cell.detailTextLabel.text = @"Topics & keywords";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == RTSectionForYou) {
        if (indexPath.row == 1) {
            UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"How adventurous should For You be?" delegate:self
                                                      cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil
                                                      otherButtonTitles:@"Familiar", @"Balanced", @"Experimental", nil];
            sheet.tag = RTSheetDiscovery;
            sheet.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
            [sheet showFromTabBar:self.tabBarController.tabBar];
        } else if (indexPath.row == 2) {
            [self.navigationController pushViewController:[[RTLanguagesViewController alloc] init] animated:YES];
        } else if (indexPath.row == 3) {
            UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Which country's For You should TikTok send?"
                                                               delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil
                                                      otherButtonTitles:nil];
            for (NSArray *region in RTFeedRegions()) [sheet addButtonWithTitle:region[1]];
            sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
            sheet.tag = RTSheetRegion;
            sheet.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
            [sheet showFromTabBar:self.tabBarController.tabBar];
        } else if (indexPath.row == 4) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Reset Learning?"
                                                            message:@"For You forgets what it learned from your viewing and which videos you have seen. Your settings and favorites stay."
                                                           delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Reset", nil];
            alert.tag = RTAlertResetLearning;
            [alert show];
        }
        return;
    }
    if (indexPath.section != RTSectionSource) return;
    if (indexPath.row == 1) {
        RTMilestoneViewController *test = [[RTMilestoneViewController alloc] init];
        test.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:test animated:YES];
    } else if (indexPath.row == 2) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Clear Video Cache?"
                                                        message:@"Downloaded videos are deleted. They download again when you watch them."
                                                       delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Clear", nil];
        alert.tag = RTAlertClearCache;
        [alert show];
    } else if (indexPath.row == 3) {
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Keep downloaded videos up to" delegate:self
                                                  cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil
                                                  otherButtonTitles:@"10 MB", @"25 MB", @"50 MB", @"100 MB", nil];
        sheet.tag = RTSheetCacheLimit;
        sheet.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
        [sheet showFromTabBar:self.tabBarController.tabBar];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.cancelButtonIndex) return;
    if (actionSheet.tag == RTSheetRegion) {
        NSArray *regions = RTFeedRegions();
        if (buttonIndex < (NSInteger)regions.count) [RTSettings setFeedRegion:regions[(NSUInteger)buttonIndex][0]];
        [self.tableView reloadData];
        return;
    }
    if (actionSheet.tag == RTSheetDiscovery) {
        NSString *title = [actionSheet buttonTitleAtIndex:buttonIndex];
        [RTSettings setDiscovery:[title isEqualToString:@"Familiar"] ? 0 : [title isEqualToString:@"Experimental"] ? 1 : 0.5];
        [self.tableView reloadData];
        return;
    }
    [RTSettings setCacheLimitMB:[[actionSheet buttonTitleAtIndex:buttonIndex] integerValue]];
    [[RTVideoCache shared] prune];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
    [self.tableView reloadData];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;
    if (alertView.tag == RTAlertResetLearning) {
        [[RTInterestProfile shared] reset];
        [self.tableView reloadData];
        return;
    }
    NSString *dir = [RTVideoCache cacheDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL])
        if ([name hasSuffix:@".mp4"]) [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:NULL];
    [self.tableView reloadData];
}

@end
