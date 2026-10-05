#import "RTDiscoverViewController.h"
#import "RTAwemeAPI.h"
#import "RTProfileViewController.h"
#import "RTTheme.h"

static NSString * const kRTRecentKey = @"recent_searches";
static const NSUInteger kRTRecentMax = 10;

@interface RTDiscoverViewController () <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSArray *actions;       // @"tag" / @"user", for the current query
@property (nonatomic, strong) NSArray *suggestions;
@property (nonatomic, strong) NSArray *recent;
@property (nonatomic, copy) NSString *busyAction;
@property (nonatomic, assign) NSUInteger suggestionSeq;
@end

@implementation RTDiscoverViewController

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Discover";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Discover" image:[RTTheme tabIconDiscover] tag:1];
        _query = @"";
        _actions = @[];
        _suggestions = @[];
        _recent = RTArr([[NSUserDefaults standardUserDefaults] arrayForKey:kRTRecentKey]) ?: @[];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 44)];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"#hashtag or @username";
    self.searchBar.tintColor = [UIColor colorWithWhite:0.25 alpha:1];
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableHeaderView = self.searchBar;
    self.tableView.tableFooterView = [[UIView alloc] init];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    NSIndexPath *sel = self.tableView.indexPathForSelectedRow;
    if (sel) [self.tableView deselectRowAtIndexPath:sel animated:animated];
}

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

#pragma mark Query

static NSString *RTTagName(NSString *q)
{
    NSMutableString *s = [NSMutableString string];
    [q enumerateSubstringsInRange:NSMakeRange(0, q.length) options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString *ch, NSRange r, NSRange e, BOOL *stop) {
        unichar c = [ch characterAtIndex:0];
        if (c == '_' || [[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) [s appendString:ch];
    }];
    return s;
}

static NSString *RTUserName(NSString *q)
{
    NSString *s = [q hasPrefix:@"@"] ? [q substringFromIndex:1] : q;
    s = [s stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (s.length < 2 || s.length > 24) return nil;
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:
                          @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._"];
    return [s rangeOfCharacterFromSet:[ok invertedSet]].location == NSNotFound ? s : nil;
}

- (void)setQueryText:(NSString *)text
{
    self.query = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] ?: @"";
    NSMutableArray *a = [NSMutableArray array];
    if (RTTagName(self.query).length) [a addObject:@"tag"];
    if (RTUserName(self.query)) {
        if ([self.query hasPrefix:@"@"]) [a insertObject:@"user" atIndex:0];
        else [a addObject:@"user"];
    }
    self.actions = a;
    if (!self.query.length) self.suggestions = @[];
    [self.tableView reloadData];
    [self scheduleSuggestions];
}

- (void)scheduleSuggestions
{
    NSUInteger seq = ++self.suggestionSeq;
    NSString *q = [self.query stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"#@ "]];
    if (q.length < 2) return;
    // wait for a pause in typing; only the latest request may update the list
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (seq != self.suggestionSeq) return;
        [[RTAwemeAPI shared] loadSuggestions:q handler:^(NSArray *words, NSError *error) {
            if (seq != self.suggestionSeq || error) return;
            self.suggestions = words;
            [self.tableView reloadData];
        }];
    });
}

- (void)remember:(NSString *)entry
{
    NSMutableArray *r = [self.recent mutableCopy];
    [r removeObject:entry];
    [r insertObject:entry atIndex:0];
    while (r.count > kRTRecentMax) [r removeLastObject];
    self.recent = r;
    [[NSUserDefaults standardUserDefaults] setObject:r forKey:kRTRecentKey];
}

#pragma mark Search bar

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [self setQueryText:searchText];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
    [searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar
{
    [searchBar setShowsCancelButton:NO animated:YES];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    searchBar.text = @"";
    [self setQueryText:@""];
    [searchBar resignFirstResponder];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
    if (self.actions.count) [self open:self.actions[0]];
}

#pragma mark Opening

- (void)open:(NSString *)action
{
    if (self.busyAction) return;
    self.busyAction = action;
    [self.tableView reloadData];
    if ([action isEqualToString:@"tag"]) {
        NSString *name = RTTagName(self.query);
        [[RTAwemeAPI shared] lookupHashtag:name handler:^(NSDictionary *tag, NSError *error) {
            self.busyAction = nil;
            [self.tableView reloadData];
            if (error) { RTAlert(@"Hashtag", error.localizedDescription); return; }
            [self remember:[@"#" stringByAppendingString:RTStr(tag[@"title"]) ?: name]];
            [self.tableView reloadData];
            [self.navigationController pushViewController:[[RTProfileViewController alloc] initWithHashtag:tag] animated:YES];
        }];
    } else {
        NSString *name = RTUserName(self.query);
        [[RTAwemeAPI shared] lookupUser:name handler:^(NSDictionary *profile, NSError *error) {
            self.busyAction = nil;
            [self.tableView reloadData];
            if (error) { RTAlert(@"Creator", error.localizedDescription); return; }
            [self remember:[@"@" stringByAppendingString:RTStr(profile[@"author"]) ?: name]];
            [self.tableView reloadData];
            [self.navigationController pushViewController:[[RTProfileViewController alloc] initWithItem:profile] animated:YES];
        }];
    }
}

#pragma mark Table

// With a query: 0 = hashtag / creator rows, 1 = suggestions. Without: 0 = recent searches.
- (BOOL)searching { return self.query.length > 0; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.searching ? 2 : 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (!self.searching) return (NSInteger)self.recent.count;
    return (NSInteger)(section == 0 ? self.actions.count : self.suggestions.count);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (!self.searching) return self.recent.count ? @"Recent" : nil;
    return section == 1 && self.suggestions.count ? @"Suggestions" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (!self.searching && !self.recent.count)
        return @"Search a hashtag to see its videos, or type a creator's exact username to open their profile.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
    cell.detailTextLabel.text = nil;
    NSUInteger row = (NSUInteger)indexPath.row;

    if (!self.searching) {
        cell.textLabel.text = self.recent[row];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 0) {
        NSString *action = self.actions[row];
        BOOL tag = [action isEqualToString:@"tag"];
        cell.textLabel.text = tag ? [@"#" stringByAppendingString:RTTagName(self.query)]
                                  : [@"@" stringByAppendingString:RTUserName(self.query) ?: @""];
        cell.detailTextLabel.text = tag ? @"Hashtag videos" : @"Creator profile";
        if ([self.busyAction isEqualToString:action]) {
            UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            [spin startAnimating];
            cell.accessoryView = spin;
        } else {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else {
        cell.textLabel.text = self.suggestions[row];
        cell.textLabel.font = [UIFont systemFontOfSize:17];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSUInteger row = (NSUInteger)indexPath.row;
    if (!self.searching) {
        // "#tag" / "@user": run it again
        NSString *entry = self.recent[row];
        self.searchBar.text = entry;
        [self setQueryText:entry];
        [self open:[entry hasPrefix:@"@"] ? @"user" : @"tag"];
    } else if (indexPath.section == 0) {
        [self.searchBar resignFirstResponder];
        [self open:self.actions[row]];
    } else {
        NSString *word = self.suggestions[row];
        self.searchBar.text = word;
        [self setQueryText:word];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return !self.searching;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
                                            forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete || self.searching) return;
    NSMutableArray *r = [self.recent mutableCopy];
    [r removeObjectAtIndex:(NSUInteger)indexPath.row];
    self.recent = r;
    [[NSUserDefaults standardUserDefaults] setObject:r forKey:kRTRecentKey];
    [tableView reloadData];
}

@end
