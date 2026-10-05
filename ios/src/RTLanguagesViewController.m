#import "RTLanguagesViewController.h"
#import "RTSettings.h"

@interface RTLanguagesViewController () <UIActionSheetDelegate>
@property (nonatomic, strong) NSArray *languages;   // @[code, name]
@property (nonatomic, copy) NSString *editingCode;   // not "editing": that is UIViewController's BOOL
@end

@implementation RTLanguagesViewController

+ (NSString *)nameForLevel:(NSInteger)level
{
    switch (level) {
        case RTLevelPrefer: return @"Prefer";
        case RTLevelReduce: return @"Reduce";
        case RTLevelBlock: return @"Block";
        default: return @"Normal";
    }
}

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Languages";
        _languages = @[ @[@"nl", @"Dutch"], @[@"en", @"English"], @[@"de", @"German"], @[@"fr", @"French"],
                        @[@"es", @"Spanish"], @[@"pt", @"Portuguese"], @[@"it", @"Italian"], @[@"pl", @"Polish"],
                        @[@"tr", @"Turkish"], @[@"ar", @"Arabic"], @[@"ru", @"Russian"], @[@"uk", @"Ukrainian"],
                        @[@"he", @"Hebrew"], @[@"hi", @"Hindi"], @[@"id", @"Indonesian"], @[@"tl", @"Filipino"],
                        @[@"vi", @"Vietnamese"], @[@"th", @"Thai"], @[@"ko", @"Korean"], @[@"ja", @"Japanese"],
                        @[@"zh", @"Chinese"], @[@"un", @"Unknown / no text"] ];
    }
    return self;
}

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.languages.count; }

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return @"Prefer and Reduce move videos up or down; what you actually watch can still outweigh them. "
           @"Block hides a language completely. Languages not listed count as Normal.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"lang"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"lang"];
    NSArray *lang = self.languages[(NSUInteger)indexPath.row];
    RTLevel level = [RTSettings levelForLanguage:lang[0]];
    cell.textLabel.text = lang[1];
    cell.detailTextLabel.text = [RTLanguagesViewController nameForLevel:level];
    cell.detailTextLabel.textColor = level == RTLevelBlock ? [UIColor colorWithRed:0.8 green:0.1 blue:0.1 alpha:1]
                                   : level == RTLevelPrefer ? [UIColor colorWithRed:0.1 green:0.5 blue:0.1 alpha:1]
                                   : [UIColor colorWithRed:0.22 green:0.33 blue:0.53 alpha:1];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *lang = self.languages[(NSUInteger)indexPath.row];
    self.editingCode = lang[0];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:lang[1] delegate:self cancelButtonTitle:@"Cancel"
                                         destructiveButtonTitle:@"Block" otherButtonTitles:@"Prefer", @"Normal", @"Reduce", nil];
    sheet.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
    [sheet showInView:self.view.window ?: self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.cancelButtonIndex || !self.editingCode) return;
    NSString *title = [actionSheet buttonTitleAtIndex:buttonIndex];
    RTLevel level = [title isEqualToString:@"Block"] ? RTLevelBlock : [title isEqualToString:@"Prefer"] ? RTLevelPrefer
                  : [title isEqualToString:@"Reduce"] ? RTLevelReduce : RTLevelNormal;
    [RTSettings setLevel:level forLanguage:self.editingCode];
    self.editingCode = nil;
    [self.tableView reloadData];
}

@end
