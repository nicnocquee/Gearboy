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
    BOOL isDownloadingSaveFile;
    BOOL isDownloadingROM;
    BOOL isSyncingSaveFile;
    UIBackgroundTaskIdentifier backgroundTaskIdentifier;
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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
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
            [self downloadRomFromDropboxFile:[self.dropboxFiles objectAtIndex:indexPath.row]];
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
    if (self.detailViewController.detailItem) {
        [self syncSaveFileForROM:self.detailViewController.detailItem];
    }
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
        if ([fileName.pathExtension isEqualToString:@"gb"] || [fileName.pathExtension isEqualToString:@"gbc"]) { // let's just show gb and gbc
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
        self.allDropboxFiles = [NSMutableArray arrayWithArray:metadata.contents];
        if (!self.dropboxFiles) {
            self.dropboxFiles = [NSMutableArray array];
        } else [self.dropboxFiles removeAllObjects];
        
        if (!self.saveFiles) {
            self.saveFiles = [NSMutableDictionary dictionary];
        } else [self.saveFiles removeAllObjects];
        
        for (DBMetadata *file in metadata.contents) {
            NSLog(@"\t%@", file.filename);
            if ([file.filename.pathExtension isEqualToString:@"gb"]||[file.filename.pathExtension isEqualToString:@"gbc"]) {
                [self.dropboxFiles addObject:file];
            } else if ([file.filename.pathExtension isEqualToString:@"gearboy"]) {
                [self.saveFiles setObject:file forKey:file.filename];
            }
        }
        [self.tableView reloadData];
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

- (void)downloadRomFromDropboxFile:(DBMetadata *)dropboxFile{
    [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
    isDownloadingROM = YES;
    [[self restClient] loadFile:dropboxFile.path intoPath:[[self romPath] stringByAppendingPathComponent:dropboxFile.filename]];
    
    if ([self.saveFiles.allKeys containsObject:[dropboxFile.filename stringByAppendingPathExtension:@"gearboy"]]) {
        NSLog(@"Downloading save data too ...");
        DBMetadata *saveFile = [self.saveFiles objectForKey:[dropboxFile.filename stringByAppendingPathExtension:@"gearboy"]];
        isDownloadingSaveFile = YES;
        [[self restClient] loadFile:saveFile.path
                           intoPath:[[self romPath] stringByAppendingPathComponent:saveFile.filename]];
    }
    
     
}

- (void)restClient:(DBRestClient*)client loadedFile:(NSString*)localPath {
    NSLog(@"File loaded into path: %@", [localPath lastPathComponent]);
    if (![localPath.pathExtension isEqualToString:@"gearboy"]) {
        isDownloadingROM = NO;
        if (!isDownloadingSaveFile) {
            [MBProgressHUD hideHUDForView:self.navigationController.view animated:YES];
            [self openRom:[localPath lastPathComponent]];
        }
    } else {
        isDownloadingSaveFile = NO;
        if (!isDownloadingROM) {
            [MBProgressHUD hideHUDForView:self.navigationController.view animated:YES];
            [self openRom:[[localPath lastPathComponent] stringByDeletingPathExtension]];
        }
    }
    
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

#pragma mark - Enter background

- (void)appWillEnterBackground:(NSNotification *)notification {
    if (isSyncingSaveFile) {
        
    }
}

- (void)syncSaveFileForROM:(NSString *)rom {
    NSString *saveFile = [rom stringByAppendingPathExtension:@"gearboy"];
    NSString *pathToSaveFile = [[self romPath] stringByAppendingPathComponent:saveFile];
    NSLog(@"Sync save file: %@ in path: %@", saveFile, pathToSaveFile);
    if ([[NSFileManager defaultManager] fileExistsAtPath:pathToSaveFile]) {
        NSString *rev = nil;
        if ([self.saveFiles.allKeys containsObject:saveFile]) {
            DBMetadata *file = [self.saveFiles objectForKey:saveFile];
            rev = file.rev;
        }
        isSyncingSaveFile = YES;
        [[self restClient] uploadFile:saveFile
                               toPath:@"/"
                        withParentRev:rev
                             fromPath:pathToSaveFile];
    }
}

- (void)syncSaveFileOfCurrentROMWithBackgroundIdentifier:(UIBackgroundTaskIdentifier)identifier {
    if (!isSyncingSaveFile) {
        if (self.detailViewController.detailItem) {
            [self.detailViewController.theGLViewController.theEmulator pause];
            backgroundTaskIdentifier = identifier;
            [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
            [self syncSaveFileForROM:self.detailViewController.detailItem];
        }
    }
}

#pragma mark - Upload delegate

- (void)restClient:(DBRestClient*)client uploadedFile:(NSString*)destPath
              from:(NSString*)srcPath metadata:(DBMetadata*)metadata {
    isSyncingSaveFile = NO;
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    NSLog(@"File uploaded successfully to path: %@", metadata.path);
    if (backgroundTaskIdentifier != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
        backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    }
}

- (void)restClient:(DBRestClient*)client uploadFileFailedWithError:(NSError*)error {
    isSyncingSaveFile = NO;
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    NSLog(@"File upload failed with error - %@", error);
    if (backgroundTaskIdentifier != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
        backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    }
}

@end
