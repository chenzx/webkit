/*
 * Copyright (C) 2004 Apple Computer, Inc.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE COMPUTER, INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE COMPUTER, INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */

#include "config.h"
#import "WebCoreBridge.h"

#import "csshelper.h"
#import "dom2_eventsimpl.h"
#import "dom2_range.h"
#import "dom2_rangeimpl.h"
#import "dom2_viewsimpl.h"
#import "dom_docimpl.h"
#import "dom_node.h"
#import "dom_nodeimpl.h"
#import "dom_position.h"
#import "html_documentimpl.h"
#import "html_formimpl.h"
#import "html_imageimpl.h"
#import "htmlediting.h"
#import "khtml_part.h"
#import "khtmlview.h"
#import "kjs_proxy.h"
#import "kjs_window.h"
#import "loader.h"
#import "markup.h"
#import "render_canvas.h"
#import "render_frames.h"
#import "render_image.h"
#import "render_object.h"
#import "render_replaced.h"
#import "render_style.h"
#import "SelectionController.h"
#import "visible_position.h"
#import "visible_text.h"
#import "visible_units.h"
#import "xml_tokenizer.h"

#import <JavaScriptCore/interpreter.h>
#import <JavaScriptCore/jni_jsobject.h>
#import <JavaScriptCore/npruntime.h>
#import <JavaScriptCore/object.h>
#import <JavaScriptCore/property_map.h>
#import <JavaScriptCore/runtime_root.h>

#import <kxmlcore/Assertions.h>
#import "KWQCharsets.h"
#import "KWQClipboard.h"
#import "KWQEditCommand.h"
#import "KWQFont.h"
#import "KWQFoundationExtras.h"
#import "KWQFrame.h"
#import "KWQKHTMLPart.h"
#import "KWQLoader.h"
#import "KWQPageState.h"
#import "KWQRenderTreeDebug.h"
#import "KWQView.h"
#import "KWQPrinter.h"
#import "KWQAccObjectCache.h"

#import "DOMInternal.h"
#import "WebCoreImageRenderer.h"
#import "WebCoreTextRendererFactory.h"
#import "WebCoreViewFactory.h"
#import "WebCoreSettings.h"
#import "WebCoreFrameNamespaces.h"

@class NSView;

using namespace DOM::HTMLNames;

using DOM::AtomicString;
using DOM::CSSStyleDeclarationImpl;
using DOM::DocumentFragmentImpl;
using DOM::DocumentImpl;
using DOM::DocumentTypeImpl;
using DOM::DOMString;
using DOM::ElementImpl;
using DOM::HTMLElementImpl;
using DOM::HTMLFormElementImpl;
using DOM::HTMLGenericFormElementImpl;
using DOM::HTMLImageElementImpl;
using DOM::HTMLInputElementImpl;
using DOM::NodeImpl;
using DOM::Position;
using DOM::RangeImpl;

using khtml::ChildrenOnly;
using khtml::createMarkup;
using khtml::Decoder;
using khtml::DeleteSelectionCommand;
using khtml::DOWNSTREAM;
using khtml::EAffinity;
using khtml::EditAction;
using khtml::EditCommandPtr;
using khtml::ETextGranularity;
using khtml::IncludeNode;
using khtml::MoveSelectionCommand;
using khtml::parseURL;
using khtml::RenderCanvas;
using khtml::RenderImage;
using khtml::RenderLayer;
using khtml::RenderObject;
using khtml::RenderPart;
using khtml::RenderStyle;
using khtml::RenderWidget;
using khtml::ReplaceSelectionCommand;
using khtml::SelectionController;
using khtml::Tokenizer;
using khtml::TextIterator;
using khtml::TypingCommand;
using khtml::UPSTREAM;
using khtml::VisiblePosition;

using KJS::ExecState;
using KJS::Interpreter;
using KJS::JSLock;
using KJS::JSObject;
using KJS::SavedProperties;
using KJS::SavedBuiltins;
using KJS::Window;

using KParts::URLArgs;

using KJS::Bindings::RootObject;

NSString *WebCoreElementDOMNodeKey =            @"WebElementDOMNode";
NSString *WebCoreElementFrameKey =              @"WebElementFrame";
NSString *WebCoreElementImageAltStringKey =     @"WebElementImageAltString";
NSString *WebCoreElementImageRendererKey =      @"WebCoreElementImageRenderer";
NSString *WebCoreElementImageRectKey =          @"WebElementImageRect";
NSString *WebCoreElementImageURLKey =           @"WebElementImageURL";
NSString *WebCoreElementIsSelectedKey =         @"WebElementIsSelected";
NSString *WebCoreElementLinkURLKey =            @"WebElementLinkURL";
NSString *WebCoreElementLinkTargetFrameKey =    @"WebElementTargetFrame";
NSString *WebCoreElementLinkLabelKey =          @"WebElementLinkLabel";
NSString *WebCoreElementLinkTitleKey =          @"WebElementLinkTitle";
NSString *WebCoreElementNameKey =               @"WebElementName";
NSString *WebCoreElementTitleKey =              @"WebCoreElementTitle"; // not in WebKit API for now, could be in API some day

NSString *WebCorePageCacheStateKey =            @"WebCorePageCacheState";

@interface WebCoreBridge (WebCoreBridgeInternal)
- (RootObject *)executionContextForView:(NSView *)aView;
@end

static RootObject *rootForView(void *v)
{
    NSView *aView = (NSView *)v;
    WebCoreBridge *aBridge = [[WebCoreViewFactory sharedFactory] bridgeForView:aView];
    RootObject *root = 0;

    if (aBridge)
        root = [aBridge executionContextForView:aView];

    return root;
}

static pthread_t mainThread = 0;

static void updateRenderingForBindings (ExecState *exec, JSObject *rootObject)
{
    if (pthread_self() != mainThread)
        return;
        
    if (!rootObject)
        return;
        
    Window *window = static_cast<Window*>(rootObject);
    if (!window)
        return;
        
    DOM::DocumentImpl *doc = static_cast<DOM::DocumentImpl*>(window->part()->xmlDocImpl());
    if (doc)
        doc->updateRendering();
}

static BOOL partHasSelection(WebCoreBridge *bridge)
{
    if (!bridge)
        return NO;
    
    KHTMLPart *part = [bridge part];
    if (!part)
        return NO;
        
    if (part->selection().isNone())
        return NO;

    // If a part has a selection, it should also have a document.        
    ASSERT(part->xmlDocImpl());

    return YES;
}

static BOOL hasCaseInsensitivePrefix(NSString *string, NSString *prefix)
{
    return [string rangeOfString:prefix options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location !=
        NSNotFound;
}

static BOOL isCaseSensitiveEqual(NSString *a, NSString *b)
{
    return [a caseInsensitiveCompare:b] == NSOrderedSame;
}

@implementation WebCoreBridge

static bool initializedObjectCacheSize = FALSE;
static bool initializedKJS = FALSE;

- (WebCoreBridge *)firstChild
{
    return _firstChild;
}

- (WebCoreBridge *)lastChild
{
    return _lastChild;
}

- (unsigned)childCount
{
    return _childCount;
}

- (WebCoreBridge *)previousSibling;
{
    return _previousSibling;
}

- (WebCoreBridge *)nextSibling;
{
    return _nextSibling;
}

- (BOOL)isDescendantOfFrame:(WebCoreBridge *)ancestor
{
    for (WebCoreBridge *frame = self; frame; frame = (WebCoreBridge *)[frame parent])
        if (frame == ancestor)
            return YES;

    return NO;
}

- (WebCoreBridge *)traverseNextFrameStayWithin:(WebCoreBridge *)stayWithin
{
    WebCoreBridge *firstChild = [self firstChild];
    if (firstChild) {
        ASSERT(!stayWithin || [firstChild isDescendantOfFrame:stayWithin]);
        return firstChild;
    }

    if (self == stayWithin)
        return 0;

    WebCoreBridge *nextSibling = [self nextSibling];
    if (nextSibling) {
        assert(!stayWithin || [nextSibling isDescendantOfFrame:stayWithin]);
        return nextSibling;
    }

    WebCoreBridge *frame = self;
    while (frame && !nextSibling && (!stayWithin || [frame parent] != stayWithin)) {
        frame = (WebCoreBridge *)[frame parent];
        nextSibling = [frame nextSibling];
    }

    if (frame) {
        ASSERT(!stayWithin || !nextSibling || [nextSibling isDescendantOfFrame:stayWithin]);
        return nextSibling;
    }

    return nil;
}

- (void)appendChild:(WebCoreBridge *)child
{
    [child retain];

    [child setParent:self];

    WebCoreBridge *last = _lastChild;

    if (last) {
        last->_nextSibling = child;
        child->_previousSibling = last;
    } else
        _firstChild = child;

    _lastChild = child;

    _childCount++;

    ASSERT(child->_nextSibling == nil);
}

- (void)removeChild:(WebCoreBridge *)child
{
    if (child->_previousSibling)
        child->_previousSibling->_nextSibling = child->_nextSibling;
    else
        _firstChild = child->_nextSibling;
    
    if (child->_nextSibling)
        child->_nextSibling->_previousSibling = child->_previousSibling; 
    else
        _lastChild = child->_previousSibling;

    child->_previousSibling = nil;
    child->_nextSibling = nil;

    _childCount--;

    [child release];
}

- (WebCoreBridge *)childFrameNamed:(NSString *)name
{
    // FIXME: with a better data structure this could be O(1) instead of O(n) in number 
    // of child frames
    for (WebCoreBridge *child = [self firstChild]; child; child = [child nextSibling])
        if ([[child name] isEqualToString:name])
            return child;

    return nil;
}

// Returns the last child of us and any children, or self
- (WebCoreBridge *)_deepLastChildFrame
{
    WebCoreBridge *result = self;
    for (WebCoreBridge *lastChild = [self lastChild]; lastChild; lastChild = [lastChild lastChild])
        result = lastChild;

    return result;
}

// Return next frame to be traversed, visiting children after parent
- (WebCoreBridge *)nextFrameWithWrap:(BOOL)wrapFlag
{
    WebCoreBridge *result = [self traverseNextFrameStayWithin:nil];

    if (!result && wrapFlag)
        return [self mainFrame];

    return result;
}

// Return previous frame to be traversed, exact reverse order of _nextFrame
- (WebCoreBridge *)previousFrameWithWrap:(BOOL)wrapFlag
{
    // FIXME: besides the wrap feature, this is just the traversePreviousNode algorithm

    WebCoreBridge *prevSibling = [self previousSibling];
    if (prevSibling)
        return [prevSibling _deepLastChildFrame];
    if ([self parent])
        return [self parent];
    
    // no siblings, no parent, self==top
    if (wrapFlag)
        return [self _deepLastChildFrame];

    // top view is always the last one in this ordering, so prev is nil without wrap
    return nil;
}

- (void)setFrameNamespace:(NSString *)ns
{
    ASSERT(self == [self mainFrame]);

    if (ns != _frameNamespace){
        [WebCoreFrameNamespaces removeFrame:self fromNamespace:_frameNamespace];
        ns = [ns copy];
        [_frameNamespace release];
        _frameNamespace = ns;
        [WebCoreFrameNamespaces addFrame:self toNamespace:_frameNamespace];
    }
}

- (NSString *)frameNamespace
{
    ASSERT(self == [self mainFrame]);
    return _frameNamespace;
}

- (BOOL)_shouldAllowAccessFrom:(WebCoreBridge *)source
{
    // if no source frame, allow access
    if (source == nil)
        return YES;

    //   - allow access if the two frames are in the same window
    if ([self mainFrame] == [source mainFrame])
        return YES;

    //   - allow if the request is made from a local file.
    NSString *sourceDomain = [self domain];
    if ([sourceDomain length] == 0)
        return YES;

    //   - allow access if this frame or one of its ancestors
    //     has the same origin as source
    for (WebCoreBridge *ancestor = self; ancestor; ancestor = [ancestor parent]) {
        NSString *ancestorDomain = [ancestor domain];
        if (ancestorDomain != nil && 
            isCaseSensitiveEqual(sourceDomain, ancestorDomain))
            return YES;
        
        ancestor = [ancestor parent];
    }

    //   - allow access if this frame is a toplevel window and the source
    //     can access its opener. Note that we only allow one level of
    //     recursion here.
    if ([self parent] == nil) {
        NSString *openerDomain = [[self opener] domain];
        if (openerDomain != nil && isCaseSensitiveEqual(sourceDomain, openerDomain))
            return YES;
    }
    
    // otherwise deny access
    return NO;
}

- (WebCoreBridge *)_descendantFrameNamed:(NSString *)name sourceFrame:(WebCoreBridge *)source
{
    for (WebCoreBridge *frame = self; frame; frame = [frame traverseNextFrameStayWithin:self])
        // for security reasons, we do not want to even make frames visible to frames that
        // can't access them 
        if ([[frame name] isEqualToString:name] && [frame _shouldAllowAccessFrom:source])
            return frame;

    return nil;
}

- (WebCoreBridge *)_frameInAnyWindowNamed:(NSString *)name sourceFrame:(WebCoreBridge *)source
{
    ASSERT(self == [self mainFrame]);

    // Try this WebView first.
    WebCoreBridge *frame = [self _descendantFrameNamed:name sourceFrame:source];

    if (frame != nil)
        return frame;

    // Try other WebViews in the same set

    if ([self frameNamespace] != nil) {
        NSEnumerator *enumerator = [WebCoreFrameNamespaces framesInNamespace:[self frameNamespace]];
        WebCoreBridge *searchFrame;
        while ((searchFrame = [enumerator nextObject]))
            frame = [searchFrame _descendantFrameNamed:name sourceFrame:source];
    }

    return frame;
}

- (WebCoreBridge *)findFrameNamed:(NSString *)name
{
    // First, deal with 'special' names.
    if ([name isEqualToString:@"_self"] || [name isEqualToString:@"_current"])
        return self;
    
    if ([name isEqualToString:@"_top"])
        return [self mainFrame];
    
    if ([name isEqualToString:@"_parent"]) {
        WebCoreBridge *parent = [self parent];
        return parent ? parent : self;
    }
    
    if ([name isEqualToString:@"_blank"])
        return nil;

    // Search from this frame down.
    WebCoreBridge *frame = [self _descendantFrameNamed:name sourceFrame:self];

    // Search in the main frame for this window then in others.
    if (!frame)
        frame = [[self mainFrame] _frameInAnyWindowNamed:name sourceFrame:self];

    return frame;
}

+ (NSArray *)supportedMIMETypes
{
    return [NSArray arrayWithObjects:
        @"text/html",
        @"text/xml",
        @"text/xsl",
        @"application/xml",
        @"application/xhtml+xml",
        @"application/rss+xml",
        @"application/atom+xml",
        @"application/x-webarchive",
        @"multipart/x-mixed-replace",
#if SVG_SUPPORT
        @"image/svg+xml",
#endif
        nil];
}

+ (WebCoreBridge *)bridgeForDOMDocument:(DOMDocument *)document
{
    KHTMLPart *part = [document _documentImpl]->part();
    return part ? KWQ(part)->bridge() : nil;
}

- init
{
    [super init];
    
    _part = new KWQKHTMLPart;
    _part->setBridge(self);

    if (!initializedObjectCacheSize){
        khtml::Cache::setSize([self getObjectCacheSize]);
        initializedObjectCacheSize = TRUE;
    }
    
    if (!initializedKJS) {
        mainThread = pthread_self();
        
        RootObject::setFindRootObjectForNativeHandleFunction (rootForView);

        KJS::Bindings::Instance::setDidExecuteFunction(updateRenderingForBindings);
        
        initializedKJS = TRUE;
    }
    
    _shouldCreateRenderers = YES;
    
    return self;
}

- (void)initializeSettings: (WebCoreSettings *)settings
{
    _part->setSettings ([settings settings]);
}

- (void)dealloc
{
    [self removeFromFrame];
    
    if (_renderPart) {
        _renderPart->deref(_renderPartArena);
    }
    _part->setBridge(nil);
    _part->deref();
        
    [super dealloc];
}

- (void)finalize
{
    // FIXME: This work really should not be done at deallocation time.
    // We need to do it at some well-defined time instead.

    [self removeFromFrame];
    
    if (_renderPart) {
        _renderPart->deref(_renderPartArena);
    }
    _part->setBridge(nil);
    _part->deref();
        
    [super finalize];
}

- (KWQKHTMLPart *)part
{
    return _part;
}

- (void)setRenderPart:(KHTMLRenderPart *)newPart;
{
    RenderArena *arena = newPart->ref();
    if (_renderPart) {
        _renderPart->deref(_renderPartArena);
    }
    _renderPart = newPart;
    _renderPartArena = arena;
}

- (KHTMLRenderPart *)renderPart
{
    return _renderPart;
}

- (void)setParent:(WebCoreBridge *)parent
{
    _part->setParent([parent part]);
}

- (WebCoreBridge *)parent
{
    KWQKHTMLPart *parentPart = KWQ(_part->parentPart());
    if (!parentPart)
        return nil;
    return parentPart->bridge();
}

- (void)provisionalLoadStarted
{
    _part->provisionalLoadStarted();
}

- (void)openURL:(NSURL *)URL reload:(BOOL)reload contentType:(NSString *)contentType refresh:(NSString *)refresh lastModified:(NSDate *)lastModified pageCache:(NSDictionary *)pageCache
{
    if (pageCache) {
        KWQPageState *state = [pageCache objectForKey:WebCorePageCacheStateKey];
        _part->openURLFromPageCache(state);
        [state invalidate];
        return;
    }
        
    // arguments
    URLArgs args(_part->browserExtension()->urlArgs());
    args.reload = reload;
    if (contentType) {
        args.serviceType = QString::fromNSString(contentType);
    }
    _part->browserExtension()->setURLArgs(args);

    // opening the URL
    if (_part->didOpenURL(URL)) {
        // things we have to set up after calling didOpenURL
        if (refresh) {
            _part->addMetaData("http-refresh", QString::fromNSString(refresh));
        }
        if (lastModified) {
            NSString *modifiedString = [lastModified descriptionWithCalendarFormat:@"%a %b %d %Y %H:%M:%S" timeZone:nil locale:nil];
            _part->addMetaData("modified", QString::fromNSString(modifiedString));
        }
    }
}

- (void)setEncoding:(NSString *)encoding userChosen:(BOOL)userChosen
{
    _part->setEncoding(QString::fromNSString(encoding), userChosen);
}

- (void)addData:(NSData *)data
{
    DocumentImpl *doc = _part->xmlDocImpl();
    
    // Document may be nil if the part is about to redirect
    // as a result of JS executing during load, i.e. one frame
    // changing another's location before the frame's document
    // has been created. 
    if (doc){
        doc->setShouldCreateRenderers([self shouldCreateRenderers]);
        _part->addData((const char *)[data bytes], [data length]);
    }
}

- (void)closeURL
{
    _part->closeURL();
}

- (void)stopLoading
{
    _part->stopLoading();
}

- (void)didNotOpenURL:(NSURL *)URL pageCache:(NSDictionary *)pageCache
{
    _part->didNotOpenURL(KURL(URL).url());

    // We might have made a page cache item, but now we're bailing out due to an error before we ever
    // transitioned to the new page (before WebFrameState==commit).  The goal here is to restore any state
    // so that the existing view (that wenever got far enough to replace) can continue being used.
    DocumentImpl *doc = _part->xmlDocImpl();
    if (doc) {
        doc->setInPageCache(NO);
    }
    KWQPageState *state = [pageCache objectForKey:WebCorePageCacheStateKey];
    [state invalidate];
}

- (BOOL)canLoadURL:(NSURL *)URL fromReferrer:(NSString *)referrer hideReferrer:(BOOL *)hideReferrer
{
    BOOL referrerIsWebURL = hasCaseInsensitivePrefix(referrer, @"http:") || hasCaseInsensitivePrefix(referrer, @"https:");
    BOOL referrerIsLocalURL = hasCaseInsensitivePrefix(referrer, @"file:") || hasCaseInsensitivePrefix(referrer, @"applewebdata:");
    BOOL URLIsFileURL = [URL scheme] != NULL && [[URL scheme] compare:@"file" options:(NSCaseInsensitiveSearch|NSLiteralSearch)] == NSOrderedSame;
    
    *hideReferrer = !referrerIsWebURL;
    return !URLIsFileURL || referrerIsLocalURL;
}

- (void)saveDocumentState
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (doc != 0){
        QStringList list = doc->docState();
        NSMutableArray *documentState = [[[NSMutableArray alloc] init] autorelease];
        
        for (uint i = 0; i < list.count(); i++){
            QString s = list[i];
            [documentState addObject: [NSString stringWithCharacters: (const unichar *)s.unicode() length: s.length()]];
        }
        [self saveDocumentState: documentState];
    }
}

- (void)restoreDocumentState
{
    DocumentImpl *doc = _part->xmlDocImpl();
    
    if (doc != 0){
        NSArray *documentState = [self documentState];
        
        QStringList s;
        for (uint i = 0; i < [documentState count]; i++){
            NSString *string = [documentState objectAtIndex: i];
            s.append(QString::fromNSString(string));
        }
            
        doc->setRestoreState(s);
    }
}

- (void)scrollToAnchorWithURL:(NSURL *)URL
{
    _part->scrollToAnchor(KURL(URL).url().latin1());
}

- (BOOL)scrollOverflowInDirection:(WebScrollDirection)direction granularity:(WebScrollGranularity)granularity
{
    if (_part == NULL) {
        return NO;
    }
    return _part->scrollOverflow((KWQScrollDirection)direction, (KWQScrollGranularity)granularity);
}

- (BOOL)sendScrollWheelEvent:(NSEvent *)event
{
    return _part ? _part->wheelEvent(event) : NO;
}

- (BOOL)saveDocumentToPageCache
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (!doc)
        return NO;
    if (!doc->view())
        return NO;

    _part->clearTimers();

    JSLock lock;

    SavedProperties *windowProperties = new SavedProperties;
    _part->saveWindowProperties(windowProperties);

    SavedProperties *locationProperties = new SavedProperties;
    _part->saveLocationProperties(locationProperties);
    
    SavedBuiltins *interpreterBuiltins = new SavedBuiltins;
    _part->saveInterpreterBuiltins(*interpreterBuiltins);

    KWQPageState *pageState = [[KWQPageState alloc] initWithDocument:doc
                                                                 URL:_part->m_url
                                                    windowProperties:windowProperties
                                                  locationProperties:locationProperties
                                                 interpreterBuiltins:interpreterBuiltins
                                                      pausedTimeouts:_part->pauseTimeouts()];

    BOOL result = [self saveDocumentToPageCache:pageState];

    [pageState release];

    return result;
}

- (BOOL)canCachePage
{
    return _part->canCachePage();
}

- (void)clear
{
    _part->clear();
}

- (void)end
{
    _part->end();
}

- (void)stop
{
    _part->stop();
}

- (void)handleFallbackContent
{
    _part->handleFallbackContent();
}

- (void)createKHTMLViewWithNSView:(NSView *)view marginWidth:(int)mw marginHeight:(int)mh
{
    // If we own the view, delete the old one - otherwise the render _part will take care of deleting the view.
    [self removeFromFrame];

    KHTMLView *kview = new KHTMLView(_part, 0);
    _part->setView(kview);
    kview->deref();

    kview->setView(view);
    if (mw >= 0)
        kview->setMarginWidth(mw);
    if (mh >= 0)
        kview->setMarginHeight(mh);
}

- (void)scrollToAnchor:(NSString *)a
{
    _part->gotoAnchor(QString::fromNSString(a));
}

- (BOOL)isSelectionEditable
{
    // EDIT FIXME: This needs to consider the entire selected range
    NodeImpl *startNode = _part->selection().start().node();
    return startNode ? startNode->isContentEditable() : NO;
}

- (WebSelectionState)selectionState
{
    switch (_part->selection().state()) {
        case SelectionController::NONE:
            return WebSelectionStateNone;
        case SelectionController::CARET:
            return WebSelectionStateCaret;
        case SelectionController::RANGE:
            return WebSelectionStateRange;
    }
    
    ASSERT_NOT_REACHED();
    return WebSelectionStateNone;
}

- (NSString *)_documentTypeString
{
    NSString *documentTypeString = nil;
    DOM::DocumentImpl *doc = _part->xmlDocImpl();
    if (doc) {
        DocumentTypeImpl *doctype = doc->realDocType();
        if (doctype) {
            documentTypeString = doctype->toString().qstring().getNSString();
        }
    }
    return documentTypeString;
}

- (NSString *)_stringWithDocumentTypeStringAndMarkupString:(NSString *)markupString
{
    NSString *documentTypeString = [self _documentTypeString];
    if (documentTypeString && markupString) {
        return [NSString stringWithFormat:@"%@%@", documentTypeString, markupString];
    } else if (documentTypeString) {
        return documentTypeString;
    } else if (markupString) {
        return markupString;
    } else {
        return @"";
    }
}

- (NSArray *)nodesFromList:(QPtrList<NodeImpl> *)nodeList
{
    NSMutableArray *nodes = [NSMutableArray arrayWithCapacity:nodeList->count()];
    for (QPtrListIterator<NodeImpl> i(*nodeList); i.current(); ++i) {
        [nodes addObject:[DOMNode _nodeWithImpl:i.current()]];
    }
    return nodes;
}

- (NSString *)markupStringFromNode:(DOMNode *)node nodes:(NSArray **)nodes
{
    // FIXME: This is never "for interchange". Is that right? See the next method.
    QPtrList<NodeImpl> nodeList;
    NSString *markupString = createMarkup([node _nodeImpl], IncludeNode, nodes ? &nodeList : 0).getNSString();
    if (nodes) {
        *nodes = [self nodesFromList:&nodeList];
    }
    return [self _stringWithDocumentTypeStringAndMarkupString:markupString];
}

- (NSString *)markupStringFromRange:(DOMRange *)range nodes:(NSArray **)nodes
{
    // FIXME: This is always "for interchange". Is that right? See the previous method.
    QPtrList<NodeImpl> nodeList;
    NSString *markupString = createMarkup([range _rangeImpl], nodes ? &nodeList : 0, AnnotateForInterchange).getNSString();
    if (nodes) {
        *nodes = [self nodesFromList:&nodeList];
    }
    return [self _stringWithDocumentTypeStringAndMarkupString:markupString];
}

- (NSString *)selectedString
{
    QString text = _part->selectedText();
    text.replace(QChar('\\'), _part->backslashAsCurrencySymbol());
    return [[text.getNSString() copy] autorelease];
}

- (NSString *)stringForRange:(DOMRange *)range
{
    QString text = plainText([range _rangeImpl]);
    text.replace(QChar('\\'), _part->backslashAsCurrencySymbol());
    return [[text.getNSString() copy] autorelease];
}

- (void)selectAll
{
    _part->selectAll();
}

- (void)deselectAll
{
    [self deselectText];
    DocumentImpl *doc = _part->xmlDocImpl();
    if (doc) {
        doc->setFocusNode(0);
    }
}

- (void)deselectText
{
    _part->clearSelection();
}

- (BOOL)isFrameSet
{
    return _part->isFrameSet();
}

- (void)reapplyStylesForDeviceType:(WebCoreDeviceType)deviceType
{
    _part->setMediaType(deviceType == WebCoreDeviceScreen ? "screen" : "print");
    DocumentImpl *doc = _part->xmlDocImpl();
    if (doc) {
        static QPaintDevice screen;
        static QPrinter printer;
        doc->setPaintDevice(deviceType == WebCoreDeviceScreen ? &screen : &printer);
    }
    return _part->reparseConfiguration();
}

static BOOL nowPrinting(WebCoreBridge *self)
{
    DocumentImpl *doc = self->_part->xmlDocImpl();
    return doc && doc->paintDevice() && doc->paintDevice()->devType() == QInternal::Printer;
}

// Set or unset the printing mode in the view.  We only toy with this if we're printing.
- (void)_setupRootForPrinting:(BOOL)onOrOff
{
    if (nowPrinting(self)) {
        RenderCanvas *root = static_cast<khtml::RenderCanvas *>(_part->xmlDocImpl()->renderer());
        if (root) {
            root->setPrintingMode(onOrOff);
        }
    }
}

- (void)forceLayoutAdjustingViewSize:(BOOL)flag
{
    [self _setupRootForPrinting:YES];
    _part->forceLayout();
    if (flag) {
        [self adjustViewSize];
    }
    [self _setupRootForPrinting:NO];
}

- (void)forceLayoutWithMinimumPageWidth:(float)minPageWidth maximumPageWidth:(float)maxPageWidth adjustingViewSize:(BOOL)flag
{
    [self _setupRootForPrinting:YES];
    _part->forceLayoutWithPageWidthRange(minPageWidth, maxPageWidth);
    if (flag) {
        [self adjustViewSize];
    }
    [self _setupRootForPrinting:NO];
}

- (void)sendResizeEvent
{
    _part->sendResizeEvent();
}

- (void)sendScrollEvent
{
    _part->sendScrollEvent();
}

- (void)drawRect:(NSRect)rect withPainter:(QPainter *)p
{
    [self _setupRootForPrinting:YES];
    _part->paint(p, QRect(rect));
    [self _setupRootForPrinting:NO];
}

- (void)drawRect:(NSRect)rect
{
    QPainter painter(nowPrinting(self));
    bool displaysWithFocusAttributes = _part->displaysWithFocusAttributes();
    painter.setUsesInactiveTextBackgroundColor(!displaysWithFocusAttributes);
    [self drawRect:rect withPainter:&painter];
}

// Used by pagination code called from AppKit when a standalone web page is printed.
- (NSArray*)computePageRectsWithPrintWidthScaleFactor:(float)printWidthScaleFactor printHeight:(float)printHeight
{
    [self _setupRootForPrinting:YES];
    NSMutableArray* pages = [NSMutableArray arrayWithCapacity:5];
    if (printWidthScaleFactor <= 0) {
        ERROR("printWidthScaleFactor has bad value %.2f", printWidthScaleFactor);
        return pages;
    }
    
    if (printHeight <= 0) {
        ERROR("printHeight has bad value %.2f", printHeight);
        return pages;
    }

    if (!_part || !_part->xmlDocImpl() || !_part->view()) return pages;
    RenderCanvas* root = static_cast<khtml::RenderCanvas *>(_part->xmlDocImpl()->renderer());
    if (!root) return pages;
    
    KHTMLView* view = _part->view();
    NSView* documentView = view->getDocumentView();
    if (!documentView)
        return pages;

    float currPageHeight = printHeight;
    float docHeight = root->layer()->height();
    float docWidth = root->layer()->width();
    float printWidth = docWidth/printWidthScaleFactor;
    
    // We need to give the part the opportunity to adjust the page height at each step.
    for (float i = 0; i < docHeight; i += currPageHeight) {
        float proposedBottom = kMin(docHeight, i + printHeight);
        _part->adjustPageHeight(&proposedBottom, i, proposedBottom, i);
        currPageHeight = kMax(1.0f, proposedBottom - i);
        for (float j = 0; j < docWidth; j += printWidth) {
            NSValue* val = [NSValue valueWithRect: NSMakeRect(j, i, printWidth, currPageHeight)];
            [pages addObject: val];
        }
    }
    [self _setupRootForPrinting:NO];
    
    return pages;
}

// This is to support the case where a webview is embedded in the view that's being printed
- (void)adjustPageHeightNew:(float *)newBottom top:(float)oldTop bottom:(float)oldBottom limit:(float)bottomLimit
{
    [self _setupRootForPrinting:YES];
    _part->adjustPageHeight(newBottom, oldTop, oldBottom, bottomLimit);
    [self _setupRootForPrinting:NO];
}

- (NSObject *)copyDOMNode:(NodeImpl *)node copier:(id <WebCoreDOMTreeCopier>)copier
{
    NSMutableArray *children = [[NSMutableArray alloc] init];
    for (NodeImpl *child = node->firstChild(); child; child = child->nextSibling()) {
        [children addObject:[self copyDOMNode:child copier:copier]];
    }
    NSObject *copiedNode = [copier nodeWithName:node->nodeName().qstring().getNSString()
                                          value:node->nodeValue().qstring().getNSString()
                                         source:createMarkup(node, ChildrenOnly).getNSString()
                                       children:children];
    [children release];
    return copiedNode;
}

- (NSObject *)copyDOMTree:(id <WebCoreDOMTreeCopier>)copier
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (!doc) {
        return nil;
    }
    return [self copyDOMNode:doc copier:copier];
}

- (NSObject *)copyRenderNode:(RenderObject *)node copier:(id <WebCoreRenderTreeCopier>)copier
{
    NSMutableArray *children = [[NSMutableArray alloc] init];
    for (RenderObject *child = node->firstChild(); child; child = child->nextSibling()) {
        [children addObject:[self copyRenderNode:child copier:copier]];
    }
          
    NSString *name = [[NSString alloc] initWithUTF8String:node->renderName()];
    
    RenderWidget *renderWidget = node->isWidget() ? static_cast<RenderWidget *>(node) : 0;
    QWidget *widget = renderWidget ? renderWidget->widget() : 0;
    NSView *view = widget ? widget->getView() : nil;
    
    int nx, ny;
    node->absolutePosition(nx,ny);
    NSObject *copiedNode = [copier nodeWithName:name
                                       position:NSMakePoint(nx,ny)
                                           rect:NSMakeRect(node->xPos(), node->yPos(), node->width(), node->height())
                                           view:view
                                       children:children];
    
    [name release];
    [children release];
    
    return copiedNode;
}

- (NSObject *)copyRenderTree:(id <WebCoreRenderTreeCopier>)copier
{
    RenderObject *renderer = _part->renderer();
    if (!renderer) {
        return nil;
    }
    return [self copyRenderNode:renderer copier:copier];
}

- (void)removeFromFrame
{
    _part->setView(0);
}

- (void)installInFrame:(NSView *)view
{
    // If this isn't the main frame, it must have a render _part set, or it
    // won't ever get installed in the view hierarchy.
    ASSERT(self == [self mainFrame] || _renderPart != nil);

    _part->view()->setView(view);
    if (_renderPart) {
        _renderPart->setWidget(_part->view());
        // Now the render part owns the view, so we don't any more.
    }

    _part->view()->initScrollBars();
}

- (void)setActivationEventNumber:(int)num
{
    _part->setActivationEventNumber(num);
}

- (void)mouseDown:(NSEvent *)event
{
    _part->mouseDown(event);
}

- (void)mouseDragged:(NSEvent *)event
{
    _part->mouseDragged(event);
}

- (void)mouseUp:(NSEvent *)event
{
    _part->mouseUp(event);
}

- (void)mouseMoved:(NSEvent *)event
{
    _part->mouseMoved(event);
}

- (BOOL)sendContextMenuEvent:(NSEvent *)event
{
    return _part->sendContextMenuEvent(event);
}

- (DOMElement *)elementForView:(NSView *)view
{
    // FIXME: implemented currently for only a subset of the KWQ widgets
    if ([view conformsToProtocol:@protocol(KWQWidgetHolder)]) {
        NSView <KWQWidgetHolder> *widgetHolder = view;
        QWidget *widget = [widgetHolder widget];
        if (widget != nil && widget->eventFilterObject() != nil) {
            NodeImpl *node = static_cast<const RenderWidget *>(widget->eventFilterObject())->element();
            return [DOMElement _elementWithImpl:static_cast<ElementImpl *>(node)];
        }
    }
    return nil;
}

static HTMLInputElementImpl *inputElementFromDOMElement(DOMElement *element)
{
    NodeImpl *node = [element _nodeImpl];
    if (node->hasTagName(inputTag)) {
        return static_cast<HTMLInputElementImpl *>(node);
    }
    return nil;
}

static HTMLFormElementImpl *formElementFromDOMElement(DOMElement *element)
{
    NodeImpl *node = [element _nodeImpl];
    // This should not be necessary, but an XSL file on
    // maps.google.com crashes otherwise because it is an xslt file
    // that contains <form> elements that aren't in any namespace, so
    // they come out as generic CML elements
    if (node && node->hasTagName(formTag)) {
        return static_cast<HTMLFormElementImpl *>(node);
    }
    return nil;
}

- (DOMElement *)elementWithName:(NSString *)name inForm:(DOMElement *)form
{
    HTMLFormElementImpl *formElement = formElementFromDOMElement(form);
    if (formElement) {
        QPtrVector<HTMLGenericFormElementImpl> &elements = formElement->formElements;
        QString targetName = QString::fromNSString(name);
        for (unsigned int i = 0; i < elements.count(); i++) {
            HTMLGenericFormElementImpl *elt = elements.at(i);
            // Skip option elements, other duds
            if (elt->name() == targetName) {
                return [DOMElement _elementWithImpl:elt];
            }
        }
    }
    return nil;
}

- (BOOL)elementDoesAutoComplete:(DOMElement *)element
{
    HTMLInputElementImpl *inputElement = inputElementFromDOMElement(element);
    return inputElement != nil
        && inputElement->inputType() == HTMLInputElementImpl::TEXT
        && inputElement->autoComplete();
}

- (BOOL)elementIsPassword:(DOMElement *)element
{
    HTMLInputElementImpl *inputElement = inputElementFromDOMElement(element);
    return inputElement != nil
        && inputElement->inputType() == HTMLInputElementImpl::PASSWORD;
}

- (DOMElement *)formForElement:(DOMElement *)element;
{
    HTMLInputElementImpl *inputElement = inputElementFromDOMElement(element);
    if (inputElement) {
        HTMLFormElementImpl *formElement = inputElement->form();
        if (formElement) {
            return [DOMElement _elementWithImpl:formElement];
        }
    }
    return nil;
}

- (DOMElement *)currentForm
{
    HTMLFormElementImpl *formElement = _part->currentForm();
    return formElement ? [DOMElement _elementWithImpl:formElement] : nil;
}

- (NSArray *)controlsInForm:(DOMElement *)form
{
    NSMutableArray *results = nil;
    HTMLFormElementImpl *formElement = formElementFromDOMElement(form);
    if (formElement) {
        QPtrVector<HTMLGenericFormElementImpl> &elements = formElement->formElements;
        for (unsigned int i = 0; i < elements.count(); i++) {
            if (elements.at(i)->isEnumeratable()) { // Skip option elements, other duds
                DOMElement *de = [DOMElement _elementWithImpl:elements.at(i)];
                if (!results) {
                    results = [NSMutableArray arrayWithObject:de];
                } else {
                    [results addObject:de];
                }
            }
        }
    }
    return results;
}

- (NSString *)searchForLabels:(NSArray *)labels beforeElement:(DOMElement *)element
{
    return _part->searchForLabelsBeforeElement(labels, [element _elementImpl]);
}

- (NSString *)matchLabels:(NSArray *)labels againstElement:(DOMElement *)element
{
    return _part->matchLabelsAgainstElement(labels, [element _elementImpl]);
}

- (NSDictionary *)elementAtPoint:(NSPoint)point
{
    RenderObject *renderer = _part->renderer();
    if (!renderer) 
        return nil;
    
    RenderObject::NodeInfo nodeInfo(true, true);
    renderer->layer()->hitTest(nodeInfo, (int)point.x, (int)point.y);

    NodeImpl *n;
    QWidget *widget = 0;
    QPoint widgetPoint(point);
    
    while (true) {
        n = nodeInfo.innerNode();
        if (!n || !n->renderer() || !n->renderer()->isWidget())
            break;
        widget = static_cast<RenderWidget *>(n->renderer())->widget();
        if (!widget || !widget->inherits("KHTMLView"))
            break;
        KHTMLPart *kpart = static_cast<DOM::HTMLFrameElementImpl *>(n)->contentPart();
        if (!kpart || !static_cast<KWQKHTMLPart *>(kpart)->renderer())
            break;
        int absX, absY;
        n->renderer()->absolutePosition(absX, absY, true);
        KHTMLView *view = static_cast<KHTMLView *>(widget);
        widgetPoint.setX(widgetPoint.x() - absX + view->contentsX());
        widgetPoint.setY(widgetPoint.y() - absY + view->contentsY());

        RenderObject::NodeInfo widgetNodeInfo(true, true);
        static_cast<KWQKHTMLPart *>(kpart)->renderer()->layer()->hitTest(widgetNodeInfo, widgetPoint.x(), widgetPoint.y());
        nodeInfo = widgetNodeInfo;
    }
    
    NSMutableDictionary *element = [NSMutableDictionary dictionary];
    [element setObject:[NSNumber numberWithBool:_part->isPointInsideSelection((int)point.x, (int)point.y)]
                forKey:WebCoreElementIsSelectedKey];

    // Find the title in the nearest enclosing DOM node.
    // For <area> tags in image maps, walk the tree for the <area>, not the <img> using it.
    for (NodeImpl *titleNode = nodeInfo.innerNode(); titleNode; titleNode = titleNode->parentNode()) {
        if (titleNode->isElementNode()) {
            const AtomicString& title = static_cast<ElementImpl *>(titleNode)->getAttribute(titleAttr);
            if (!title.isNull()) {
                // We found a node with a title.
                QString titleText = title.qstring();
                titleText.replace(QChar('\\'), _part->backslashAsCurrencySymbol());
                [element setObject:titleText.getNSString() forKey:WebCoreElementTitleKey];
                break;
            }
        }
    }

    NodeImpl *URLNode = nodeInfo.URLElement();
    if (URLNode) {
        ElementImpl *e = static_cast<ElementImpl *>(URLNode);
        DocumentImpl *doc = e->getDocument();
        ASSERT(doc);
        
        const AtomicString& title = e->getAttribute(titleAttr);
        if (!title.isEmpty()) {
            QString titleText = title.qstring();
            titleText.replace(QChar('\\'), _part->backslashAsCurrencySymbol());
            [element setObject:titleText.getNSString() forKey:WebCoreElementLinkTitleKey];
        }
        
        const AtomicString& link = e->getAttribute(hrefAttr);
        if (!link.isNull()) {
            QString t = plainText(rangeOfContents(e).get());
            if (!t.isEmpty()) {
                [element setObject:t.getNSString() forKey:WebCoreElementLinkLabelKey];
            }
            QString URLString = parseURL(link).qstring();
            [element setObject:doc->completeURL(URLString).getNSString() forKey:WebCoreElementLinkURLKey];
        }
        
        DOMString target = e->getAttribute(targetAttr);
        if (target.isEmpty() && doc) { // FIXME: Take out this doc check when we're not just before a release.
            target = doc->baseTarget();
        }
        if (!target.isEmpty()) {
            [element setObject:target.qstring().getNSString() forKey:WebCoreElementLinkTargetFrameKey];
        }
    }

    NodeImpl *node = nodeInfo.innerNonSharedNode();
    if (node) {
        [element setObject:[DOMNode _nodeWithImpl:node] forKey:WebCoreElementDOMNodeKey];
    
        // Only return image information if there is an image.
        if (node->renderer() && node->renderer()->isImage()) {
            RenderImage *r = static_cast<RenderImage *>(node->renderer());
            if (!r->isDisplayingError()) {
                QPixmap p = r->pixmap();
                if (p.imageRenderer())
                    [element setObject:p.imageRenderer() forKey:WebCoreElementImageRendererKey];
            }

            int x, y;
            if (r->absolutePosition(x, y)) {
                NSValue *rect = [NSValue valueWithRect:NSMakeRect(x, y, r->contentWidth(), r->contentHeight())];
                [element setObject:rect forKey:WebCoreElementImageRectKey];
            }

            ElementImpl *i = static_cast<ElementImpl*>(node);
    
            // FIXME: Code copied from RenderImage::updateFromElement; should share.
            DOMString attr;
            if (i->hasTagName(objectTag)) {
                attr = i->getAttribute(dataAttr);
            } else {
                attr = i->getAttribute(srcAttr);
            }
            if (!attr.isEmpty()) {
                QString URLString = parseURL(attr).qstring();
                [element setObject:i->getDocument()->completeURL(URLString).getNSString() forKey:WebCoreElementImageURLKey];
            }
            
            // FIXME: Code copied from RenderImage::updateFromElement; should share.
            DOMString alt;
            if (i->hasTagName(inputTag))
                alt = static_cast<HTMLInputElementImpl *>(i)->altText();
            else if (i->hasTagName(imgTag))
                alt = static_cast<HTMLImageElementImpl *>(i)->altText();
            if (!alt.isNull()) {
                QString altText = alt.qstring();
                altText.replace(QChar('\\'), _part->backslashAsCurrencySymbol());
                [element setObject:altText.getNSString() forKey:WebCoreElementImageAltStringKey];
            }
        }
    }
    
    return element;
}

- (NSURL *)URLWithAttributeString:(NSString *)string
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (!doc) {
        return nil;
    }
    QString rel = parseURL(QString::fromNSString(string)).qstring();
    return KURL(doc->baseURL(), rel, doc->decoder() ? doc->decoder()->codec() : 0).getNSURL();
}

- (BOOL)searchFor:(NSString *)string direction:(BOOL)forward caseSensitive:(BOOL)caseFlag wrap:(BOOL)wrapFlag
{
    return _part->findString(string, forward, caseFlag, wrapFlag);
}

- (NSString *)advanceToNextMisspelling
{
    return _part->advanceToNextMisspelling().getNSString();
}

- (NSString *)advanceToNextMisspellingStartingJustBeforeSelection
{
    return _part->advanceToNextMisspelling(true).getNSString();
}

- (void)unmarkAllMisspellings
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (!doc) {
        return;
    }
    doc->removeMarkers(DOM::DocumentMarker::Spelling);
}

- (void)setTextSizeMultiplier:(float)multiplier
{
    int newZoomFactor = (int)rint(multiplier * 100);
    if (_part->zoomFactor() == newZoomFactor) {
        return;
    }
    _part->setZoomFactor(newZoomFactor);
}

- (CFStringEncoding)textEncoding
{
    return KWQCFStringEncodingFromIANACharsetName(_part->encoding().latin1());
}

- (NSView *)nextKeyView
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (!doc) {
        return nil;
    }
    return _part->nextKeyView(doc->focusNode(), KWQSelectingNext);
}

- (NSView *)previousKeyView
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (!doc) {
        return nil;
    }
    return _part->nextKeyView(doc->focusNode(), KWQSelectingPrevious);
}

- (NSView *)nextKeyViewInsideWebFrameViews
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (!doc) {
        return nil;
    }
    
    return _part->nextKeyViewInFrameHierarchy(doc->focusNode(), KWQSelectingNext);
}

- (NSView *)previousKeyViewInsideWebFrameViews
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (!doc) {
        return nil;
    }

    return _part->nextKeyViewInFrameHierarchy(doc->focusNode(), KWQSelectingPrevious);
}

- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)string
{
    return [self stringByEvaluatingJavaScriptFromString:string forceUserGesture:true];
}

// 
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)string forceUserGesture:(BOOL)forceUserGesture
{
    _part->createEmptyDocument();
    return _part->executeScript(QString::fromNSString(string), forceUserGesture).asString().getNSString();
}

- (WebScriptObject *)windowScriptObject
{
    return _part->windowScriptObject();
}

- (NPObject *)windowScriptNPObject
{
    return _part->windowScriptNPObject();
}

- (DOMDocument *)DOMDocument
{
    return [DOMDocument _documentWithImpl:_part->xmlDocImpl()];
}

- (DOMHTMLElement *)frameElement
{
    return (DOMHTMLElement *)[[self DOMDocument] _ownerElement];
}

- (NSAttributedString *)selectedAttributedString
{
    return _part->attributedString(_part->selectionStart(), _part->selectionStartOffset(), _part->selectionEnd(), _part->selectionEndOffset());
}

- (NSAttributedString *)attributedStringFrom:(DOMNode *)start startOffset:(int)startOffset to:(DOMNode *)end endOffset:(int)endOffset
{
    DOMNode *startNode = start;
    DOMNode *endNode = end;
    return _part->attributedString([startNode _nodeImpl], startOffset, [endNode _nodeImpl], endOffset);
}

- (NSRect)selectionRect
{
    return _part->selectionRect(); 
}

- (NSRect)visibleSelectionRect
{
    return _part->visibleSelectionRect(); 
}

- (void)centerSelectionInVisibleArea
{
    _part->centerSelectionInVisibleArea(); 
}

- (NSRect)caretRectAtNode:(DOMNode *)node offset:(int)offset affinity:(NSSelectionAffinity)affinity
{
    return [node _nodeImpl]->renderer()->caretRect(offset, static_cast<EAffinity>(affinity));
}
- (NSRect)firstRectForDOMRange:(DOMRange *)range
{
    int extraWidthToEndOfLine = 0;
    QRect startCaretRect = [[range startContainer] _nodeImpl]->renderer()->caretRect([range startOffset], UPSTREAM, &extraWidthToEndOfLine);
    QRect endCaretRect = [[range endContainer] _nodeImpl]->renderer()->caretRect([range endOffset], UPSTREAM);

    if (startCaretRect.y() == endCaretRect.y()) {
        // start and end are on the same line
        return QRect(MIN(startCaretRect.x(), endCaretRect.x()), 
                     startCaretRect.y(), 
                     abs(endCaretRect.x() - startCaretRect.x()),
                     MAX(startCaretRect.height(), endCaretRect.height()));
    }

    // start and end aren't on the same line, so go from start to the end of its line
    return QRect(startCaretRect.x(), 
                 startCaretRect.y(),
                 startCaretRect.width() + extraWidthToEndOfLine,
                 startCaretRect.height());
}

- (NSImage *)selectionImage
{
    return _part->selectionImage();
}

- (void)setName:(NSString *)name
{
    _part->setName(QString::fromNSString(name));
}

- (NSString *)name
{
    return _part->name().getNSString();
}

- (void)_addFramePathToString:(NSMutableString *)path
{
    NSString *name = [self name];
    if ([name hasPrefix:@"<!--framePath "]) {
        // we have a generated name - take the path from our name
        NSRange ourPathRange = {14, [name length] - 14 - 3};
        [path appendString:[name substringWithRange:ourPathRange]];
    } else {
        // we don't have a generated name - just add our simple name to the end
        [[self parent] _addFramePathToString:path];
        [path appendString:@"/"];
        if (name)
            [path appendString:name];
    }
}

// Generate a repeatable name for a child about to be added to us.  The name must be
// unique within the frame tree.  The string we generate includes a "path" of names
// from the root frame down to us.  For this path to be unique, each set of siblings must
// contribute a unique name to the path, which can't collide with any HTML-assigned names.
// We generate this path component by index in the child list along with an unlikely frame name.
- (NSString *)generateFrameName
{
    NSMutableString *path = [NSMutableString stringWithCapacity:256];
    [path insertString:@"<!--framePath " atIndex:0];
    [self _addFramePathToString:path];
    // The new child's path component is all but the 1st char and the last 3 chars
    // FIXME: Shouldn't this number be the index of this frame in its parent rather than the child count?
    [path appendFormat:@"/<!--frame%d-->-->", [self childCount]];
    return path;
}

- (NSURL *)URL
{
    return _part->url().getNSURL();
}

- (NSURL *)baseURL
{
    return _part->completeURL(_part->xmlDocImpl()->baseURL()).getNSURL();
}

- (NSString *)referrer
{
    return _part->referrer().getNSString();
}

- (NSString *)domain
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (doc && doc->isHTMLDocument()) {
        return doc->domain().qstring().getNSString();
    }
    return nil;
}

- (WebCoreBridge *)opener
{
    KHTMLPart *openerPart = _part->opener();

    if (openerPart)
        return KWQ(openerPart)->bridge();

    return nil;
}

- (void)setOpener:(WebCoreBridge *)bridge;
{
    KHTMLPart *p = [bridge part];
    
    if (p)
        p->setOpener(_part);
}

+ (NSString *)stringWithData:(NSData *)data textEncoding:(CFStringEncoding)textEncoding
{
    if (textEncoding == kCFStringEncodingInvalidId || textEncoding == kCFStringEncodingISOLatin1) {
        textEncoding = kCFStringEncodingWindowsLatin1;
    }
    return QTextCodec(textEncoding).toUnicode((const char*)[data bytes], [data length]).getNSString();
}

+ (NSString *)stringWithData:(NSData *)data textEncodingName:(NSString *)textEncodingName
{
    CFStringEncoding textEncoding = KWQCFStringEncodingFromIANACharsetName([textEncodingName lossyCString]);
    return [WebCoreBridge stringWithData:data textEncoding:textEncoding];
}

- (BOOL)needsLayout
{
    RenderObject *renderer = _part->renderer();
    return renderer ? renderer->needsLayout() : false;
}

- (void)setNeedsLayout
{
    RenderObject *renderer = _part->renderer();
    if (renderer)
        renderer->setNeedsLayout(true);
}

- (BOOL)interceptKeyEvent:(NSEvent *)event toView:(NSView *)view
{
    return _part->keyEvent(event);
}

- (NSString *)renderTreeAsExternalRepresentation
{
    return externalRepresentation(_part->renderer()).getNSString();
}

- (void)setSelectionFromNone
{
    _part->setSelectionFromNone();
}

- (void)setDisplaysWithFocusAttributes:(BOOL)flag
{
    _part->setDisplaysWithFocusAttributes(flag);
}

- (void)setWindowHasFocus:(BOOL)flag
{
    _part->setWindowHasFocus(flag);
}

- (void)setShouldCreateRenderers:(BOOL)f
{
    _shouldCreateRenderers = f;
}

- (BOOL)shouldCreateRenderers
{
    return _shouldCreateRenderers;
}

- (int)numPendingOrLoadingRequests
{
    DocumentImpl *doc = _part->xmlDocImpl();
    
    if (doc)
        return KWQNumberOfPendingOrLoadingRequests (doc->docLoader());
    return 0;
}

- (BOOL)doneProcessingData
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (doc) {
        Tokenizer* tok = doc->tokenizer();
        if (tok)
            return !tok->processingData();
    }
    return YES;
}

- (BOOL)shouldClose
{
    return _part->shouldClose();
}

- (NSColor *)bodyBackgroundColor
{
    return _part->bodyBackgroundColor();
}

- (NSColor *)selectionColor
{
    RenderCanvas* root = static_cast<khtml::RenderCanvas *>(_part->xmlDocImpl()->renderer());
    if (root) {
        RenderStyle *pseudoStyle = root->getPseudoStyle(RenderStyle::SELECTION);
        if (pseudoStyle && pseudoStyle->backgroundColor().isValid()) {
            return nsColor(pseudoStyle->backgroundColor());
        }
    }
    return _part->displaysWithFocusAttributes() ? [NSColor selectedTextBackgroundColor] : [NSColor secondarySelectedControlColor];
}

- (void)adjustViewSize
{
    KHTMLView *view = _part->view();
    if (view)
        view->adjustViewSize();
}

-(id)accessibilityTree
{
    KWQAccObjectCache::enableAccessibility();
    if (!_part || !_part->xmlDocImpl()) return nil;
    RenderCanvas* root = static_cast<khtml::RenderCanvas *>(_part->xmlDocImpl()->renderer());
    if (!root) return nil;
    return _part->xmlDocImpl()->getAccObjectCache()->accObject(root);
}

- (void)setDrawsBackground:(BOOL)drawsBackground
{
    if (_part && _part->view())
        _part->view()->setTransparent(!drawsBackground);
}

- (void)undoEditing:(id)arg
{
    ASSERT([arg isKindOfClass:[KWQEditCommand class]]);
    [arg command]->unapply();
}

- (void)redoEditing:(id)arg
{
    ASSERT([arg isKindOfClass:[KWQEditCommand class]]);
    [arg command]->reapply();
}

- (DOMRange *)rangeByExpandingSelectionWithGranularity:(WebBridgeSelectionGranularity)granularity
{
    if (!partHasSelection(self))
        return nil;
        
    // NOTE: The enums *must* match the very similar ones declared in SelectionController.h
    SelectionController selection(_part->selection());
    selection.expandUsingGranularity(static_cast<ETextGranularity>(granularity));
    return [DOMRange _rangeWithImpl:selection.toRange().get()];
}

- (DOMRange *)rangeByAlteringCurrentSelection:(WebSelectionAlteration)alteration direction:(WebBridgeSelectionDirection)direction granularity:(WebBridgeSelectionGranularity)granularity
{
    if (!partHasSelection(self))
        return nil;
        
    // NOTE: The enums *must* match the very similar ones declared in SelectionController.h
    SelectionController selection(_part->selection());
    selection.modify(static_cast<SelectionController::EAlter>(alteration), 
                     static_cast<SelectionController::EDirection>(direction), 
                     static_cast<ETextGranularity>(granularity));
    return [DOMRange _rangeWithImpl:selection.toRange().get()];
}

- (void)alterCurrentSelection:(WebSelectionAlteration)alteration direction:(WebBridgeSelectionDirection)direction granularity:(WebBridgeSelectionGranularity)granularity
{
    if (!partHasSelection(self))
        return;
        
    // NOTE: The enums *must* match the very similar ones declared in SelectionController.h
    SelectionController selection(_part->selection());
    selection.modify(static_cast<SelectionController::EAlter>(alteration), 
                     static_cast<SelectionController::EDirection>(direction), 
                     static_cast<ETextGranularity>(granularity));

    // save vertical navigation x position if necessary; many types of motion blow it away
    int xPos = KHTMLPart::NoXPosForVerticalArrowNavigation;
    switch (granularity) {
        case WebBridgeSelectByLine:
        case WebBridgeSelectByParagraph:
            xPos = _part->xPosForVerticalArrowNavigation();
            break;
        case WebBridgeSelectByCharacter:
        case WebBridgeSelectByWord:
        case WebBridgeSelectToLineBoundary:
        case WebBridgeSelectToParagraphBoundary:
        case WebBridgeSelectToDocumentBoundary:
            break;
    }

    
    // setting the selection always clears saved vertical navigation x position
    _part->setSelection(selection);
    
    // altering the selection also sets the granularity back to character
    // NOTE: The one exception is that we need to keep word granularity
    // to preserve smart delete behavior when extending by word.  e.g. double-click,
    // then shift-option-rightarrow, then delete needs to smart delete, per TextEdit.
    if (!((alteration == WebSelectByExtending) &&
          (granularity == WebBridgeSelectByWord) && (_part->selectionGranularity() == khtml::WORD)))
        _part->setSelectionGranularity(static_cast<ETextGranularity>(WebBridgeSelectByCharacter));
    
    // restore vertical navigation x position if necessary
    if (xPos != KHTMLPart::NoXPosForVerticalArrowNavigation)
        _part->setXPosForVerticalArrowNavigation(xPos);

    _part->selectFrameElementInParentIfFullySelected();

    [self ensureSelectionVisible];
}

- (DOMRange *)rangeByAlteringCurrentSelection:(WebSelectionAlteration)alteration verticalDistance:(float)verticalDistance
{
    if (!partHasSelection(self))
        return nil;
        
    SelectionController selection(_part->selection());
    selection.modify(static_cast<SelectionController::EAlter>(alteration), static_cast<int>(verticalDistance));
    return [DOMRange _rangeWithImpl:selection.toRange().get()];
}

- (void)alterCurrentSelection:(WebSelectionAlteration)alteration verticalDistance:(float)verticalDistance
{
    if (!partHasSelection(self))
        return;
        
    SelectionController selection(_part->selection());
    selection.modify(static_cast<SelectionController::EAlter>(alteration), static_cast<int>(verticalDistance));

    // setting the selection always clears saved vertical navigation x position, so preserve it
    int xPos = _part->xPosForVerticalArrowNavigation();
    _part->setSelection(selection);
    _part->setSelectionGranularity(static_cast<ETextGranularity>(WebBridgeSelectByCharacter));
    _part->setXPosForVerticalArrowNavigation(xPos);

    _part->selectFrameElementInParentIfFullySelected();

    [self ensureSelectionVisible];
}

- (WebBridgeSelectionGranularity)selectionGranularity
{
    // NOTE: The enums *must* match the very similar ones declared in SelectionController.h
    return static_cast<WebBridgeSelectionGranularity>(_part->selectionGranularity());
}

- (void)setSelectedDOMRange:(DOMRange *)range affinity:(NSSelectionAffinity)selectionAffinity closeTyping:(BOOL)closeTyping
{
    NodeImpl *startContainer = [[range startContainer] _nodeImpl];
    NodeImpl *endContainer = [[range endContainer] _nodeImpl];
    ASSERT(startContainer);
    ASSERT(endContainer);
    ASSERT(startContainer->getDocument());
    ASSERT(startContainer->getDocument() == endContainer->getDocument());
    
    _part->xmlDocImpl()->updateLayoutIgnorePendingStylesheets();

    EAffinity affinity = static_cast<EAffinity>(selectionAffinity);
    
    // Non-collapsed ranges are not allowed to start at the end of a line that is wrapped,
    // they start at the beginning of the next line instead
    if (![range collapsed])
        affinity = DOWNSTREAM;
    
    // FIXME: Can we provide extentAffinity?
    VisiblePosition visibleStart(startContainer, [range startOffset], affinity);
    VisiblePosition visibleEnd(endContainer, [range endOffset], khtml::SEL_DEFAULT_AFFINITY);
    SelectionController selection(visibleStart, visibleEnd);
    _part->setSelection(selection, closeTyping);
}

- (DOMRange *)selectedDOMRange
{
    return [DOMRange _rangeWithImpl:_part->selection().toRange().get()];
}

- (NSRange)convertToNSRange:(DOM::RangeImpl *)range
{
    if (!range || range->isDetached()) {
        return NSMakeRange(NSNotFound, 0);
    }

    RefPtr<RangeImpl> fromStartRange(_part->xmlDocImpl()->createRange());
    int exception = 0;

    fromStartRange->setEnd(range->startContainer(exception), range->startOffset(exception), exception);
    int startPosition = TextIterator::rangeLength(fromStartRange.get());

    fromStartRange->setEnd(range->endContainer(exception), range->endOffset(exception), exception);
    int endPosition = TextIterator::rangeLength(fromStartRange.get());

    return NSMakeRange(startPosition, endPosition - startPosition);
}

- (RangeImpl *)convertToDOMRange:(NSRange)nsrange
{
    if (nsrange.location > INT_MAX)
        return 0;
    if (nsrange.length > INT_MAX || nsrange.location + nsrange.length > INT_MAX)
        nsrange.length = INT_MAX - nsrange.location;

    return TextIterator::rangeFromLocationAndLength(_part->xmlDocImpl(), nsrange.location, nsrange.length);
}

- (DOMRange *)convertNSRangeToDOMRange:(NSRange)nsrange
{
    return [DOMRange _rangeWithImpl:[self convertToDOMRange:nsrange]];
}

- (NSRange)convertDOMRangeToNSRange:(DOMRange *)range
{
    return [self convertToNSRange:[range _rangeImpl]];
}

- (void)selectNSRange:(NSRange)range
{
    _part->setSelection(SelectionController([self convertToDOMRange:range], khtml::SEL_DEFAULT_AFFINITY, khtml::SEL_DEFAULT_AFFINITY));
}

- (NSRange)selectedNSRange
{
    return [self convertToNSRange:_part->selection().toRange().get()];
}

- (NSSelectionAffinity)selectionAffinity
{
    return static_cast<NSSelectionAffinity>(_part->selection().startAffinity());
}

- (void)setMarkDOMRange:(DOMRange *)range
{
    _part->setMark(SelectionController([range _rangeImpl], khtml::SEL_DEFAULT_AFFINITY, khtml::SEL_DEFAULT_AFFINITY));
}

- (DOMRange *)markDOMRange
{
    return [DOMRange _rangeWithImpl:_part->mark().toRange().get()];
}

- (void)setMarkedTextDOMRange:(DOMRange *)range customAttributes:(NSArray *)attributes ranges:(NSArray *)ranges
{
    _part->setMarkedTextRange([range _rangeImpl], attributes, ranges);
}

- (DOMRange *)markedTextDOMRange
{
    return [DOMRange _rangeWithImpl:_part->markedTextRange()];
}

- (NSRange)markedTextNSRange
{
    return [self convertToNSRange:_part->markedTextRange()];
}

- (void)replaceMarkedTextWithText:(NSString *)text
{
    if (!partHasSelection(self))
        return;
    
    int exception = 0;

    RangeImpl *markedTextRange = _part->markedTextRange();
    if (markedTextRange && !markedTextRange->collapsed(exception))
        TypingCommand::deleteKeyPressed(_part->xmlDocImpl(), NO);
    
    if ([text length] > 0)
        TypingCommand::insertText(_part->xmlDocImpl(), text, YES);
    
    [self ensureSelectionVisible];
}

- (BOOL)canDeleteRange:(DOMRange *)range
{
    NodeImpl *startContainer = [[range startContainer] _nodeImpl];
    NodeImpl *endContainer = [[range endContainer] _nodeImpl];
    if (startContainer == nil || endContainer == nil)
        return NO;
    
    if (!startContainer->isContentEditable() || !endContainer->isContentEditable())
        return NO;
    
    if ([range collapsed]) {
        VisiblePosition start(startContainer, [range startOffset], DOWNSTREAM);
        if (isStartOfEditableContent(start))
            return NO;
    }
    
    return YES;
}

// Given proposedRange, returns an extended range that includes adjacent whitespace that should
// be deleted along with the proposed range in order to preserve proper spacing and punctuation of
// the text surrounding the deletion.
- (DOMRange *)smartDeleteRangeForProposedRange:(DOMRange *)proposedRange
{
    NodeImpl *startContainer = [[proposedRange startContainer] _nodeImpl];
    NodeImpl *endContainer = [[proposedRange endContainer] _nodeImpl];
    if (startContainer == nil || endContainer == nil)
        return nil;

    ASSERT(startContainer->getDocument());
    ASSERT(startContainer->getDocument() == endContainer->getDocument());
    
    _part->xmlDocImpl()->updateLayoutIgnorePendingStylesheets();

    Position start(startContainer, [proposedRange startOffset]);
    Position end(endContainer, [proposedRange endOffset]);
    Position newStart = start.upstream().leadingWhitespacePosition(khtml::DOWNSTREAM, true);
    if (newStart.isNull())
        newStart = start;
    Position newEnd = end.downstream().trailingWhitespacePosition(khtml::DOWNSTREAM, true);
    if (newEnd.isNull())
        newEnd = end;

    RangeImpl *range = _part->xmlDocImpl()->createRange();
    int exception = 0;
    range->setStart(newStart.node(), newStart.offset(), exception);
    range->setEnd(newStart.node(), newStart.offset(), exception);
    return [DOMRange _rangeWithImpl:range];
}

// Determines whether whitespace needs to be added around aString to preserve proper spacing and
// punctuation when it’s inserted into the receiver’s text over charRange. Returns by reference
// in beforeString and afterString any whitespace that should be added, unless either or both are
// nil. Both are returned as nil if aString is nil or if smart insertion and deletion are disabled.
- (void)smartInsertForString:(NSString *)pasteString replacingRange:(DOMRange *)rangeToReplace beforeString:(NSString **)beforeString afterString:(NSString **)afterString
{
    // give back nil pointers in case of early returns
    if (beforeString)
        *beforeString = nil;
    if (afterString)
        *afterString = nil;
        
    // inspect destination
    NodeImpl *startContainer = [[rangeToReplace startContainer] _nodeImpl];
    NodeImpl *endContainer = [[rangeToReplace endContainer] _nodeImpl];

    Position startPos(startContainer, [rangeToReplace startOffset]);
    Position endPos(endContainer, [rangeToReplace endOffset]);

    VisiblePosition startVisiblePos = VisiblePosition(startPos, khtml::VP_DEFAULT_AFFINITY);
    VisiblePosition endVisiblePos = VisiblePosition(endPos, khtml::VP_DEFAULT_AFFINITY);
    
    // this check also ensures startContainer, startPos, endContainer, and endPos are non-null
    if (startVisiblePos.isNull() || endVisiblePos.isNull())
        return;

    bool addLeadingSpace = startPos.leadingWhitespacePosition(khtml::VP_DEFAULT_AFFINITY, true).isNull() && !isStartOfParagraph(startVisiblePos);
    if (addLeadingSpace) {
        QChar previousChar = startVisiblePos.previous().character();
        if (!previousChar.isNull()) {
            addLeadingSpace = !_part->isCharacterSmartReplaceExempt(previousChar, true);
        }
    }
    
    bool addTrailingSpace = endPos.trailingWhitespacePosition(khtml::VP_DEFAULT_AFFINITY, true).isNull() && !isEndOfParagraph(endVisiblePos);
    if (addTrailingSpace) {
        QChar thisChar = endVisiblePos.character();
        if (!thisChar.isNull()) {
            addTrailingSpace = !_part->isCharacterSmartReplaceExempt(thisChar, false);
        }
    }
    
    // inspect source
    bool hasWhitespaceAtStart = false;
    bool hasWhitespaceAtEnd = false;
    unsigned pasteLength = [pasteString length];
    if (pasteLength > 0) {
        NSCharacterSet *whiteSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        
        if ([whiteSet characterIsMember:[pasteString characterAtIndex:0]]) {
            hasWhitespaceAtStart = YES;
        }
        if ([whiteSet characterIsMember:[pasteString characterAtIndex:(pasteLength - 1)]]) {
            hasWhitespaceAtEnd = YES;
        }
    }
    
    // issue the verdict
    if (beforeString && addLeadingSpace && !hasWhitespaceAtStart)
        *beforeString = @" ";
    if (afterString && addTrailingSpace && !hasWhitespaceAtEnd)
        *afterString = @" ";
}

- (DOMDocumentFragment *)documentFragmentWithMarkupString:(NSString *)markupString baseURLString:(NSString *)baseURLString 
{
    if (!_part || !_part->xmlDocImpl())
        return 0;

    PassRefPtr<DocumentFragmentImpl> fragment = createFragmentFromMarkup(_part->xmlDocImpl(), QString::fromNSString(markupString), QString::fromNSString(baseURLString));
    return [DOMDocumentFragment _documentFragmentWithImpl:fragment.get()];
}

- (DOMDocumentFragment *)documentFragmentWithText:(NSString *)text
{
    if (!partHasSelection(self) || !text)
        return 0;
    
    return [DOMDocumentFragment _documentFragmentWithImpl:createFragmentFromText(_part->xmlDocImpl(), QString::fromNSString(text)).get()];
}

- (DOMDocumentFragment *)documentFragmentWithNodesAsParagraphs:(NSArray *)nodes
{
    NSEnumerator *nodeEnum = [nodes objectEnumerator];
    DOMNode *node;
    QPtrList<DOM::NodeImpl> nodeList;
    
    if (!_part || !_part->xmlDocImpl())
        return 0;
    
    while ((node = [nodeEnum nextObject])) {
        nodeList.append([node _nodeImpl]);
    }
    
    return [DOMDocumentFragment _documentFragmentWithImpl:createFragmentFromNodeList(_part->xmlDocImpl(), nodeList).get()];
}

- (void)replaceSelectionWithFragment:(DOMDocumentFragment *)fragment selectReplacement:(BOOL)selectReplacement smartReplace:(BOOL)smartReplace matchStyle:(BOOL)matchStyle
{
    if (!partHasSelection(self) || !fragment)
        return;
    
    EditCommandPtr(new ReplaceSelectionCommand(_part->xmlDocImpl(), [fragment _fragmentImpl], selectReplacement, smartReplace, matchStyle)).apply();
    [self ensureSelectionVisible];
}

- (void)replaceSelectionWithNode:(DOMNode *)node selectReplacement:(BOOL)selectReplacement smartReplace:(BOOL)smartReplace
{
    DOMDocumentFragment *fragment = [[self DOMDocument] createDocumentFragment];
    [fragment appendChild:node];
    [self replaceSelectionWithFragment:fragment selectReplacement:selectReplacement smartReplace:smartReplace matchStyle:NO];
}

- (void)replaceSelectionWithMarkupString:(NSString *)markupString baseURLString:(NSString *)baseURLString selectReplacement:(BOOL)selectReplacement smartReplace:(BOOL)smartReplace
{
    DOMDocumentFragment *fragment = [self documentFragmentWithMarkupString:markupString baseURLString:baseURLString];
    [self replaceSelectionWithFragment:fragment selectReplacement:selectReplacement smartReplace:smartReplace matchStyle:NO];
}

- (void)replaceSelectionWithText:(NSString *)text selectReplacement:(BOOL)selectReplacement smartReplace:(BOOL)smartReplace
{
    [self replaceSelectionWithFragment:[self documentFragmentWithText:text] selectReplacement:selectReplacement smartReplace:smartReplace matchStyle:YES];
}

- (void)insertLineBreak
{
    if (!partHasSelection(self))
        return;
    
    TypingCommand::insertLineBreak(_part->xmlDocImpl());
    [self ensureSelectionVisible];
}

- (void)insertParagraphSeparator
{
    if (!partHasSelection(self))
        return;
    
    TypingCommand::insertParagraphSeparator(_part->xmlDocImpl());
    [self ensureSelectionVisible];
}

- (void)insertParagraphSeparatorInQuotedContent
{
    if (!partHasSelection(self))
        return;
    
    TypingCommand::insertParagraphSeparatorInQuotedContent(_part->xmlDocImpl());
    [self ensureSelectionVisible];
}

- (void)insertText:(NSString *)text selectInsertedText:(BOOL)selectInsertedText
{
    if (!partHasSelection(self))
        return;
    
    TypingCommand::insertText(_part->xmlDocImpl(), text, selectInsertedText);
    [self ensureSelectionVisible];
}

- (void)setSelectionToDragCaret
{
    _part->setSelection(_part->dragCaret());
}

- (void)moveSelectionToDragCaret:(DOMDocumentFragment *)selectionFragment smartMove:(BOOL)smartMove
{
    Position base = _part->dragCaret().base();
    EditCommandPtr(new MoveSelectionCommand(_part->xmlDocImpl(), [selectionFragment _fragmentImpl], base, smartMove)).apply();
}

- (VisiblePosition)_visiblePositionForPoint:(NSPoint)point
{
    RenderObject *renderer = _part->renderer();
    if (!renderer) {
        return VisiblePosition();
    }
    
    RenderObject::NodeInfo nodeInfo(true, true);
    renderer->layer()->hitTest(nodeInfo, (int)point.x, (int)point.y);
    NodeImpl *node = nodeInfo.innerNode();
    if (!node || !node->renderer())
        return VisiblePosition();
    
    return node->renderer()->positionForCoordinates((int)point.x, (int)point.y);
}

- (void)moveDragCaretToPoint:(NSPoint)point
{   
    SelectionController dragCaret([self _visiblePositionForPoint:point]);
    _part->setDragCaret(dragCaret);
}

- (void)removeDragCaret
{
    _part->setDragCaret(SelectionController());
}

- (DOMRange *)dragCaretDOMRange
{
    return [DOMRange _rangeWithImpl:_part->dragCaret().toRange().get()];
}

- (DOMRange *)editableDOMRangeForPoint:(NSPoint)point
{
    VisiblePosition position = [self _visiblePositionForPoint:point];
    return position.isNull() ? nil : [DOMRange _rangeWithImpl:SelectionController(position).toRange().get()];
}

- (DOMRange *)characterRangeAtPoint:(NSPoint)point
{
    VisiblePosition position = [self _visiblePositionForPoint:point];
    if (position.isNull())
        return nil;
    
    VisiblePosition previous = position.previous();
    if (previous.isNotNull()) {
        DOMRange *previousCharacterRange = [DOMRange _rangeWithImpl:makeRange(previous, position).get()];
        NSRect rect = [self firstRectForDOMRange:previousCharacterRange];
        if (NSPointInRect(point, rect))
            return previousCharacterRange;
    }

    VisiblePosition next = position.next();
    if (next.isNotNull()) {
        DOMRange *nextCharacterRange = [DOMRange _rangeWithImpl:makeRange(position, next).get()];
        NSRect rect = [self firstRectForDOMRange:nextCharacterRange];
        if (NSPointInRect(point, rect))
            return nextCharacterRange;
    }
    
    return nil;
}

- (void)deleteSelectionWithSmartDelete:(BOOL)smartDelete
{
    if (!partHasSelection(self))
        return;
    
    EditCommandPtr(new DeleteSelectionCommand(_part->xmlDocImpl(), smartDelete)).apply();
}

- (void)deleteKeyPressedWithSmartDelete:(BOOL)smartDelete
{
    if (!_part || !_part->xmlDocImpl())
        return;
    
    TypingCommand::deleteKeyPressed(_part->xmlDocImpl(), smartDelete);
    [self ensureSelectionVisible];
}

- (void)forwardDeleteKeyPressedWithSmartDelete:(BOOL)smartDelete
{
    if (!_part || !_part->xmlDocImpl())
        return;
    
    TypingCommand::forwardDeleteKeyPressed(_part->xmlDocImpl(), smartDelete);
    [self ensureSelectionVisible];
}

- (DOMCSSStyleDeclaration *)typingStyle
{
    if (!_part || !_part->typingStyle())
        return nil;
    return [DOMCSSStyleDeclaration _styleDeclarationWithImpl:_part->typingStyle()->copy()];
}

- (void)setTypingStyle:(DOMCSSStyleDeclaration *)style withUndoAction:(WebUndoAction)undoAction
{
    if (!_part)
        return;
    _part->computeAndSetTypingStyle([style _styleDeclarationImpl], static_cast<EditAction>(undoAction));
}

- (void)applyStyle:(DOMCSSStyleDeclaration *)style withUndoAction:(WebUndoAction)undoAction
{
    if (!_part)
        return;
    _part->applyStyle([style _styleDeclarationImpl], static_cast<EditAction>(undoAction));
}

- (void)applyParagraphStyle:(DOMCSSStyleDeclaration *)style withUndoAction:(WebUndoAction)undoAction
{
    if (!_part)
        return;
    _part->applyParagraphStyle([style _styleDeclarationImpl], static_cast<EditAction>(undoAction));
}

- (BOOL)selectionStartHasStyle:(DOMCSSStyleDeclaration *)style
{
    if (!_part)
        return NO;
    return _part->selectionStartHasStyle([style _styleDeclarationImpl]);
}

- (NSCellStateValue)selectionHasStyle:(DOMCSSStyleDeclaration *)style
{
    if (!_part)
        return NSOffState;
    switch (_part->selectionHasStyle([style _styleDeclarationImpl])) {
        case KHTMLPart::falseTriState:
            return NSOffState;
        case KHTMLPart::trueTriState:
            return NSOnState;
        case KHTMLPart::mixedTriState:
            return NSMixedState;
    }
    return NSOffState;
}

- (void)applyEditingStyleToBodyElement
{
    if (!_part)
        return;
    _part->applyEditingStyleToBodyElement();
}

- (void)removeEditingStyleFromBodyElement
{
    if (!_part)
        return;
    _part->removeEditingStyleFromBodyElement();
}

- (void)applyEditingStyleToElement:(DOMElement *)element
{
    if (!_part)
        return;
    _part->applyEditingStyleToElement([element _elementImpl]);
}

- (void)removeEditingStyleFromElement:(DOMElement *)element
{
    if (!_part)
        return;
    _part->removeEditingStyleFromElement([element _elementImpl]);
}

- (NSFont *)fontForSelection:(BOOL *)hasMultipleFonts
{
    bool multipleFonts = false;
    NSFont *font = nil;
    if (_part)
        font = _part->fontForSelection(hasMultipleFonts ? &multipleFonts : 0);
    if (hasMultipleFonts)
        *hasMultipleFonts = multipleFonts;
    return font;
}

- (NSDictionary *)fontAttributesForSelectionStart
{
    return _part ? _part->fontAttributesForSelectionStart() : nil;
}

- (NSWritingDirection)baseWritingDirectionForSelectionStart
{
    return _part ? _part->baseWritingDirectionForSelectionStart() : NSWritingDirectionLeftToRight;
}

- (void)ensureSelectionVisible
{
    if (!partHasSelection(self))
        return;
    
    KHTMLView *v = _part->view();
    if (!v)
        return;

    Position extent = _part->selection().extent();
    if (extent.isNull())
        return;
    
    RenderObject *renderer = extent.node()->renderer();
    if (!renderer)
        return;
    
    NSView *documentView = v->getDocumentView();
    if (!documentView)
        return;
    
    QRect extentRect = renderer->caretRect(extent.offset(), _part->selection().extentAffinity());
    RenderLayer *layer = renderer->enclosingLayer();
    if (layer)
        layer->scrollRectToVisible(extentRect);
}

// [info draggingLocation] is in window coords

- (BOOL)eventMayStartDrag:(NSEvent *)event
{
    return _part ? _part->eventMayStartDrag(event) : NO;
}

- (NSDragOperation)dragOperationForDraggingInfo:(id <NSDraggingInfo>)info
{
    NSDragOperation op = NSDragOperationNone;
    if (_part) {
        KHTMLView *v = _part->view();
        if (v) {
            // Sending an event can result in the destruction of the view and part.
            v->ref();
            
            KWQClipboard::AccessPolicy policy = _part->baseURL().isLocalFile() ? KWQClipboard::Readable : KWQClipboard::TypesReadable;
            KWQClipboard *clipboard = new KWQClipboard(true, [info draggingPasteboard], policy);
            clipboard->ref();
            NSDragOperation srcOp = [info draggingSourceOperationMask];
            clipboard->setSourceOperation(srcOp);

            if (v->updateDragAndDrop(QPoint([info draggingLocation]), clipboard)) {
                // *op unchanged if no source op was set
                if (!clipboard->destinationOperation(&op)) {
                    // The element accepted but they didn't pick an operation, so we pick one for them
                    // (as does WinIE).
                    if (srcOp & NSDragOperationCopy) {
                        op = NSDragOperationCopy;
                    } else if (srcOp & NSDragOperationMove || srcOp & NSDragOperationGeneric) {
                        op = NSDragOperationMove;
                    } else if (srcOp & NSDragOperationLink) {
                        op = NSDragOperationLink;
                    } else {
                        op = NSDragOperationGeneric;
                    }
                } else if (!(op & srcOp)) {
                    // make sure WC picked an op that was offered.  Cocoa doesn't seem to enforce this,
                    // but IE does.
                    op = NSDragOperationNone;
                }
            }
            clipboard->setAccessPolicy(KWQClipboard::Numb);    // invalidate clipboard here for security

            clipboard->deref();
            v->deref();
            return op;
        }
    }
    return op;
}

- (void)dragExitedWithDraggingInfo:(id <NSDraggingInfo>)info
{
    if (_part) {
        KHTMLView *v = _part->view();
        if (v) {
            // Sending an event can result in the destruction of the view and part.
            v->ref();

            KWQClipboard::AccessPolicy policy = _part->baseURL().isLocalFile() ? KWQClipboard::Readable : KWQClipboard::TypesReadable;
            KWQClipboard *clipboard = new KWQClipboard(true, [info draggingPasteboard], policy);
            clipboard->ref();
            clipboard->setSourceOperation([info draggingSourceOperationMask]);
            
            v->cancelDragAndDrop(QPoint([info draggingLocation]), clipboard);
            clipboard->setAccessPolicy(KWQClipboard::Numb);    // invalidate clipboard here for security

            clipboard->deref();
            v->deref();
        }
    }
}

- (BOOL)concludeDragForDraggingInfo:(id <NSDraggingInfo>)info
{
    if (_part) {
        KHTMLView *v = _part->view();
        if (v) {
            // Sending an event can result in the destruction of the view and part.
            v->ref();

            KWQClipboard *clipboard = new KWQClipboard(true, [info draggingPasteboard], KWQClipboard::Readable);
            clipboard->ref();
            clipboard->setSourceOperation([info draggingSourceOperationMask]);

            BOOL result = v->performDragAndDrop(QPoint([info draggingLocation]), clipboard);
            clipboard->setAccessPolicy(KWQClipboard::Numb);    // invalidate clipboard here for security

            clipboard->deref();
            v->deref();

            return result;
        }
    }
    return NO;
}

- (void)dragSourceMovedTo:(NSPoint)windowLoc
{
    if (_part) {
        _part->dragSourceMovedTo(QPoint(windowLoc));
    }
}

- (void)dragSourceEndedAt:(NSPoint)windowLoc operation:(NSDragOperation)operation
{
    if (_part) {
        _part->dragSourceEndedAt(QPoint(windowLoc), operation);
    }
}

- (BOOL)mayDHTMLCut
{
    return _part->mayCut();
}

- (BOOL)mayDHTMLCopy
{
    return _part->mayCopy();
}

- (BOOL)mayDHTMLPaste
{
    return _part->mayPaste();
}

- (BOOL)tryDHTMLCut
{
    return _part->tryCut();
}

- (BOOL)tryDHTMLCopy
{
    return _part->tryCopy();
}

- (BOOL)tryDHTMLPaste
{
    return _part->tryPaste();
}

- (DOMRange *)rangeOfCharactersAroundCaret
{
    if (!_part)
        return nil;
        
    SelectionController selection(_part->selection());
    if (!selection.isCaret())
        return nil;

    VisiblePosition caret(selection.start(), selection.startAffinity());
    VisiblePosition next = caret.next();
    VisiblePosition previous = caret.previous();
    if (previous.isNull() || next.isNull() || caret == next || caret == previous)
        return nil;

    return [DOMRange _rangeWithImpl:makeRange(previous, next).get()];
}

- (NSMutableDictionary *)dashboardRegions
{
    return _part->dashboardRegionsDictionary();
}

@end

@implementation WebCoreBridge (WebCoreBridgeInternal)

- (RootObject *)executionContextForView:(NSView *)aView
{
    KWQKHTMLPart *part = [self part];
    RootObject *root = new RootObject(aView);    // The root gets deleted by JavaScriptCore.
    root->setRootObjectImp(Window::retrieveWindow(part));
    root->setInterpreter(part->jScript()->interpreter());
    part->addPluginRootObject(root);
    return root;
}

@end
