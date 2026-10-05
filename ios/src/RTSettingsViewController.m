#import "RTSettingsViewController.h"
#import "RTAwemeAPI.h"
#import "RTHTTPClient.h"
#import "RTMilestoneViewController.h"
#import "RTSettings.h"
#import "RTTheme.h"
#import "RTVideoCache.h"

enum { RTSectionSource, RTSectionPlayback, RTSectionAbout, RTSectionCount };

@interface RTSettingsViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) UISwitch *soundSwitch;
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
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    [self.tableView reloadData];
}

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

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
        case RTSectionSource: return 3;
        case RTSectionPlayback: return 1;
        default: return 2;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case RTSectionSource: return @"TikTok";
        case RTSectionPlayback: return @"Playback";
        default: return @"About";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == RTSectionSource)
        return @"LegacyTikTok talks to TikTok directly with its own TLS. No server or computer is needed. "
               @"The pipeline test checks every step and shows a log you can copy.";
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
        } else {
            cell.textLabel.text = @"Video Cache";
            cell.detailTextLabel.text = [self cacheSummary];
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        }
    } else if (indexPath.section == RTSectionPlayback) {
        cell.textLabel.text = @"Sound";
        cell.accessoryView = self.soundSwitch;
    } else if (indexPath.row == 0) {
        cell.textLabel.text = @"Version";
        cell.detailTextLabel.text = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    } else {
        cell.textLabel.text = @"Coming Next";
        cell.detailTextLabel.text = @"Profiles, comments";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != RTSectionSource) return;
    if (indexPath.row == 1) {
        RTMilestoneViewController *test = [[RTMilestoneViewController alloc] init];
        test.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:test animated:YES];
    } else if (indexPath.row == 2) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Clear Video Cache?"
                                                        message:@"Downloaded videos are deleted. They download again when you watch them."
                                                       delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Clear", nil];
        [alert show];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;
    NSString *dir = [RTVideoCache cacheDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL])
        if ([name hasSuffix:@".mp4"]) [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:NULL];
    [self.tableView reloadData];
}

@end
