/*	
    IFMainURLHandleClient.h

    Private header.
    
    Copyright 2001, Apple, Inc. All rights reserved.
*/


#import <WebKit/IFLocationChangeHandler.h>
#import <WebFoundation/IFURLHandle.h>

@class IFDownloadHandler;
@class IFWebDataSource;
@protocol IFURLHandleClient;

class KHTMLPart;

@interface IFMainURLHandleClient : NSObject <IFURLHandleClient>
{
    NSURL *url;
    id dataSource;
    KHTMLPart *part;
    BOOL processedBufferedData;
    BOOL examinedInitialData;
    BOOL isFirstChunk;
}
- initWithDataSource: (IFWebDataSource *)ds;

@end

