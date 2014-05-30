//
//  QMChatViewController.m
//  Q-municate
//
//  Created by Igor Alefirenko on 01/04/2014.
//  Copyright (c) 2014 Quickblox. All rights reserved.
//

#import "QMChatViewController.h"
#import "QMChatViewCell.h"
#import "QMChatDataSource.h"
#import "QMContactList.h"
#import "QMChatService.h"
#import "QMUtilities.h"
#import "QMContent.h"
#import "QMChatInvitationCell.h"
#import "QMPrivateChatCell.h"
#import "QMPrivateContentCell.h"
#import "QMUploadAttachCell.h"
#import "QMChatUploadingMessage.h"
#import "UIImage+Cropper.h"
#import "QMContentPreviewController.h"


static CGFloat const kCellHeightOffset = 33.0f;

@interface QMChatViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet UIView *inputMessageView;
@property (weak, nonatomic) IBOutlet UITextField *inputMessageTextField;

@property (nonatomic, strong) QMContent *uploadManager;
@property (nonatomic, strong) QMChatDataSource *dataSource;

@property (assign) BOOL isBackButtonClicked;

@property (nonatomic, strong) NSMutableArray *chatHistory;

@end

@implementation QMChatViewController


- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.title = self.chatName;
    
    // UI & observers:
    [self configureInputMessageViewShadow];
    [self addKeyboardObserver];
	[self addChatObserver];
	self.isBackButtonClicked = NO;
    
    NSString *opponentID = [@(self.opponent.ID) stringValue];
    // if dialog is group chat:
    if (self.chatDialog.type != QBChatDialogTypePrivate) {
        
        // if user is joined, return
        if (![self userIsJoinedRoomForDialog:self.chatDialog]) {
            
            // enter chat room:
            [QMUtilities createIndicatorView];
            [[QMChatService shared] joinRoomWithRoomJID:self.chatDialog.roomJID];
        }
        self.chatRoom = [QMChatService shared].allChatRoomsAsDictionary[self.chatDialog.roomJID];
        // load history:
        self.chatHistory = [QMChatService shared].allConversations[self.chatDialog.roomJID];
        if (self.chatHistory == nil) {
            [QMUtilities createIndicatorView];
            [self loadHistory];
        }
        return;
    }

    // for private chat:
    // retrieve chat history:
    self.chatHistory = [QMChatService shared].allConversations[opponentID];
    if (self.chatHistory == nil) {
        
        // if new chat dialog (not from server):
        if ([self.chatDialog.occupantIDs count] == 1) {    // created now:
            NSMutableArray *emptyHistory = [NSMutableArray new];
            [QMChatService shared].allConversations[opponentID] = emptyHistory;
            return;
        }
        [QMUtilities createIndicatorView];
        // load history:
        [self loadHistory];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    // update unread message count:
    [self updateChatDialog];
    
    [self resetTableView];
    
    [super viewWillAppear:NO];
}

- (void)updateChatDialog
{
    self.chatDialog.unreadMessageCount = 0;
}

- (void)loadHistory
{
    // load history:
    [[QMChatService shared] getMessageHistoryWithDialogID:self.chatDialog.ID withCompletion:^(NSArray *chatDialogHistoryArray, NSError *error) {
        [QMUtilities removeIndicatorView];
        if (chatDialogHistoryArray != nil) {
            
            if (self.chatDialog.type == QBChatDialogTypePrivate) {
                [QMChatService shared].allConversations[[@(self.opponent.ID)stringValue]] = [chatDialogHistoryArray mutableCopy];
            } else {
                [QMChatService shared].allConversations[self.chatDialog.roomJID] = [chatDialogHistoryArray mutableCopy];
            }
        }
        [self resetTableView];
    }];
}

//- (void)updateProgressFooter
//{
//    NSlog(@"%lu", (unsigned long)(self.uploadManager.uploadProgress * 100));
//}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)addChatObserver
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(localChatDidReceiveMessage:) name:kChatDidReceiveMessage object:nil];
    
    // upload progress:
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resetTableView) name:@"ContentDidLoadNotification" object:nil];
    
    // chat room:
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatRoomDidEnterNotification) name:kChatRoomDidEnterNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatRoomDidReveiveMessage) name:kChatRoomDidReceiveMessageNotification object:nil];
}

- (void)configureNavBarButtons
{
	BOOL isGroupChat = YES;

	if (isGroupChat) {
		UIButton *groupInfoButton = [UIButton buttonWithType:UIButtonTypeCustom];
		[groupInfoButton setFrame:CGRectMake(0, 0, 30, 40)];

		[groupInfoButton setImage:[UIImage imageNamed:@"ic_info_top"] forState:UIControlStateNormal];
		[groupInfoButton setImage:[UIImage imageNamed:@"ic_info_top"] forState:UIControlStateHighlighted];
		[groupInfoButton addTarget:self action:@selector(groupInfoNavButtonAction) forControlEvents:UIControlEventTouchUpInside];
		UIBarButtonItem *groupInfoBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:groupInfoButton];
		self.navigationItem.rightBarButtonItems = @[groupInfoBarButtonItem];
	} else {
		UIButton *videoButton = [UIButton buttonWithType:UIButtonTypeCustom];
		UIButton *audioButton = [UIButton buttonWithType:UIButtonTypeCustom];
		[videoButton setFrame:CGRectMake(0, 0, 30, 40)];
		[audioButton setFrame:CGRectMake(0, 0, 30, 40)];

		[videoButton setImage:[UIImage imageNamed:@"ic_camera_top"] forState:UIControlStateNormal];
		[videoButton setImage:[UIImage imageNamed:@"ic_camera_top"] forState:UIControlStateHighlighted];
		[videoButton addTarget:self action:@selector(videoCallAction) forControlEvents:UIControlEventTouchUpInside];

		[audioButton setImage:[UIImage imageNamed:@"ic_phone_top"] forState:UIControlStateNormal];
		[audioButton setImage:[UIImage imageNamed:@"ic_phone_top"] forState:UIControlStateHighlighted];
		[audioButton addTarget:self action:@selector(audioCallAction) forControlEvents:UIControlEventTouchUpInside];

		UIBarButtonItem *videoCallBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:videoButton];
		UIBarButtonItem *audioCallBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:audioButton];
		self.navigationItem.rightBarButtonItems = @[audioCallBarButtonItem, videoCallBarButtonItem];
	}
}


- (void)addKeyboardObserver
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resizeViewWithKeyboardNotification:) name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resizeViewWithKeyboardNotification:) name:UIKeyboardWillShowNotification object:nil];
}

- (void)configureInputMessageViewShadow
{
    self.inputMessageView.layer.shadowColor = [UIColor darkGrayColor].CGColor;
    self.inputMessageView.layer.shadowOffset = CGSizeMake(0, -1.0);
    self.inputMessageView.layer.shadowOpacity = 0.5;
    self.inputMessageView.layer.shadowPath = [UIBezierPath bezierPathWithRect:[self.inputMessageView bounds]].CGPath;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)back:(id)sender
{
	self.isBackButtonClicked = YES;
    if (self.createdJustNow) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }
	[self.navigationController popViewControllerAnimated:YES];
}

- (IBAction)showMediaFiles:(id)sender
{
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.delegate = self;
        
        [self presentViewController:picker animated:YES completion:nil];
    }
}


#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.chatHistory count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    QBChatAbstractMessage *message = self.chatHistory[indexPath.row];
    
    // "User created a group chat" cell
    //
    if (message.customParameters[@"xmpp_room_jid"] != nil) {
        QMChatInvitationCell *invitationCell = (QMChatInvitationCell *)[tableView dequeueReusableCellWithIdentifier:@"InvitationCell"];
        [invitationCell configureCellWithMessage:message];
        return invitationCell;
    }
    BOOL isMe = NO;
    QBUUser *currentMessageUser = nil;
    if ([QMContactList shared].me.ID == message.senderID) {
        currentMessageUser = [QMContactList shared].me;
        isMe = YES;
    } else {
        currentMessageUser = [[QMContactList shared] findFriendWithID:message.senderID];
    }
    
    // Upload attach cell
    //
    if([message isKindOfClass:QMChatUploadingMessage.class]){
        QMUploadAttachCell *cell = (QMUploadAttachCell *)[tableView dequeueReusableCellWithIdentifier:@"UploadingAttachIdentifier"];
        [cell configureCellWithMessage:(QMChatUploadingMessage *)message];
        return cell;
    }
    
    // Privae chat cell
    if (self.chatDialog.type == QBChatDialogTypePrivate) {
        
        // attachment cell
        //
        if ([message.attachments count]>0) {
            QMPrivateContentCell *contentCell = (QMPrivateContentCell *)[tableView dequeueReusableCellWithIdentifier:@"PrivateContentCell"];
            [contentCell configureCellWithMessage:message forUser:currentMessageUser isMe:isMe];
            return contentCell;
        }
        
        // message cell
        //
        QMPrivateChatCell *privateChatCell = (QMPrivateChatCell *)[tableView dequeueReusableCellWithIdentifier:@"PrivateChatCell"];
        [privateChatCell configureCellWithMessage:message fromUser:currentMessageUser];
        return privateChatCell;
    }
    
    // Group chat cell
    //
    QMChatViewCell *cell = (QMChatViewCell *)[tableView dequeueReusableCellWithIdentifier:kChatViewCellIdentifier];
    [cell configureCellWithMessage:message fromUser:currentMessageUser];

    return cell;
}

// height for cell:
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    QBChatAbstractMessage *chatMessage = self.chatHistory[indexPath.row];
    
    // Upload attach cell
    //
    if([chatMessage isKindOfClass:QMChatUploadingMessage.class]){
        return 60.f;
    }
    
    
    if (chatMessage.customParameters[@"xmpp_room_jid"] != nil) {
        return 50.0f;
    }
    if (self.chatDialog.type == QBChatDialogTypePrivate) {
        if ([chatMessage.attachments count] >0) {
            return 150;
        }
        return [QMPrivateChatCell cellHeightForMessage:chatMessage] +9.0f;
    }
    return [QMChatViewCell cellHeightForMessage:chatMessage.text] + kCellHeightOffset;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *neededCell = [tableView cellForRowAtIndexPath:indexPath];
    if ([neededCell isKindOfClass:QMPrivateContentCell.class]) {
        
        // getting image:
        UIImage *contentImage = ((QMPrivateContentCell *)neededCell).sharedImageView.image;
        [self performSegueWithIdentifier:@"ContentPreviewIdentifier" sender:contentImage];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.destinationViewController isKindOfClass:QMContentPreviewController.class]) {
        QMContentPreviewController *contentController = (QMContentPreviewController *)segue.destinationViewController;
        contentController.contentImage = (UIImage *)sender;
        // needed public url also:
    }
}

- (void)resetTableView
{
    if (self.chatDialog.type == QBChatDialogTypePrivate) {
         self.chatHistory = [QMChatService shared].allConversations[[@(self.opponent.ID) stringValue]];
    } else {
        self.chatHistory = [QMChatService shared].allConversations[self.chatDialog.roomJID];
    }
    
    [self.tableView reloadData];
//    if ([self.chatHistory count] >2) {
//        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:[self.chatHistory count]-1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:YES];
//    }
}

#pragma mark - Keyboard
- (void)clearMessageInputTextField
{
	self.inputMessageTextField.text = kEmptyString;
	[self.inputMessageTextField resignFirstResponder];
}
- (void)resizeViewWithKeyboardNotification:(NSNotification *)notification
{
	if (self.isBackButtonClicked) {
		[self clearMessageInputTextField];
	} else {
		/*
		* below code is to follow animation of keyboard
		* for view with textField and buttons('send', 'transfer')
		* but still need to count tabBar height and time for animation
		* */
		NSDictionary * userInfo = notification.userInfo;
		NSTimeInterval animationDuration;
		UIViewAnimationCurve animationCurve;
		CGRect keyboardFrame;
		[[userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey] getValue:&animationCurve];
		[[userInfo valueForKey:UIKeyboardAnimationDurationUserInfoKey] getValue:&animationDuration];
		[[userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] getValue:&keyboardFrame];

		BOOL isKeyboardShow = !(keyboardFrame.origin.y == [[UIScreen mainScreen] bounds].size.height);

		NSInteger keyboardHeight = isKeyboardShow ? - keyboardFrame.size.height +49.0f: keyboardFrame.size.height -49.0f;
        
		[UIView animateWithDuration:animationDuration delay:0.0f options:animationCurve << 16 animations:^
		{
			CGRect frame = self.view.frame;
			frame.size.height += keyboardHeight;
			self.view.frame = frame;

			[self.view layoutIfNeeded];

		} completion:^(BOOL finished) {
            if ([self.chatHistory count] >2) {
                [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:[self.chatHistory count]-1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:YES];
            }
        }];
	}
}

#pragma mark - Nav Buttons Actions
- (void)audioCallAction
{
	//
}

- (void)videoCallAction
{
	//
}

- (void)groupInfoNavButtonAction
{
	//
}

#pragma mark - Chat Notifications


- (void)localChatDidReceiveMessage:(NSNotification *)notification
{
    [self updateChatDialog];
    [self resetTableView];
}

// ************************** CHAT ROOM **********************************
- (void)chatRoomDidEnterNotification
{
    self.chatRoom = [QMChatService shared].allChatRoomsAsDictionary[self.chatDialog.roomJID];
    
    if (self.chatHistory != nil) {
        [QMUtilities removeIndicatorView];
        return;
    }
    
    // load history:
    [self loadHistory];
}

- (void)chatRoomDidReveiveMessage
{
    // update unread message count:
    [self updateChatDialog];
    
    [self resetTableView];
}


#pragma mark -
- (IBAction)sendMessageButtonClicked:(UIButton *)sender
{
	if (self.inputMessageTextField.text.length) {
		QBChatMessage *chatMessage = [QBChatMessage new];
		chatMessage.text = self.inputMessageTextField.text;
        
		if (self.chatDialog.type == QBChatDialogTypePrivate) { // private chat
            chatMessage.recipientID = self.opponent.ID;
            chatMessage.senderID = [QMContactList shared].me.ID;
			[[QMChatService shared] sendMessage:chatMessage];

		} else { // group chat
            [[QMChatService shared] sendMessage:chatMessage toRoom:self.chatRoom];
		}
        self.inputMessageTextField.text = @"";
        [self resetTableView];
	}
}

- (void)addMessageToHistory:(QBChatMessage *)chatMessage
{
	[self.dataSource addMessageToHistory:chatMessage];
	[self clearMessageInputTextField];
	[self.tableView reloadData];
}

- (BOOL)userIsJoinedRoomForDialog:(QBChatDialog *)dialog
{
    QBChatRoom *currentRoom = [QMChatService shared].allChatRoomsAsDictionary[dialog.roomJID];
    if (currentRoom == nil || !currentRoom.isJoined) {
        return NO;
    }
    return YES;
}


#pragma mark -
- (void)showAlertWithErrorMessage:(NSString *)messageString
{
	[[[UIAlertView alloc] initWithTitle:kAlertTitleErrorString message:messageString delegate:self cancelButtonTitle:kAlertButtonTitleOkString otherButtonTitles:nil] show];
}


#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    __block UIImage *currentImage = info[UIImagePickerControllerOriginalImage];
//    currentImage = [currentImage imageByScalingProportionallyToMinimumSize:CGSizeMake(625, 400)];
    
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
    
    [self dismissViewControllerAnimated:YES completion:^{

        // Create  uploading message
        QMChatUploadingMessage *chatMessage = [QMChatUploadingMessage new];
		chatMessage.content = currentImage;
        chatMessage.text = @"Content";
		if (self.chatDialog.type == QBChatDialogTypePrivate) {
            chatMessage.recipientID = self.opponent.ID;
            
            //add private upload message to history
            NSMutableArray *messages = [QMChatService shared].allConversations[[@(self.opponent.ID) stringValue]];
            [messages addObject:chatMessage];
            [self resetTableView];
            return;
        }
        chatMessage.roomJID = self.chatDialog.roomJID;                      //room jid for caching message in QMChatService
        //add group upload message to history
        NSMutableArray *messages = [QMChatService shared].allConversations[self.chatDialog.roomJID];
        [messages addObject:chatMessage];
        
        [self resetTableView];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
