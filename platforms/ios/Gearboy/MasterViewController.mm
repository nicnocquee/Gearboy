/*
 * Gearboy - Nintendo Game Boy Emulator
 * Copyright (C) 2012  Ignacio Sanchez
 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see http://www.gnu.org/licenses/
 *
 */

#import "MasterViewController.h"

#import "DetailViewController.h"

#import <DropboxSDK/DropboxSDK.h>

#import "MBProgressHUD.h"

@interface MasterViewController () <DBRestClientDelegate> {
    DBRestClient *restClient;
}

@end

@implementation MasterViewController

@synthesize listData;
@synthesize sections = _sections;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.title = @"Games";
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
            self.clearsSelectionOnViewWillAppear = NO;
            self.contentSizeForViewInPopover = CGSizeMake(320.0, 600.0);
        }
    }
    return self;
}
							
- (void)viewDidLoad
{
    [super viewDidLoad];
    
    UIRefreshControl *pullToRefreshControl = [[UIRefreshControl alloc] init];
    [pullToRefreshControl addTarget:self action:@selector(refreshList:) forControlEvents:UIControlEventValueChanged];
    [self setRefreshControl:pullToRefreshControl];
    
    self.listData = [NSMutableArray array];
    [self refreshLocal];
       
    self.sections = @[NSLocalizedString(@"Local", nil), NSLocalizedString(@"Dropbox", nil)];
    
    [self setupBarButtonItem];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait) || (interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown);
    } else {
        return (interfaceOrientation == UIInterfaceOrientationPortrait) || (interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown);
    }
}

- (void)setupBarButtonItem {
    NSString *title = NSLocalizedString(@"Link Dropbox", nil);
    if ([[DBSession sharedSession] isLinked]) {
        title = NSLocalizedString(@"Unlink Dropbox", nil);
    }
    UIBarButtonItem *leftButton = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:self action:@selector(linkUnlinkButtonTapped:)];
    [self.navigationItem setLeftBarButtonItem:leftButton];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [self.sections objectAtIndex:section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) {
        return self.listData.count;
    }
    return self.dropboxFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    
    if (indexPath.section == 0) {
        NSString* rom = [self.listData objectAtIndex:indexPath.row];
        
        cell.textLabel.text = [rom stringByDeletingPathExtension];
    } else {
        NSString *rom = [[self.dropboxFiles objectAtIndex:indexPath.row] filename];
        cell.textLabel.text = rom;
    }
    
    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    UIView* blackColorView = [[UIView alloc] init];
    blackColorView.backgroundColor = [UIColor blackColor];
    cell.selectedBackgroundView = blackColorView;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        NSString* rom = [self.listData objectAtIndex:indexPath.row];
        [self openRom:rom];
    } else {
        NSString *rom = [self pathToDownloadedRomForIndexPath:indexPath];
        if (rom) {
            [self openRom:[rom lastPathComponent]];
        } else {
            [self downloadRomFromDropboxPath:[[self.dropboxFiles objectAtIndex:indexPath.row] path] name:[[self.dropboxFiles objectAtIndex:indexPath.row] filename]];
        }
    }
}

- (void)openRom:(NSString *)rom {
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        if (!self.detailViewController) {
            self.detailViewController = [[DetailViewController alloc] initWithNibName:@"DetailViewController_iPhone" bundle:nil];
        }
        self.detailViewController.detailItem = rom;
        [self.navigationController pushViewController:self.detailViewController animated:YES];
    } else {
        self.detailViewController.detailItem = rom;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [self linkToDropbox];
    [self refreshLocal];
    [self.detailViewController.theGLViewController.theEmulator pause];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self.detailViewController.theGLViewController.theEmulator resume];
}

#pragma mark - Local

- (NSString *)romPath {
    NSArray *homeDomains = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [homeDomains objectAtIndex:0];
}

- (void)refreshLocal {
    [self.listData removeAllObjects];
    NSString *documentsDirectory = [self romPath];
    
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    NSArray *files = [fileManager contentsOfDirectoryAtPath:documentsDirectory
                                                      error:nil];
    
    for (NSString *fileName in files) {
        if (![fileName.pathExtension isEqualToString:@"gearboy"]) {
            [self.listData addObject:fileName];
        }
    }
}

#pragma mark - Dropbox

- (void)linkToDropbox {
    if (![[DBSession sharedSession] isLinked]) {
        [[DBSession sharedSession] linkFromController:self];
    } else {
        [self dropboxDidLinked];
    }
}

- (void)dropboxDidLinked {
    [self setupBarButtonItem];
    [[self restClient] loadMetadata:@"/"];
}

- (DBRestClient *)restClient {
    if (!restClient) {
        restClient =
        [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
        restClient.delegate = self;
    }
    return restClient;
}

- (void)restClient:(DBRestClient *)client loadedMetadata:(DBMetadata *)metadata {
    if (metadata.isDirectory) {
        NSLog(@"Folder '%@' contains:", metadata.path);
        self.dropboxFiles = [NSMutableArray arrayWithArray:metadata.contents];
        [self.tableView reloadData];
        for (DBMetadata *file in metadata.contents) {
            NSLog(@"\t%@", file.filename);
        }
    }
    [self.refreshControl endRefreshing];
}

- (void)restClient:(DBRestClient *)client loadMetadataFailedWithError:(NSError *)error {
    
    NSLog(@"Error loading metadata: %@", error);
    [self.refreshControl endRefreshing];
}

- (NSString *)pathToDownloadedRomForIndexPath:(NSIndexPath *)indexPath {
    DBMetadata *file = [self.dropboxFiles objectAtIndex:indexPath.row];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[[self romPath] stringByAppendingPathComponent:file.filename]]) {
        return [[self romPath] stringByAppendingPathComponent:file.filename];
    }
    return nil;
}

- (void)downloadRomFromDropboxPath:(NSString *)path name:(NSString *)fileName{
    [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
    [[self restClient] loadFile:path intoPath:[[self romPath] stringByAppendingPathComponent:fileName]];
}

- (void)restClient:(DBRestClient*)client loadedFile:(NSString*)localPath {
    [MBProgressHUD hideHUDForView:self.navigationController.view animated:YES];
    NSLog(@"File loaded into path: %@", [localPath lastPathComponent]);
    [self openRom:[localPath lastPathComponent]];
}

- (void)restClient:(DBRestClient*)client loadFileFailedWithError:(NSError*)error {
    [MBProgressHUD hideHUDForView:self.navigationController.view animated:YES];
    NSLog(@"There was an error loading the file - %@", error);
}

- (void)refreshList:(id)sender {
    [self refreshLocal];
    [self dropboxDidLinked];
}

#pragma mark - Button

- (void)linkUnlinkButtonTapped:(id)sender {
    if ([[DBSession sharedSession] isLinked]) {
        [[DBSession sharedSession] unlinkAll];
        [self setupBarButtonItem];
    } else {
        [self linkToDropbox];
    }
}

@end
