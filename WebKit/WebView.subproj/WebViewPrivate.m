/*	
    WebControllerPrivate.mm
	Copyright (c) 2001, 2002, Apple, Inc. All rights reserved.
*/

#import <WebKit/WebBackForwardList.h>
#import <WebKit/WebContextMenuHandler.h>
#import <WebKit/WebControllerPrivate.h>
#import <WebKit/WebControllerPolicyHandlerPrivate.h>
#import <WebKit/WebDataSourcePrivate.h>
#import <WebKit/WebDefaultContextMenuHandler.h>
#import <WebKit/WebFramePrivate.h>
#import <WebKit/WebLoadProgress.h>
#import <WebKit/WebPreferencesPrivate.h>
#import <WebKit/WebResourceProgressHandler.h>
#import <WebKit/WebStandardPanelsPrivate.h>
#import <WebKit/WebViewPrivate.h>
#import <WebKit/WebWindowContext.h>

#import <WebFoundation/WebAssertions.h>

#import <WebFoundation/WebCacheLoaderConstants.h>
#import <WebFoundation/WebError.h>
#import <WebFoundation/WebFileTypeMappings.h>
#import <WebFoundation/WebResourceHandle.h>
#import <WebFoundation/WebResourceRequest.h>

@implementation WebControllerPrivate

- init 
{
    backForwardList = [[WebBackForwardList alloc] init];
    defaultContextMenuHandler = [[WebDefaultContextMenuHandler alloc] init];
    textSizeMultiplier = 1;
    userAgentLock = [[NSLock alloc] init];
    return self;
}

- (void)_clearControllerReferences: (WebFrame *)aFrame
{
    NSArray *frames;
    WebFrame *nextFrame;
    int i, count;
        
    [[aFrame dataSource] _setController: nil];
    [[aFrame webView] _setController: nil];
    [aFrame _setController: nil];

    // Walk the frame tree, niling the controller.
    frames = [[aFrame dataSource] children];
    count = [frames count];
    for (i = 0; i < count; i++){
        nextFrame = [frames objectAtIndex: i];
        [self _clearControllerReferences: nextFrame];
    }
}

- (void)dealloc
{
    [self _clearControllerReferences: mainFrame];

    [mainFrame reset];
    
    [mainFrame release];
    [windowContext release];
    [resourceProgressHandler release];
    [downloadProgressHandler release];
    [contextMenuHandler release];
    [defaultContextMenuHandler release];
    [policyHandler release];
    [locationChangeHandler release];
    [backForwardList release];
    [applicationNameForUserAgent release];
    [userAgentOverride release];
    [userAgentLock release];
    
    [controllerSetName release];
    [topLevelFrameName release];

    [super dealloc];
}

@end


@implementation WebController (WebPrivate)

- (WebFrame *)createFrameNamed: (NSString *)fname for: (WebDataSource *)childDataSource inParent: (WebDataSource *)parentDataSource allowsScrolling: (BOOL)allowsScrolling
{
    WebView *childView;
    WebFrame *newFrame;

    childView = [[WebView alloc] initWithFrame: NSMakeRect(0,0,0,0)];

    newFrame = [[WebFrame alloc] initWithName: fname webView: childView provisionalDataSource: childDataSource controller: self];

    [parentDataSource addFrame: newFrame];
    
    [newFrame release];

    [childView _setController: self];
    [childDataSource _setController: self];

    [childView setAllowsScrolling: allowsScrolling];
    
    [childView release];
        
    return newFrame;
}


- (id<WebContextMenuHandler>)_defaultContextMenuHandler
{
    return _private->defaultContextMenuHandler;
}

- (void)_receivedProgress:(WebLoadProgress *)progress forResourceHandle:(WebResourceHandle *)resourceHandle fromDataSource:(WebDataSource *)dataSource complete:(BOOL)isComplete
{
    WebFrame *frame = [dataSource webFrame];
    
    ASSERT(dataSource != nil);
    
    [[self resourceProgressHandler] receivedProgress: progress forResourceHandle: resourceHandle 
        fromDataSource: dataSource complete:isComplete];

    // This resource has completed, so check if the load is complete for all frames.
    if (isComplete) {
        if (frame != nil) {
            [frame _transitionToLayoutAcceptable];
            [frame _checkLoadComplete];
        }
    }
}

- (void)_mainReceivedProgress: (WebLoadProgress *)progress forResourceHandle: (WebResourceHandle *)resourceHandle fromDataSource: (WebDataSource *)dataSource complete: (BOOL)isComplete
{
    WebFrame *frame = [dataSource webFrame];
    
    ASSERT(dataSource != nil);

    [[self resourceProgressHandler] receivedProgress: progress forResourceHandle: resourceHandle 
        fromDataSource: dataSource complete:isComplete];
    
    // The frame may be nil if a previously cancelled load is still making progress callbacks.
    if (frame == nil)
        return;
        
    // This resouce has completed, so check if the load is complete for all frames.
    if (isComplete){
        // If the load is complete, mark the primary load as done.  The primary load is the load
        // of the main document.  Other resources may still be arriving.
        [dataSource _setPrimaryLoadComplete: YES];
        [frame _checkLoadComplete];
    }
    else {
        // If the frame isn't complete it might be ready for a layout.  Perform that check here.
        // Note that transitioning a frame to this state doesn't guarantee a layout, rather it
        // just indicates that an early layout can be performed.
        int timedLayoutSize = [[WebPreferences standardPreferences] _initialTimedLayoutSize];
        if ([progress bytesSoFar] > timedLayoutSize)
            [frame _transitionToLayoutAcceptable];
    }
}



- (void)_receivedError: (WebError *)error forResourceHandle: (WebResourceHandle *)resourceHandle partialProgress: (WebLoadProgress *)progress fromDataSource: (WebDataSource *)dataSource
{
    WebFrame *frame = [dataSource webFrame];

    [[self resourceProgressHandler] receivedError: error forResourceHandle: resourceHandle partialProgress: progress fromDataSource: dataSource];

    NSString *resourceIdentifier = [[[resourceHandle request] URL] absoluteString];
    if (resourceIdentifier == nil) {
        resourceIdentifier = [error failingURL];
    }
    if (resourceIdentifier) {
        [dataSource _addError:error forResource:resourceIdentifier];
    }
    
    [frame _checkLoadComplete];
}


- (void)_mainReceivedError: (WebError *)error forResourceHandle: (WebResourceHandle *)resourceHandle partialProgress: (WebLoadProgress *)progress fromDataSource: (WebDataSource *)dataSource
{
    WebFrame *frame = [dataSource webFrame];

    [[self resourceProgressHandler] receivedError: error forResourceHandle: resourceHandle partialProgress: progress fromDataSource: dataSource];
    
    [dataSource _setMainDocumentError: error];
    [dataSource _setPrimaryLoadComplete: YES];

    [frame _checkLoadComplete];
}

- (void)_didStartLoading: (NSURL *)URL
{
    [[WebStandardPanels sharedStandardPanels] _didStartLoadingURL:URL inController:self];
}

- (void)_didStopLoading: (NSURL *)URL
{
    [[WebStandardPanels sharedStandardPanels] _didStopLoadingURL:URL inController:self];
}

+ (NSString *)_MIMETypeForFile: (NSString *)path
{
    NSString *result;
    NSString *extension = [path pathExtension];
    
    if ([extension isEqualToString:@""]) {
        result = @"text/html";
    }
    else {
        result = [[WebFileTypeMappings sharedMappings] MIMETypeForExtension:extension];
        if (result == nil) {
            result = @"application/octet-stream";
        }
    }
    
    return result;
}

- (void)_downloadURL:(NSURL *)URL toPath:(NSString *)path
{
    WebDataSource *dataSource = [[WebDataSource alloc] initWithURL:URL];
    WebFrame *webFrame = [self mainFrame];
        
    WebContentPolicy *contentPolicy = [WebContentPolicy webPolicyWithContentAction:WebContentPolicySave andPath:path];
    [dataSource _setContentPolicy:contentPolicy];
    if([webFrame setProvisionalDataSource:dataSource]){
        [webFrame startLoading];
    }
    [dataSource release];
}

- (BOOL)_defersCallbacks
{
    return _private->defersCallbacks;
}

- (void)_setDefersCallbacks:(BOOL)defers
{
    if (defers == _private->defersCallbacks) {
        return;
    }

    _private->defersCallbacks = defers;
    [_private->mainFrame _defersCallbacksChanged];
}

- (void)_setTopLevelFrameName:(NSString *)name
{
    [_private->topLevelFrameName release];
    _private->topLevelFrameName = [name retain];
}

- (WebFrame *)_frameInThisWindowNamed:(NSString *)name
{
    if ([_private->topLevelFrameName isEqualToString:name]) {
	return [self mainFrame];
    } else {
	return [[self mainFrame] frameNamed:name];
    }
}

@end
