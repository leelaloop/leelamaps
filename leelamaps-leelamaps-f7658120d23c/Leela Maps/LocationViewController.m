//
//  LocationViewController.m
//  Leela Maps
//
//  Created by Gregory Hazel on 11/5/17.
//  Copyright © 2017 Leela Maps. All rights reserved.
//

#import "LocationViewController.h"
#import "AppDelegate.h"
#import "NSAttributedString+Twitterify.h"
#import "LocationEditViewController.h"
#import "MapViewController.h"
#import "SearchTable.h"

@import CoreLocation;


@interface LocationViewController () <UICloudSharingControllerDelegate, UIPopoverPresentationControllerDelegate, UITextViewDelegate>
@property (weak, nonatomic) IBOutlet UITextView *address;
@property (weak, nonatomic) IBOutlet UITextView *desc;
@property (weak, nonatomic) IBOutlet UILabel *owner;
@property (weak, nonatomic) IBOutlet UILabel *memberList;
@property (weak, nonatomic) IBOutlet UILabel *instructions;
@end

@implementation LocationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = nil;
    _address.text = nil;
    _desc.text = nil;
    _owner.text = nil;
    _memberList.text = nil;
    _instructions.text = nil;
    self.location = _location;
    self.share = _share;
}

- (void)updateBarButton
{
    if (!_location) {
        self.navigationItem.rightBarButtonItem = nil;
        return;
    }
    if (_share.currentUserParticipant.permission == CKShareParticipantPermissionReadWrite ||
        (!_share && [_location.creatorUserRecordID.recordName isEqualToString:CKCurrentUserDefaultName])) {
        self.navigationItem.rightBarButtonItem = [UIBarButtonItem.alloc initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
                                                                                             target:self
                                                                                             action:@selector(edit:)];
    } else {
        self.navigationItem.rightBarButtonItem = [UIBarButtonItem.alloc initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                             target:self
                                                                                             action:@selector(share:)];
    }
}

- (void)setLocation:(CKRecord*)location
{
    _location = location;
    self.title = _location[@"name"];
    _address.text = _location[@"address"];
    _desc.text = _location[@"desc"];
    _desc.attributedText = [_desc.attributedText twitterify:_desc.tintColor];
    if (!location) {
        _owner.text = nil;
    } else {
        [CKContainer.defaultContainer discoverUserIdentityWithUserRecordID:location.creatorUserRecordID completionHandler:^(CKUserIdentity * _Nullable userInfo, NSError * _Nullable error) {
            if (error) {
                NSLog(@"userInfo error: %@", error);
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.owner.text = [NSPersonNameComponentsFormatter localizedStringFromPersonNameComponents:userInfo.nameComponents
                                                                                                     style:NSPersonNameComponentsFormatterStyleDefault
                                                                                                   options:0];
            });
        }];
    }
    _instructions.text = _location[@"instructions"];
    [self updateBarButton];
}

- (void)setShare:(CKShare *)share
{
    _share = share;
    NSMutableArray *a = NSMutableArray.array;
    for (CKShareParticipant *p in _share.participants) {
        if (p.role == CKShareParticipantRoleOwner) {
            continue;
        }
        [a addObject:[NSPersonNameComponentsFormatter localizedStringFromPersonNameComponents:p.userIdentity.nameComponents
                                                                                        style:NSPersonNameComponentsFormatterStyleDefault
                                                                                      options:0]];
    }
    _memberList.text = [a componentsJoinedByString:@"\n"];
    [self updateBarButton];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange interaction:(UITextItemInteraction)interaction
{
    NSLog(@"%@", URL);
    AppDelegate *a = (AppDelegate*)UIApplication.sharedApplication.delegate;
    MapViewController *m = a.mapViewController;
    [m selectTag:URL.absoluteString];
    return NO;
}

- (void)cloudSharingControllerDidSaveShare:(UICloudSharingController *)csc
{
    NSLog(@"cloudSharingControllerDidSaveShare:%@", csc);
    [csc dismissViewControllerAnimated:YES completion:nil];
}

- (void)cloudSharingControllerDidStopSharing:(UICloudSharingController *)csc
{
    NSLog(@"cloudSharingControllerDidStopSharing:%@", csc);
}

- (void)cloudSharingController:(UICloudSharingController *)csc failedToSaveShareWithError:(NSError *)error
{
    NSLog(@"failedToSaveShareWithError:%@", error);
}

- (nullable NSString *)itemTitleForCloudSharingController:(UICloudSharingController *)csc
{
    return _location[@"name"];
}

- (nullable NSData *)itemThumbnailDataForCloudSharingController:(UICloudSharingController *)csc
{
    return [NSDataAsset.alloc initWithName:@"Thumbnail"].data;
}

- (nullable NSString *)itemTypeForCloudSharingController:(UICloudSharingController *)csc
{
    return @"com.leelamaps.location";
}

- (UICloudSharingController*)newShareController
{
    __block UICloudSharingController *s = [UICloudSharingController.alloc initWithPreparationHandler:^(UICloudSharingController * _Nonnull controller, void (^ _Nonnull preparationCompletionHandler)(CKShare * _Nullable, CKContainer * _Nullable, NSError * _Nullable)) {
        CKShare *share = [CKShare.alloc initWithRootRecord:self.location];
        share[CKShareTitleKey] = [self itemTitleForCloudSharingController:s];
        share[CKShareThumbnailImageDataKey] = [self itemThumbnailDataForCloudSharingController:s];
        share[CKShareTypeKey] = [self itemTypeForCloudSharingController:s];
        CKModifyRecordsOperation *modifyOp = [CKModifyRecordsOperation.alloc initWithRecordsToSave:@[self.location, share]
                                                                                 recordIDsToDelete:nil];
        modifyOp.modifyRecordsCompletionBlock = ^(NSArray<CKRecord *> * _Nullable savedRecords, NSArray<CKRecordID *> * _Nullable deletedRecordIDs, NSError * _Nullable operationError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"modifyOp error:%@ savedRecords:%@", operationError, savedRecords);
                preparationCompletionHandler(share, CKContainer.defaultContainer, operationError);
                NSLog(@"publicPermissions:%d", (int)share.publicPermission);
                NSLog(@"url:%@", share.URL);
                self.share = share;
            });
        };
        [CKContainer.defaultContainer.privateCloudDatabase addOperation:modifyOp];
    }];
    return s;
}

- (UICloudSharingController*)updateShareController
{
    return [UICloudSharingController.alloc initWithShare:_share container:CKContainer.defaultContainer];
}

- (IBAction)edit:(id)sender
{
    UINavigationController *v = [self.storyboard instantiateViewControllerWithIdentifier:@"LocationEditNav"];
    LocationEditViewController *l = v.viewControllers.firstObject;
    l.location = _location;
    l.share = _share;
    [self presentViewController:v animated:YES completion:nil];
}

- (IBAction)share:(id)sender
{
    UICloudSharingController *s;
    if (_share) {
        s = [self updateShareController];
    } else {
        s = [self newShareController];
    }
    s.delegate = self;
    s.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:s animated:YES completion:nil];
}

@end
