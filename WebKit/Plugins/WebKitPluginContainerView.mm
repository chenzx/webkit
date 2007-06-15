/*
 * Copyright (C) 2007 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1.  Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer. 
 * 2.  Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution. 
 * 3.  Neither the name of Apple Computer, Inc. ("Apple") nor the names of
 *     its contributors may be used to endorse or promote products derived
 *     from this software without specific prior written permission. 
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE AND ITS CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL APPLE OR ITS CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "WebKitPluginContainerView.h"
#import <WebKit/DOMPrivate.h>

@implementation WebKitPluginContainerView
 
- (id)initWithFrame:(NSRect)frame
         DOMElement:(DOMElement *)anElement
{
    [super initWithFrame:frame];

    _element = [anElement retain];
    
    return self;
}

- (void)dealloc
{
    [_element release];
    
    // Calling [super dealloc] can end up calling visibleRect so we need to set
    // the _element instance to 0 here so we can check for it in our visibleRect.
    _element = 0;
    
    [super dealloc];
}

- (NSRect)visibleRect
{
    if (!_element)
        return [super visibleRect];
    
    // WebCore may impose an additional clip (via CSS overflow or clip properties).  Fetch
    // that clip now.    
    return NSIntersectionRect([self convertRect:[_element _windowClipRect] fromView:nil], [super visibleRect]);
}

- (BOOL)respondsToSelector:(SEL)selector
{
    if (selector == @selector(objectForWebScript))
        return [[[self subviews] objectAtIndex: 0] respondsToSelector:selector];
    return [super respondsToSelector:selector];  
}

- (id)objectForWebScript
{
    return [[[self subviews] objectAtIndex: 0] objectForWebScript];
}

@end

