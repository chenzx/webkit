/*
        WebNetscapePluginEmbeddedView.h
	Copyright 2002, Apple, Inc. All rights reserved.
*/

#import <AppKit/AppKit.h>

#import <WebKit/WebBaseNetscapePluginView.h>

@interface WebNetscapePluginEmbeddedView : WebBaseNetscapePluginView
{
    NSURL *URL;
}

- (id)initWithFrame:(NSRect)r
             plugin:(WebNetscapePlugin *)plugin
                URL:(NSURL *)URL
            baseURL:(NSURL *)baseURL
               mime:(NSString *)mimeType
          arguments:(NSDictionary *)arguments;

@end
