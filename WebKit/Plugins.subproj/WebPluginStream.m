/*	
    WebPluginStream.m
	Copyright (c) 2002, Apple, Inc. All rights reserved.
*/

#import <WebKit/WebLoadProgress.h>
#import <WebKit/WebPluginStream.h>
#import <WebKit/WebView.h>
#import <WebKit/WebDataSource.h>
#import <WebKit/WebControllerPrivate.h>
#import <WebKitDebug.h>

#import <WebFoundation/WebFoundation.h>

@interface WebPluginStream (WebResourceClient) <WebResourceClient>
@end

static NSString *getCarbonPath(NSString *posixPath);

@implementation WebPluginStream

- init
{
    [super init];

    isFirstChunk = YES;
    stopped = YES;
    
    return self;
}

- initWithURL:(NSURL *)theURL pluginPointer:(NPP)thePluginPointer
{        
    return [self initWithURL:theURL pluginPointer:thePluginPointer notifyData:nil attributes:nil];
}

- initWithURL:(NSURL *)theURL pluginPointer:(NPP)thePluginPointer notifyData:(void *)theNotifyData
{
    return [self initWithURL:theURL pluginPointer:thePluginPointer notifyData:theNotifyData attributes:nil];
}

- initWithURL:(NSURL *)theURL pluginPointer:(NPP)thePluginPointer notifyData:(void *)theNotifyData attributes:(NSDictionary *)theAttributes
{    
    [super init];
    
    if(!theURL)
        return nil;
    
    if(!thePluginPointer)
       return nil;
    
    view = [(WebPluginView *)thePluginPointer->ndata retain];
    URL = [theURL retain];
    attributes = [theAttributes retain];
    instance = thePluginPointer;
    notifyData = theNotifyData;
    
    NPP_NewStream = 	[view NPP_NewStream];
    NPP_WriteReady = 	[view NPP_WriteReady];
    NPP_Write = 	[view NPP_Write];
    NPP_StreamAsFile = 	[view NPP_StreamAsFile];
    NPP_DestroyStream = [view NPP_DestroyStream];
    NPP_URLNotify = 	[view NPP_URLNotify];
    
    isFirstChunk = YES;
    stopped = YES;
    
    return self;
}

- (void) dealloc
{
    [self stop];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(path){
        [fileManager removeFileAtPath:path handler:nil];
        [path release];
    }
    free((void *)npStream.url);
    [URL release];
    [attributes release];
    [super dealloc];
}

- (void)startLoad
{
    resource = [[WebResourceHandle alloc] initWithURL:URL attributes:attributes flags:0];
    if(resource){
        [resource addClient:self];
        [resource loadInBackground];
    }
}

- (void)stop
{
    if(!stopped){
        stopped = YES;
        if([resource statusCode] == WebResourceHandleStatusLoading)
            [resource cancelLoadInBackground];
        [resource removeClient:self];
        [resource release];
    }
    [view release];
    view = nil;
}

- (void)receivedData:(NSData *)data
{
    int32 numBytes;
    NPError npErr;
    
    if(isFirstChunk){
        isFirstChunk = NO;
        
        //FIXME: Need a way to check if stream is seekable
        
        npErr = NPP_NewStream(instance, (char *)[mimeType cString], &npStream, NO, &transferMode);
        WEBKITDEBUGLEVEL(WEBKIT_LOG_PLUGINS, "NPP_NewStream: %d %s\n", npErr, [[URL absoluteString] cString]);
        
        if(npErr != NPERR_NO_ERROR){
            [self stop];
            return;
        }
        
        if(transferMode == NP_NORMAL)
            WEBKITDEBUGLEVEL(WEBKIT_LOG_PLUGINS, "Stream type: NP_NORMAL\n");
        else if(transferMode == NP_ASFILEONLY)
            WEBKITDEBUGLEVEL(WEBKIT_LOG_PLUGINS, "Stream type: NP_ASFILEONLY\n");
        else if(transferMode == NP_ASFILE)
            WEBKITDEBUGLEVEL(WEBKIT_LOG_PLUGINS, "Stream type: NP_ASFILE\n");
        else if(transferMode == NP_SEEK){
            WEBKITDEBUGLEVEL(WEBKIT_LOG_PLUGINS, "Stream type: NP_SEEK not yet supported\n");
            [self stop];
            return;
        }
    }

    if(transferMode != NP_ASFILEONLY){
        numBytes = NPP_WriteReady(instance, &npStream);
        WEBKITDEBUGLEVEL(WEBKIT_LOG_PLUGINS, "NPP_WriteReady bytes=%lu\n", numBytes);
        
        numBytes = NPP_Write(instance, &npStream, offset, [data length], (void *)[data bytes]);
        WEBKITDEBUGLEVEL(WEBKIT_LOG_PLUGINS, "NPP_Write bytes=%lu\n", numBytes);
        
        offset += [data length];
    }
}

- (void)receivedError
{
    NPError npErr;
    
    npErr = NPP_DestroyStream(instance, &npStream, NPRES_NETWORK_ERR);
    WEBKITDEBUGLEVEL(WEBKIT_LOG_PLUGINS, "NPP_DestroyStream: %d\n", npErr);
}

- (void)finishedLoadingWithData:(NSData *)data
{
    NPError npErr;
    NSFileManager *fileManager;
    NSString *filename;
    
    filename = [[URL path] lastPathComponent];
    if(transferMode == NP_ASFILE || transferMode == NP_ASFILEONLY) {
        // FIXME: Need to use something like mkstemp?
        path = [[NSString stringWithFormat:@"/tmp/%@", filename] retain];        
        fileManager = [NSFileManager defaultManager];
        [fileManager removeFileAtPath:path handler:nil];
        [fileManager createFileAtPath:path contents:data attributes:nil];
        
        // FIXME: Will cString use the correct character set?
        NPP_StreamAsFile(instance, &npStream, [getCarbonPath(path) cString]);
        WEBKITDEBUGLEVEL(WEBKIT_LOG_PLUGINS, "NPP_StreamAsFile: %s\n", [getCarbonPath(path) cString]);
    }
    npErr = NPP_DestroyStream(instance, &npStream, NPRES_DONE);
    WEBKITDEBUGLEVEL(WEBKIT_LOG_PLUGINS, "NPP_DestroyStream: %d\n", npErr);
    
    if(notifyData){
        NPP_URLNotify(instance, [[URL absoluteString] cString], NPRES_DONE, notifyData);
        WEBKITDEBUGLEVEL(WEBKIT_LOG_PLUGINS, "NPP_URLNotify\n");
    }
    
    [self stop];
}

- (void)receivedData:(NSData *)data withDataSource:(WebDataSource *)dataSource
{
    if(isFirstChunk){
        URL = [[dataSource inputURL] retain];
        NSString *URLString = [URL absoluteString];
        char *cURL = (char *)malloc([URLString cStringLength]+1);
        [URLString getCString:cURL];
        
        npStream.ndata = self;
        npStream.url = cURL;
        npStream.end = 0;
        npStream.lastmodified = 0;
        npStream.notifyData = 0;
        offset = 0;
        mimeType = [[dataSource contentType] retain];
        
        WebFrame *frame = [dataSource webFrame];
        WebView *webView = [frame webView];
        view = [[webView documentView] retain];
        instance = [view pluginInstance];
        
        NPP_NewStream = 	[view NPP_NewStream];
        NPP_WriteReady = 	[view NPP_WriteReady];
        NPP_Write = 		[view NPP_Write];
        NPP_StreamAsFile = 	[view NPP_StreamAsFile];
        NPP_DestroyStream = 	[view NPP_DestroyStream];
        NPP_URLNotify = 	[view NPP_URLNotify];
    }
    [self receivedData:data];
}

- (void)receivedError:(WebError *)error withDataSource:(WebDataSource *)dataSource
{
    [self receivedError];
}

- (void)finishedLoadingWithDataSource:(WebDataSource *)dataSource
{
    [self finishedLoadingWithData:[dataSource data]];
}

- (void)WebResourceHandleDidBeginLoading:(WebResourceHandle *)handle
{
    [[view webController] _didStartLoading:URL];
}

- (void)WebResourceHandle:(WebResourceHandle *)handle dataDidBecomeAvailable:(NSData *)data
{
    WebController *webController = [view webController];
    
    if(isFirstChunk){
        NSString *URLString = [[handle url] absoluteString];
        char *cURL = (char *)malloc([URLString cStringLength]+1);
        [URLString getCString:cURL];
        
        npStream.ndata = self;
        npStream.url = cURL;
        npStream.end = 0;
        npStream.lastmodified = 0;
        npStream.notifyData = notifyData;
        offset = 0;
        mimeType = [[handle contentType] retain];
    }
    [self receivedData:data];
    
    [webController _receivedProgress:[WebLoadProgress progressWithResourceHandle:handle]
        forResourceHandle: handle fromDataSource: [view webDataSource] complete: NO];
}

- (void)WebResourceHandleDidFinishLoading:(WebResourceHandle *)handle data: (NSData *)data
{
    WebController *webController = [view webController];
    
    [webController _receivedProgress:[WebLoadProgress progressWithResourceHandle:handle]
            forResourceHandle: handle fromDataSource: [view webDataSource] complete: YES];
 
    [self finishedLoadingWithData:data];
          
    [webController _didStopLoading:URL];
}

- (void)WebResourceHandleDidCancelLoading:(WebResourceHandle *)handle
{
    WebController *webController = [view webController];
    
    [webController _receivedProgress:[WebLoadProgress progress]
        forResourceHandle: handle fromDataSource: [view webDataSource] complete: YES];
            
    [self receivedError];
    
    [webController _didStopLoading:URL];
}

- (void)WebResourceHandle:(WebResourceHandle *)handle didFailLoadingWithResult:(WebError *)result
{
    WebController *webController = [view webController];
    
    WebLoadProgress *loadProgress = [[WebLoadProgress alloc] initWithResourceHandle:handle];
    
    [webController _receivedError: result forResourceHandle: handle 
        partialProgress: loadProgress fromDataSource: [view webDataSource]];
    [loadProgress release];
    
    [self receivedError];
    
    [webController _didStopLoading:URL];
}

- (void)WebResourceHandle:(WebResourceHandle *)handle didRedirectToURL:(NSURL *)toURL
{
    WebController *webController = [view webController];
    
    [webController _didStopLoading:URL];
    // FIXME: This next line is not sufficient. We don't do anything to remember the new URL.
    [webController _didStartLoading:toURL];
}

@end

static NSString *getCarbonPath(NSString *posixPath)
{
    OSStatus error;
    FSRef ref, rootRef, parentRef;
    FSCatalogInfo info;
    NSMutableArray *carbonPathPieces;
    HFSUniStr255 nameString;
    
    // Make an FSRef.
    error = FSPathMakeRef((const UInt8 *)[[NSFileManager defaultManager] fileSystemRepresentationWithPath:posixPath], &ref, NULL);
    if (error != noErr) {
        return nil;
    }
    
    // Get volume refNum.
    error = FSGetCatalogInfo(&ref, kFSCatInfoVolume, &info, NULL, NULL, NULL);
    if (error != noErr) {
        return nil;
    }
    
    // Get root directory FSRef.
    error = FSGetVolumeInfo(info.volume, 0, NULL, kFSVolInfoNone, NULL, NULL, &rootRef);
    if (error != noErr) {
        return nil;
    }
    
    // Get the pieces of the path.
    carbonPathPieces = [NSMutableArray array];
    for (;;) {
        error = FSGetCatalogInfo(&ref, kFSCatInfoNone, NULL, &nameString, NULL, &parentRef);
        if (error != noErr) {
            return nil;
        }
        [carbonPathPieces insertObject:[NSString stringWithCharacters:nameString.unicode length:nameString.length] atIndex:0];
        if (FSCompareFSRefs(&ref, &rootRef) == noErr) {
            break;
        }
        ref = parentRef;
    }
    
    // Volume names need trailing : character.
    if ([carbonPathPieces count] == 1) {
        [carbonPathPieces addObject:@""];
    }
    
    return [carbonPathPieces componentsJoinedByString:@":"];
}
