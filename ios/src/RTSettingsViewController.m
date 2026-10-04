#import "RTSettingsViewController.h"
#import "RTAPI.h"
#import "RTSettings.h"
#import "RTTheme.h"

enum { RTSectionServer, RTSectionPlayback, RTSectionAbout, RTSectionCount };

@interface RTSettingsViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *serverField;
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UISwitch *soundSwitch;
@property (nonatomic, copy) NSString *status;
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

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text
{
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 190, 24)];
    f.placeholder = placeholder;
    f.text = text;
    f.textColor = [UIColor colorWithRed:0.22 green:0.33 blue:0.53 alpha:1];
    f.font = [UIFont systemFontOfSize:16];
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.returnKeyType = UIReturnKeyDone;
    f.delegate = self;
    return f;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.serverField = [self fieldWithPlaceholder:@"192.168.1.20:8460" text:[RTSettings serverURL]];
    self.serverField.keyboardType = UIKeyboardTypeURL;
    self.keyField = [self fieldWithPlaceholder:@"optional" text:[RTSettings accessKey]];
    self.keyField.secureTextEntry = YES;
    self.soundSwitch = [[UISwitch alloc] init];
    self.soundSwitch.on = [RTSettings soundOn];
    [self.soundSwitch addTarget:self action:@selector(soundChanged) forControlEvents:UIControlEventValueChanged];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    [self checkServer];
}

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

- (void)checkServer
{
    if (![[RTAPI shared] hasServer]) {
        self.status = @"Not set";
        [self.tableView reloadData];
        return;
    }
    self.status = @"Checking...";
    [self.tableView reloadData];
    [[RTAPI shared] GET:@"/api/status" timeout:10 handler:^(id json, NSError *error) {
        NSString *version = RTStr(RTDict(json)[@"version"]);
        self.status = error ? @"Not reachable" : [NSString stringWithFormat:@"Connected (v%@)", version];
        [self.tableView reloadData];
    }];
}

- (void)soundChanged
{
    [RTSettings setSoundOn:self.soundSwitch.on];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    if (textField == self.serverField) {
        [RTSettings setServerURL:textField.text];
        textField.text = [RTSettings serverURL];
    } else {
        [RTSettings setAccessKey:textField.text];
    }
    [self checkServer];
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return RTSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case RTSectionServer: return 3;
        case RTSectionPlayback: return 1;
        default: return 2;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case RTSectionServer: return @"RetroTok Server";
        case RTSectionPlayback: return @"Playback";
        default: return @"About";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == RTSectionServer)
        return @"Run the RetroTok server on a computer or Raspberry Pi on your Wi-Fi (python3 -m retrotok). It talks to TikTok and converts every video so iOS 6 can play it.";
    if (section == RTSectionAbout)
        return @"RetroTok is not affiliated with TikTok or ByteDance. It only shows public videos.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == RTSectionServer) {
        if (indexPath.row == 0) { cell.textLabel.text = @"Address"; cell.accessoryView = self.serverField; }
        else if (indexPath.row == 1) { cell.textLabel.text = @"Access Key"; cell.accessoryView = self.keyField; }
        else {
            cell.textLabel.text = @"Status";
            cell.detailTextLabel.text = self.status;
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
    if (indexPath.section == RTSectionServer && indexPath.row == 2) [self checkServer];
}

@end
