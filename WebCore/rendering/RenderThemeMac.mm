/*
 * Copyright (C) 2005, 2006, 2007, 2008, 2009 Apple Inc. All rights reserved.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this library; see the file COPYING.LIB.  If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 */

#import "config.h"
#import "RenderThemeMac.h"

#import "BitmapImage.h"
#import "ColorMac.h"
#import "CSSStyleSelector.h"
#import "CSSValueKeywords.h"
#import "Document.h"
#import "Element.h"
#import "FrameView.h"
#import "GraphicsContext.h"
#import "HTMLInputElement.h"
#import "HTMLMediaElement.h"
#import "HTMLNames.h"
#import "Image.h"
#import "ImageBuffer.h"
#import "LocalCurrentGraphicsContext.h"
#import "MediaControlElements.h"
#import "RenderMedia.h"
#import "RenderSlider.h"
#import "RenderView.h"
#import "SharedBuffer.h"
#import "TimeRanges.h"
#import "ThemeMac.h"
#import "WebCoreSystemInterface.h"
#import "UserAgentStyleSheets.h"
#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#import <wtf/RetainPtr.h>
#import <wtf/StdLibExtras.h>
#import <math.h>

#import "RenderProgress.h"

#ifdef BUILDING_ON_TIGER
typedef int NSInteger;
typedef unsigned NSUInteger;
#endif

using namespace std;

// The methods in this file are specific to the Mac OS X platform.

// FIXME: The platform-independent code in this class should be factored out and merged with RenderThemeSafari. 

// We estimate the animation rate of a Mac OS X progress bar is 33 fps.
// Hard code the value here because we haven't found API for it.
const double progressAnimationFrameRate = 0.033;

// Mac OS X progress bar animation seems to have 256 frames.
const double progressAnimationNumFrames = 256;

@interface WebCoreRenderThemeNotificationObserver : NSObject
{
    WebCore::RenderTheme *_theme;
}

- (id)initWithTheme:(WebCore::RenderTheme *)theme;
- (void)systemColorsDidChange:(NSNotification *)notification;

@end

@implementation WebCoreRenderThemeNotificationObserver

- (id)initWithTheme:(WebCore::RenderTheme *)theme
{
    [super init];
    _theme = theme;
    
    return self;
}

- (void)systemColorsDidChange:(NSNotification *)unusedNotification
{
    ASSERT_UNUSED(unusedNotification, [[unusedNotification name] isEqualToString:NSSystemColorsDidChangeNotification]);
    _theme->platformColorsDidChange();
}

@end

namespace WebCore {

using namespace HTMLNames;

enum {
    topMargin,
    rightMargin,
    bottomMargin,
    leftMargin
};

enum {
    topPadding,
    rightPadding,
    bottomPadding,
    leftPadding
};

PassRefPtr<RenderTheme> RenderTheme::themeForPage(Page*)
{
    static RenderTheme* rt = RenderThemeMac::create().releaseRef();
    return rt;
}

PassRefPtr<RenderTheme> RenderThemeMac::create()
{
    return adoptRef(new RenderThemeMac);
}

RenderThemeMac::RenderThemeMac()
    : m_isSliderThumbHorizontalPressed(false)
    , m_isSliderThumbVerticalPressed(false)
    , m_notificationObserver(AdoptNS, [[WebCoreRenderThemeNotificationObserver alloc] initWithTheme:this])
{
    [[NSNotificationCenter defaultCenter] addObserver:m_notificationObserver.get()
                                                        selector:@selector(systemColorsDidChange:)
                                                            name:NSSystemColorsDidChangeNotification
                                                          object:nil];
}

RenderThemeMac::~RenderThemeMac()
{
    [[NSNotificationCenter defaultCenter] removeObserver:m_notificationObserver.get()];
}

Color RenderThemeMac::platformActiveSelectionBackgroundColor() const
{
    NSColor* color = [[NSColor selectedTextBackgroundColor] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    return Color(static_cast<int>(255.0 * [color redComponent]), static_cast<int>(255.0 * [color greenComponent]), static_cast<int>(255.0 * [color blueComponent]));
}

Color RenderThemeMac::platformInactiveSelectionBackgroundColor() const
{
    NSColor* color = [[NSColor secondarySelectedControlColor] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    return Color(static_cast<int>(255.0 * [color redComponent]), static_cast<int>(255.0 * [color greenComponent]), static_cast<int>(255.0 * [color blueComponent]));
}

Color RenderThemeMac::platformActiveListBoxSelectionBackgroundColor() const
{
    NSColor* color = [[NSColor alternateSelectedControlColor] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    return Color(static_cast<int>(255.0 * [color redComponent]), static_cast<int>(255.0 * [color greenComponent]), static_cast<int>(255.0 * [color blueComponent]));
}

Color RenderThemeMac::platformActiveListBoxSelectionForegroundColor() const
{
    return Color::white;
}

Color RenderThemeMac::platformInactiveListBoxSelectionForegroundColor() const
{
    return Color::black;
}

Color RenderThemeMac::platformFocusRingColor() const
{
    if (usesTestModeFocusRingColor())
        return oldAquaFocusRingColor();

    return systemColor(CSSValueWebkitFocusRingColor);
}

Color RenderThemeMac::platformInactiveListBoxSelectionBackgroundColor() const
{
    return platformInactiveSelectionBackgroundColor();
}

static FontWeight toFontWeight(NSInteger appKitFontWeight)
{
    ASSERT(appKitFontWeight > 0 && appKitFontWeight < 15);
    if (appKitFontWeight > 14)
        appKitFontWeight = 14;
    else if (appKitFontWeight < 1)
        appKitFontWeight = 1;

    static FontWeight fontWeights[] = {
        FontWeight100,
        FontWeight100,
        FontWeight200,
        FontWeight300,
        FontWeight400,
        FontWeight500,
        FontWeight600,
        FontWeight600,
        FontWeight700,
        FontWeight800,
        FontWeight800,
        FontWeight900,
        FontWeight900,
        FontWeight900
    };
    return fontWeights[appKitFontWeight - 1];
}

void RenderThemeMac::systemFont(int cssValueId, FontDescription& fontDescription) const
{
    DEFINE_STATIC_LOCAL(FontDescription, systemFont, ());
    DEFINE_STATIC_LOCAL(FontDescription, smallSystemFont, ());
    DEFINE_STATIC_LOCAL(FontDescription, menuFont, ());
    DEFINE_STATIC_LOCAL(FontDescription, labelFont, ());
    DEFINE_STATIC_LOCAL(FontDescription, miniControlFont, ());
    DEFINE_STATIC_LOCAL(FontDescription, smallControlFont, ());
    DEFINE_STATIC_LOCAL(FontDescription, controlFont, ());

    FontDescription* cachedDesc;
    NSFont* font = nil;
    switch (cssValueId) {
        case CSSValueSmallCaption:
            cachedDesc = &smallSystemFont;
            if (!smallSystemFont.isAbsoluteSize())
                font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
            break;
        case CSSValueMenu:
            cachedDesc = &menuFont;
            if (!menuFont.isAbsoluteSize())
                font = [NSFont menuFontOfSize:[NSFont systemFontSize]];
            break;
        case CSSValueStatusBar:
            cachedDesc = &labelFont;
            if (!labelFont.isAbsoluteSize())
                font = [NSFont labelFontOfSize:[NSFont labelFontSize]];
            break;
        case CSSValueWebkitMiniControl:
            cachedDesc = &miniControlFont;
            if (!miniControlFont.isAbsoluteSize())
                font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSMiniControlSize]];
            break;
        case CSSValueWebkitSmallControl:
            cachedDesc = &smallControlFont;
            if (!smallControlFont.isAbsoluteSize())
                font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]];
            break;
        case CSSValueWebkitControl:
            cachedDesc = &controlFont;
            if (!controlFont.isAbsoluteSize())
                font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSRegularControlSize]];
            break;
        default:
            cachedDesc = &systemFont;
            if (!systemFont.isAbsoluteSize())
                font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }

    if (font) {
        NSFontManager *fontManager = [NSFontManager sharedFontManager];
        cachedDesc->setIsAbsoluteSize(true);
        cachedDesc->setGenericFamily(FontDescription::NoFamily);
        cachedDesc->firstFamily().setFamily([font familyName]);
        cachedDesc->setSpecifiedSize([font pointSize]);
        cachedDesc->setWeight(toFontWeight([fontManager weightOfFont:font]));
        cachedDesc->setItalic([fontManager traitsOfFont:font] & NSItalicFontMask);
    }
    fontDescription = *cachedDesc;
}

static RGBA32 convertNSColorToColor(NSColor *color)
{
    NSColor *colorInColorSpace = [color colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    if (colorInColorSpace) {
        static const double scaleFactor = nextafter(256.0, 0.0);
        return makeRGB(static_cast<int>(scaleFactor * [colorInColorSpace redComponent]),
            static_cast<int>(scaleFactor * [colorInColorSpace greenComponent]),
            static_cast<int>(scaleFactor * [colorInColorSpace blueComponent]));
    }

    // This conversion above can fail if the NSColor in question is an NSPatternColor 
    // (as many system colors are). These colors are actually a repeating pattern
    // not just a solid color. To work around this we simply draw a 1x1 image of
    // the color and use that pixel's color. It might be better to use an average of
    // the colors in the pattern instead.
    NSBitmapImageRep *offscreenRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil
                                                                             pixelsWide:1
                                                                             pixelsHigh:1
                                                                          bitsPerSample:8
                                                                        samplesPerPixel:4
                                                                               hasAlpha:YES
                                                                               isPlanar:NO
                                                                         colorSpaceName:NSDeviceRGBColorSpace
                                                                            bytesPerRow:4
                                                                           bitsPerPixel:32];

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:offscreenRep]];
    NSEraseRect(NSMakeRect(0, 0, 1, 1));
    [color drawSwatchInRect:NSMakeRect(0, 0, 1, 1)];
    [NSGraphicsContext restoreGraphicsState];

    NSUInteger pixel[4];
    [offscreenRep getPixel:pixel atX:0 y:0];

    [offscreenRep release];

    return makeRGB(pixel[0], pixel[1], pixel[2]);
}

static RGBA32 menuBackgroundColor()
{
    NSBitmapImageRep *offscreenRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil
                                                                             pixelsWide:1
                                                                             pixelsHigh:1
                                                                          bitsPerSample:8
                                                                        samplesPerPixel:4
                                                                               hasAlpha:YES
                                                                               isPlanar:NO
                                                                         colorSpaceName:NSDeviceRGBColorSpace
                                                                            bytesPerRow:4
                                                                           bitsPerPixel:32];

    CGContextRef context = static_cast<CGContextRef>([[NSGraphicsContext graphicsContextWithBitmapImageRep:offscreenRep] graphicsPort]);
    CGRect rect = CGRectMake(0, 0, 1, 1);
    HIThemeMenuDrawInfo drawInfo;
    drawInfo.version =  0;
    drawInfo.menuType = kThemeMenuTypePopUp;
    HIThemeDrawMenuBackground(&rect, &drawInfo, context, kHIThemeOrientationInverted);

    NSUInteger pixel[4];
    [offscreenRep getPixel:pixel atX:0 y:0];

    [offscreenRep release];

    return makeRGB(pixel[0], pixel[1], pixel[2]);
}

void RenderThemeMac::platformColorsDidChange()
{
    m_systemColorCache.clear();
    RenderTheme::platformColorsDidChange();
}

Color RenderThemeMac::systemColor(int cssValueId) const
{
    if (m_systemColorCache.contains(cssValueId))
        return m_systemColorCache.get(cssValueId);
    
    Color color;
    switch (cssValueId) {
        case CSSValueActiveborder:
            color = convertNSColorToColor([NSColor keyboardFocusIndicatorColor]);
            break;
        case CSSValueActivecaption:
            color = convertNSColorToColor([NSColor windowFrameTextColor]);
            break;
        case CSSValueAppworkspace:
            color = convertNSColorToColor([NSColor headerColor]);
            break;
        case CSSValueBackground:
            // Use theme independent default
            break;
        case CSSValueButtonface:
            // We use this value instead of NSColor's controlColor to avoid website incompatibilities.
            // We may want to change this to use the NSColor in future.
            color = 0xFFC0C0C0;
            break;
        case CSSValueButtonhighlight:
            color = convertNSColorToColor([NSColor controlHighlightColor]);
            break;
        case CSSValueButtonshadow:
            color = convertNSColorToColor([NSColor controlShadowColor]);
            break;
        case CSSValueButtontext:
            color = convertNSColorToColor([NSColor controlTextColor]);
            break;
        case CSSValueCaptiontext:
            color = convertNSColorToColor([NSColor textColor]);
            break;
        case CSSValueGraytext:
            color = convertNSColorToColor([NSColor disabledControlTextColor]);
            break;
        case CSSValueHighlight:
            color = convertNSColorToColor([NSColor selectedTextBackgroundColor]);
            break;
        case CSSValueHighlighttext:
            color = convertNSColorToColor([NSColor selectedTextColor]);
            break;
        case CSSValueInactiveborder:
            color = convertNSColorToColor([NSColor controlBackgroundColor]);
            break;
        case CSSValueInactivecaption:
            color = convertNSColorToColor([NSColor controlBackgroundColor]);
            break;
        case CSSValueInactivecaptiontext:
            color = convertNSColorToColor([NSColor textColor]);
            break;
        case CSSValueInfobackground:
            // There is no corresponding NSColor for this so we use a hard coded value.
            color = 0xFFFBFCC5;
            break;
        case CSSValueInfotext:
            color = convertNSColorToColor([NSColor textColor]);
            break;
        case CSSValueMenu:
            color = menuBackgroundColor();
            break;
        case CSSValueMenutext:
            color = convertNSColorToColor([NSColor selectedMenuItemTextColor]);
            break;
        case CSSValueScrollbar:
            color = convertNSColorToColor([NSColor scrollBarColor]);
            break;
        case CSSValueText:
            color = convertNSColorToColor([NSColor textColor]);
            break;
        case CSSValueThreeddarkshadow:
            color = convertNSColorToColor([NSColor controlDarkShadowColor]);
            break;
        case CSSValueThreedshadow:
            color = convertNSColorToColor([NSColor shadowColor]);
            break;
        case CSSValueThreedface:
            // We use this value instead of NSColor's controlColor to avoid website incompatibilities.
            // We may want to change this to use the NSColor in future.
            color = 0xFFC0C0C0;
            break;
        case CSSValueThreedhighlight:
            color = convertNSColorToColor([NSColor highlightColor]);
            break;
        case CSSValueThreedlightshadow:
            color = convertNSColorToColor([NSColor controlLightHighlightColor]);
            break;
        case CSSValueWebkitFocusRingColor:
            color = convertNSColorToColor([NSColor keyboardFocusIndicatorColor]);
            break;
        case CSSValueWindow:
            color = convertNSColorToColor([NSColor windowBackgroundColor]);
            break;
        case CSSValueWindowframe:
            color = convertNSColorToColor([NSColor windowFrameColor]);
            break;
        case CSSValueWindowtext:
            color = convertNSColorToColor([NSColor windowFrameTextColor]);
            break;
    }

    if (!color.isValid())
        color = RenderTheme::systemColor(cssValueId);

    if (color.isValid())
        m_systemColorCache.set(cssValueId, color.rgb());

    return color;
}

bool RenderThemeMac::isControlStyled(const RenderStyle* style, const BorderData& border,
                                     const FillLayer& background, const Color& backgroundColor) const
{
    if (style->appearance() == TextFieldPart || style->appearance() == TextAreaPart || style->appearance() == ListboxPart)
        return style->border() != border;
        
    // FIXME: This is horrible, but there is not much else that can be done.  Menu lists cannot draw properly when
    // scaled.  They can't really draw properly when transformed either.  We can't detect the transform case at style
    // adjustment time so that will just have to stay broken.  We can however detect that we're zooming.  If zooming
    // is in effect we treat it like the control is styled.
    if (style->appearance() == MenulistPart && style->effectiveZoom() != 1.0f)
        return true;

    return RenderTheme::isControlStyled(style, border, background, backgroundColor);
}

void RenderThemeMac::adjustRepaintRect(const RenderObject* o, IntRect& r)
{
    ControlPart part = o->style()->appearance();
    
#if USE(NEW_THEME)
    switch (part) {
        case CheckboxPart:
        case RadioPart:
        case PushButtonPart:
        case SquareButtonPart:
        case ListButtonPart:
        case DefaultButtonPart:
        case ButtonPart:
            return RenderTheme::adjustRepaintRect(o, r);
        default:
            break;
    }
#endif

    float zoomLevel = o->style()->effectiveZoom();

    if (part == MenulistPart) {
        setPopupButtonCellState(o, r);
        IntSize size = popupButtonSizes()[[popupButton() controlSize]];
        size.setHeight(size.height() * zoomLevel);
        size.setWidth(r.width());
        r = inflateRect(r, size, popupButtonMargins(), zoomLevel);
    }
}

IntRect RenderThemeMac::inflateRect(const IntRect& r, const IntSize& size, const int* margins, float zoomLevel) const
{
    // Only do the inflation if the available width/height are too small.  Otherwise try to
    // fit the glow/check space into the available box's width/height.
    int widthDelta = r.width() - (size.width() + margins[leftMargin] * zoomLevel + margins[rightMargin] * zoomLevel);
    int heightDelta = r.height() - (size.height() + margins[topMargin] * zoomLevel + margins[bottomMargin] * zoomLevel);
    IntRect result(r);
    if (widthDelta < 0) {
        result.setX(result.x() - margins[leftMargin] * zoomLevel);
        result.setWidth(result.width() - widthDelta);
    }
    if (heightDelta < 0) {
        result.setY(result.y() - margins[topMargin] * zoomLevel);
        result.setHeight(result.height() - heightDelta);
    }
    return result;
}

FloatRect RenderThemeMac::convertToPaintingRect(const RenderObject* inputRenderer, const RenderObject* partRenderer, const FloatRect& inputRect, const IntRect& r) const
{
    FloatRect partRect(inputRect);
    
    // Compute an offset between the part renderer and the input renderer
    FloatSize offsetFromInputRenderer;
    const RenderObject* renderer = partRenderer;
    while (renderer && renderer != inputRenderer) {
        RenderObject* containingRenderer = renderer->container();
        offsetFromInputRenderer -= renderer->offsetFromContainer(containingRenderer, IntPoint());
        renderer = containingRenderer;
    }
    // If the input renderer was not a container, something went wrong
    ASSERT(renderer == inputRenderer);
    // Move the rect into partRenderer's coords
    partRect.move(offsetFromInputRenderer);
    // Account for the local drawing offset (tx, ty)
    partRect.move(r.x(), r.y());

    return partRect;
}

void RenderThemeMac::updateCheckedState(NSCell* cell, const RenderObject* o)
{
    bool oldIndeterminate = [cell state] == NSMixedState;
    bool indeterminate = isIndeterminate(o);
    bool checked = isChecked(o);

    if (oldIndeterminate != indeterminate) {
        [cell setState:indeterminate ? NSMixedState : (checked ? NSOnState : NSOffState)];
        return;
    }

    bool oldChecked = [cell state] == NSOnState;
    if (checked != oldChecked)
        [cell setState:checked ? NSOnState : NSOffState];
}

void RenderThemeMac::updateEnabledState(NSCell* cell, const RenderObject* o)
{
    bool oldEnabled = [cell isEnabled];
    bool enabled = isEnabled(o);
    if (enabled != oldEnabled)
        [cell setEnabled:enabled];
}

void RenderThemeMac::updateFocusedState(NSCell* cell, const RenderObject* o)
{
    bool oldFocused = [cell showsFirstResponder];
    bool focused = isFocused(o) && o->style()->outlineStyleIsAuto();
    if (focused != oldFocused)
        [cell setShowsFirstResponder:focused];
}

void RenderThemeMac::updatePressedState(NSCell* cell, const RenderObject* o)
{
    bool oldPressed = [cell isHighlighted];
    bool pressed = (o->node() && o->node()->active());
    if (pressed != oldPressed)
        [cell setHighlighted:pressed];
}

bool RenderThemeMac::controlSupportsTints(const RenderObject* o) const
{
    // An alternate way to implement this would be to get the appropriate cell object
    // and call the private _needRedrawOnWindowChangedKeyState method. An advantage of
    // that would be that we would match AppKit behavior more closely, but a disadvantage
    // would be that we would rely on an AppKit SPI method.

    if (!isEnabled(o))
        return false;

    // Checkboxes only have tint when checked.
    if (o->style()->appearance() == CheckboxPart)
        return isChecked(o);

    // For now assume other controls have tint if enabled.
    return true;
}

NSControlSize RenderThemeMac::controlSizeForFont(RenderStyle* style) const
{
    int fontSize = style->fontSize();
    if (fontSize >= 16)
        return NSRegularControlSize;
    if (fontSize >= 11)
        return NSSmallControlSize;
    return NSMiniControlSize;
}

void RenderThemeMac::setControlSize(NSCell* cell, const IntSize* sizes, const IntSize& minSize, float zoomLevel)
{
    NSControlSize size;
    if (minSize.width() >= static_cast<int>(sizes[NSRegularControlSize].width() * zoomLevel) &&
        minSize.height() >= static_cast<int>(sizes[NSRegularControlSize].height() * zoomLevel))
        size = NSRegularControlSize;
    else if (minSize.width() >= static_cast<int>(sizes[NSSmallControlSize].width() * zoomLevel) &&
             minSize.height() >= static_cast<int>(sizes[NSSmallControlSize].height() * zoomLevel))
        size = NSSmallControlSize;
    else
        size = NSMiniControlSize;
    if (size != [cell controlSize]) // Only update if we have to, since AppKit does work even if the size is the same.
        [cell setControlSize:size];
}

IntSize RenderThemeMac::sizeForFont(RenderStyle* style, const IntSize* sizes) const
{
    if (style->effectiveZoom() != 1.0f) {
        IntSize result = sizes[controlSizeForFont(style)];
        return IntSize(result.width() * style->effectiveZoom(), result.height() * style->effectiveZoom());
    }
    return sizes[controlSizeForFont(style)];
}

IntSize RenderThemeMac::sizeForSystemFont(RenderStyle* style, const IntSize* sizes) const
{
    if (style->effectiveZoom() != 1.0f) {
        IntSize result = sizes[controlSizeForSystemFont(style)];
        return IntSize(result.width() * style->effectiveZoom(), result.height() * style->effectiveZoom());
    }
    return sizes[controlSizeForSystemFont(style)];
}

void RenderThemeMac::setSizeFromFont(RenderStyle* style, const IntSize* sizes) const
{
    // FIXME: Check is flawed, since it doesn't take min-width/max-width into account.
    IntSize size = sizeForFont(style, sizes);
    if (style->width().isIntrinsicOrAuto() && size.width() > 0)
        style->setWidth(Length(size.width(), Fixed));
    if (style->height().isAuto() && size.height() > 0)
        style->setHeight(Length(size.height(), Fixed));
}

void RenderThemeMac::setFontFromControlSize(CSSStyleSelector*, RenderStyle* style, NSControlSize controlSize) const
{
    FontDescription fontDescription;
    fontDescription.setIsAbsoluteSize(true);
    fontDescription.setGenericFamily(FontDescription::SerifFamily);

    NSFont* font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:controlSize]];
    fontDescription.firstFamily().setFamily([font familyName]);
    fontDescription.setComputedSize([font pointSize] * style->effectiveZoom());
    fontDescription.setSpecifiedSize([font pointSize] * style->effectiveZoom());

    // Reset line height
    style->setLineHeight(RenderStyle::initialLineHeight());

    if (style->setFontDescription(fontDescription))
        style->font().update(0);
}

NSControlSize RenderThemeMac::controlSizeForSystemFont(RenderStyle* style) const
{
    int fontSize = style->fontSize();
    if (fontSize >= [NSFont systemFontSizeForControlSize:NSRegularControlSize])
        return NSRegularControlSize;
    if (fontSize >= [NSFont systemFontSizeForControlSize:NSSmallControlSize])
        return NSSmallControlSize;
    return NSMiniControlSize;
}

bool RenderThemeMac::paintTextField(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    LocalCurrentGraphicsContext localContext(paintInfo.context);
    wkDrawBezeledTextFieldCell(r, isEnabled(o) && !isReadOnlyControl(o));
    return false;
}

void RenderThemeMac::adjustTextFieldStyle(CSSStyleSelector*, RenderStyle*, Element*) const
{
}

bool RenderThemeMac::paintCapsLockIndicator(RenderObject*, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    if (paintInfo.context->paintingDisabled())
        return true;

    LocalCurrentGraphicsContext localContext(paintInfo.context);
    wkDrawCapsLockIndicator(paintInfo.context->platformContext(), r);
    
    return false;
}

bool RenderThemeMac::paintTextArea(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    LocalCurrentGraphicsContext localContext(paintInfo.context);
    wkDrawBezeledTextArea(r, isEnabled(o) && !isReadOnlyControl(o));
    return false;
}

void RenderThemeMac::adjustTextAreaStyle(CSSStyleSelector*, RenderStyle*, Element*) const
{
}

const int* RenderThemeMac::popupButtonMargins() const
{
    static const int margins[3][4] =
    {
        { 0, 3, 1, 3 },
        { 0, 3, 2, 3 },
        { 0, 1, 0, 1 }
    };
    return margins[[popupButton() controlSize]];
}

const IntSize* RenderThemeMac::popupButtonSizes() const
{
    static const IntSize sizes[3] = { IntSize(0, 21), IntSize(0, 18), IntSize(0, 15) };
    return sizes;
}

const int* RenderThemeMac::popupButtonPadding(NSControlSize size) const
{
    static const int padding[3][4] =
    {
        { 2, 26, 3, 8 },
        { 2, 23, 3, 8 },
        { 2, 22, 3, 10 }
    };
    return padding[size];
}

bool RenderThemeMac::paintMenuList(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    LocalCurrentGraphicsContext localContext(paintInfo.context);
    setPopupButtonCellState(o, r);

    NSPopUpButtonCell* popupButton = this->popupButton();

    float zoomLevel = o->style()->effectiveZoom();
    IntSize size = popupButtonSizes()[[popupButton controlSize]];
    size.setHeight(size.height() * zoomLevel);
    size.setWidth(r.width());

    // Now inflate it to account for the shadow.
    IntRect inflatedRect = r;
    if (r.width() >= minimumMenuListSize(o->style()))
        inflatedRect = inflateRect(inflatedRect, size, popupButtonMargins(), zoomLevel);

    paintInfo.context->save();
    
#ifndef BUILDING_ON_TIGER
    // On Leopard, the cell will draw outside of the given rect, so we have to clip to the rect
    paintInfo.context->clip(inflatedRect);
#endif

    if (zoomLevel != 1.0f) {
        inflatedRect.setWidth(inflatedRect.width() / zoomLevel);
        inflatedRect.setHeight(inflatedRect.height() / zoomLevel);
        paintInfo.context->translate(inflatedRect.x(), inflatedRect.y());
        paintInfo.context->scale(FloatSize(zoomLevel, zoomLevel));
        paintInfo.context->translate(-inflatedRect.x(), -inflatedRect.y());
    }

    [popupButton drawWithFrame:inflatedRect inView:ThemeMac::ensuredView(o->view()->frameView())];
    [popupButton setControlView:nil];

    paintInfo.context->restore();

    return false;
}
   
#if ENABLE(PROGRESS_TAG)

double RenderThemeMac::animationRepeatIntervalForProgressBar(RenderProgress*) const
{
    return progressAnimationFrameRate;
}

double RenderThemeMac::animationDurationForProgressBar(RenderProgress*) const
{
    return progressAnimationNumFrames * progressAnimationFrameRate;
}

void RenderThemeMac::adjustProgressBarStyle(CSSStyleSelector*, RenderStyle*, Element*) const
{
}

bool RenderThemeMac::paintProgressBar(RenderObject* renderObject, const RenderObject::PaintInfo& paintInfo, const IntRect& rect)
{
    RenderProgress* renderProgress = toRenderProgress(renderObject);
    HIThemeTrackDrawInfo trackInfo;
    trackInfo.version = 0;
    trackInfo.kind = renderProgress->position() < 0 ? kThemeLargeIndeterminateBar : kThemeLargeProgressBar;
    trackInfo.bounds = IntRect(IntPoint(), rect.size());
    trackInfo.min = 0;
    trackInfo.max = numeric_limits<SInt32>::max();
    trackInfo.value = lround(renderProgress->position() * nextafter(trackInfo.max, 0));
    trackInfo.trackInfo.progress.phase = lround(renderProgress->animationProgress() * nextafter(progressAnimationNumFrames, 0));
    trackInfo.attributes = kThemeTrackHorizontal;
    trackInfo.enableState = isActive(renderObject) ? kThemeTrackActive : kThemeTrackInactive;
    trackInfo.reserved = 0;
    trackInfo.filler1 = 0;

    OwnPtr<ImageBuffer> imageBuffer = ImageBuffer::create(rect.size());
    if (!imageBuffer)
        return true;

    HIThemeDrawTrack(&trackInfo, 0, imageBuffer->context()->platformContext(), kHIThemeOrientationNormal);

    paintInfo.context->save();

    if (renderProgress->style()->direction() == RTL) {
        paintInfo.context->translate(2 * rect.x() + rect.width(), 0);
        paintInfo.context->scale(FloatSize(-1, 1));
    }
    paintInfo.context->drawImage(imageBuffer->image(), DeviceColorSpace, rect.location());

    paintInfo.context->restore();
    return false;
}    
#endif

const float baseFontSize = 11.0f;
const float baseArrowHeight = 4.0f;
const float baseArrowWidth = 5.0f;
const float baseSpaceBetweenArrows = 2.0f;
const int arrowPaddingLeft = 6;
const int arrowPaddingRight = 6;
const int paddingBeforeSeparator = 4;
const int baseBorderRadius = 5;
const int styledPopupPaddingLeft = 8;
const int styledPopupPaddingTop = 1;
const int styledPopupPaddingBottom = 2;

static void TopGradientInterpolate(void*, const CGFloat* inData, CGFloat* outData)
{
    static float dark[4] = { 1.0f, 1.0f, 1.0f, 0.4f };
    static float light[4] = { 1.0f, 1.0f, 1.0f, 0.15f };
    float a = inData[0];
    int i = 0;
    for (i = 0; i < 4; i++)
        outData[i] = (1.0f - a) * dark[i] + a * light[i];
}

static void BottomGradientInterpolate(void*, const CGFloat* inData, CGFloat* outData)
{
    static float dark[4] = { 1.0f, 1.0f, 1.0f, 0.0f };
    static float light[4] = { 1.0f, 1.0f, 1.0f, 0.3f };
    float a = inData[0];
    int i = 0;
    for (i = 0; i < 4; i++)
        outData[i] = (1.0f - a) * dark[i] + a * light[i];
}

static void MainGradientInterpolate(void*, const CGFloat* inData, CGFloat* outData)
{
    static float dark[4] = { 0.0f, 0.0f, 0.0f, 0.15f };
    static float light[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
    float a = inData[0];
    int i = 0;
    for (i = 0; i < 4; i++)
        outData[i] = (1.0f - a) * dark[i] + a * light[i];
}

static void TrackGradientInterpolate(void*, const CGFloat* inData, CGFloat* outData)
{
    static float dark[4] = { 0.0f, 0.0f, 0.0f, 0.678f };
    static float light[4] = { 0.0f, 0.0f, 0.0f, 0.13f };
    float a = inData[0];
    int i = 0;
    for (i = 0; i < 4; i++)
        outData[i] = (1.0f - a) * dark[i] + a * light[i];
}

void RenderThemeMac::paintMenuListButtonGradients(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    if (r.isEmpty())
        return;

    CGContextRef context = paintInfo.context->platformContext();

    paintInfo.context->save();

    IntSize topLeftRadius;
    IntSize topRightRadius;
    IntSize bottomLeftRadius;
    IntSize bottomRightRadius;

    o->style()->getBorderRadiiForRect(r, topLeftRadius, topRightRadius, bottomLeftRadius, bottomRightRadius);

    int radius = topLeftRadius.width();

    RetainPtr<CGColorSpaceRef> cspace(AdoptCF, CGColorSpaceCreateDeviceRGB());

    FloatRect topGradient(r.x(), r.y(), r.width(), r.height() / 2.0f);
    struct CGFunctionCallbacks topCallbacks = { 0, TopGradientInterpolate, NULL };
    RetainPtr<CGFunctionRef> topFunction(AdoptCF, CGFunctionCreate(NULL, 1, NULL, 4, NULL, &topCallbacks));
    RetainPtr<CGShadingRef> topShading(AdoptCF, CGShadingCreateAxial(cspace.get(), CGPointMake(topGradient.x(), topGradient.y()), CGPointMake(topGradient.x(), topGradient.bottom()), topFunction.get(), false, false));

    FloatRect bottomGradient(r.x() + radius, r.y() + r.height() / 2.0f, r.width() - 2.0f * radius, r.height() / 2.0f);
    struct CGFunctionCallbacks bottomCallbacks = { 0, BottomGradientInterpolate, NULL };
    RetainPtr<CGFunctionRef> bottomFunction(AdoptCF, CGFunctionCreate(NULL, 1, NULL, 4, NULL, &bottomCallbacks));
    RetainPtr<CGShadingRef> bottomShading(AdoptCF, CGShadingCreateAxial(cspace.get(), CGPointMake(bottomGradient.x(),  bottomGradient.y()), CGPointMake(bottomGradient.x(), bottomGradient.bottom()), bottomFunction.get(), false, false));

    struct CGFunctionCallbacks mainCallbacks = { 0, MainGradientInterpolate, NULL };
    RetainPtr<CGFunctionRef> mainFunction(AdoptCF, CGFunctionCreate(NULL, 1, NULL, 4, NULL, &mainCallbacks));
    RetainPtr<CGShadingRef> mainShading(AdoptCF, CGShadingCreateAxial(cspace.get(), CGPointMake(r.x(),  r.y()), CGPointMake(r.x(), r.bottom()), mainFunction.get(), false, false));

    RetainPtr<CGShadingRef> leftShading(AdoptCF, CGShadingCreateAxial(cspace.get(), CGPointMake(r.x(),  r.y()), CGPointMake(r.x() + radius, r.y()), mainFunction.get(), false, false));

    RetainPtr<CGShadingRef> rightShading(AdoptCF, CGShadingCreateAxial(cspace.get(), CGPointMake(r.right(),  r.y()), CGPointMake(r.right() - radius, r.y()), mainFunction.get(), false, false));
    paintInfo.context->save();
    CGContextClipToRect(context, r);
    paintInfo.context->addRoundedRectClip(r, topLeftRadius, topRightRadius, bottomLeftRadius, bottomRightRadius);
    CGContextDrawShading(context, mainShading.get());
    paintInfo.context->restore();

    paintInfo.context->save();
    CGContextClipToRect(context, topGradient);
    paintInfo.context->addRoundedRectClip(enclosingIntRect(topGradient), topLeftRadius, topRightRadius, IntSize(), IntSize());
    CGContextDrawShading(context, topShading.get());
    paintInfo.context->restore();

    if (!bottomGradient.isEmpty()) {
        paintInfo.context->save();
        CGContextClipToRect(context, bottomGradient);
        paintInfo.context->addRoundedRectClip(enclosingIntRect(bottomGradient), IntSize(), IntSize(), bottomLeftRadius, bottomRightRadius);
        CGContextDrawShading(context, bottomShading.get());
        paintInfo.context->restore();
    }

    paintInfo.context->save();
    CGContextClipToRect(context, r);
    paintInfo.context->addRoundedRectClip(r, topLeftRadius, topRightRadius, bottomLeftRadius, bottomRightRadius);
    CGContextDrawShading(context, leftShading.get());
    CGContextDrawShading(context, rightShading.get());
    paintInfo.context->restore();

    paintInfo.context->restore();
}

bool RenderThemeMac::paintMenuListButton(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    IntRect bounds = IntRect(r.x() + o->style()->borderLeftWidth(),
                             r.y() + o->style()->borderTopWidth(),
                             r.width() - o->style()->borderLeftWidth() - o->style()->borderRightWidth(),
                             r.height() - o->style()->borderTopWidth() - o->style()->borderBottomWidth());
    // Draw the gradients to give the styled popup menu a button appearance
    paintMenuListButtonGradients(o, paintInfo, bounds);

    // Since we actually know the size of the control here, we restrict the font scale to make sure the arrows will fit vertically in the bounds
    float fontScale = min(o->style()->fontSize() / baseFontSize, bounds.height() / (baseArrowHeight * 2 + baseSpaceBetweenArrows));
    float centerY = bounds.y() + bounds.height() / 2.0f;
    float arrowHeight = baseArrowHeight * fontScale;
    float arrowWidth = baseArrowWidth * fontScale;
    float leftEdge = bounds.right() - arrowPaddingRight * o->style()->effectiveZoom() - arrowWidth;
    float spaceBetweenArrows = baseSpaceBetweenArrows * fontScale;

    if (bounds.width() < arrowWidth + arrowPaddingLeft * o->style()->effectiveZoom())
        return false;
    
    paintInfo.context->save();

    paintInfo.context->setFillColor(o->style()->color(), o->style()->colorSpace());
    paintInfo.context->setStrokeStyle(NoStroke);

    FloatPoint arrow1[3];
    arrow1[0] = FloatPoint(leftEdge, centerY - spaceBetweenArrows / 2.0f);
    arrow1[1] = FloatPoint(leftEdge + arrowWidth, centerY - spaceBetweenArrows / 2.0f);
    arrow1[2] = FloatPoint(leftEdge + arrowWidth / 2.0f, centerY - spaceBetweenArrows / 2.0f - arrowHeight);

    // Draw the top arrow
    paintInfo.context->drawConvexPolygon(3, arrow1, true);

    FloatPoint arrow2[3];
    arrow2[0] = FloatPoint(leftEdge, centerY + spaceBetweenArrows / 2.0f);
    arrow2[1] = FloatPoint(leftEdge + arrowWidth, centerY + spaceBetweenArrows / 2.0f);
    arrow2[2] = FloatPoint(leftEdge + arrowWidth / 2.0f, centerY + spaceBetweenArrows / 2.0f + arrowHeight);

    // Draw the bottom arrow
    paintInfo.context->drawConvexPolygon(3, arrow2, true);

    Color leftSeparatorColor(0, 0, 0, 40);
    Color rightSeparatorColor(255, 255, 255, 40);

    // FIXME: Should the separator thickness and space be scaled up by fontScale?
    int separatorSpace = 2; // Deliberately ignores zoom since it looks nicer if it stays thin.
    int leftEdgeOfSeparator = static_cast<int>(leftEdge - arrowPaddingLeft * o->style()->effectiveZoom()); // FIXME: Round?

    // Draw the separator to the left of the arrows
    paintInfo.context->setStrokeThickness(1.0f); // Deliberately ignores zoom since it looks nicer if it stays thin.
    paintInfo.context->setStrokeStyle(SolidStroke);
    paintInfo.context->setStrokeColor(leftSeparatorColor, DeviceColorSpace);
    paintInfo.context->drawLine(IntPoint(leftEdgeOfSeparator, bounds.y()),
                                IntPoint(leftEdgeOfSeparator, bounds.bottom()));

    paintInfo.context->setStrokeColor(rightSeparatorColor, DeviceColorSpace);
    paintInfo.context->drawLine(IntPoint(leftEdgeOfSeparator + separatorSpace, bounds.y()),
                                IntPoint(leftEdgeOfSeparator + separatorSpace, bounds.bottom()));

    paintInfo.context->restore();
    return false;
}

static const IntSize* menuListButtonSizes()
{
    static const IntSize sizes[3] = { IntSize(0, 21), IntSize(0, 18), IntSize(0, 15) };
    return sizes;
}

void RenderThemeMac::adjustMenuListStyle(CSSStyleSelector* selector, RenderStyle* style, Element* e) const
{
    NSControlSize controlSize = controlSizeForFont(style);

    style->resetBorder();
    style->resetPadding();
    
    // Height is locked to auto.
    style->setHeight(Length(Auto));

    // White-space is locked to pre
    style->setWhiteSpace(PRE);

    // Set the foreground color to black or gray when we have the aqua look.
    // Cast to RGB32 is to work around a compiler bug.
    style->setColor(e && e->isEnabledFormControl() ? static_cast<RGBA32>(Color::black) : Color::darkGray);

    // Set the button's vertical size.
    setSizeFromFont(style, menuListButtonSizes());

    // Our font is locked to the appropriate system font size for the control.  To clarify, we first use the CSS-specified font to figure out
    // a reasonable control size, but once that control size is determined, we throw that font away and use the appropriate
    // system font for the control size instead.
    setFontFromControlSize(selector, style, controlSize);

    style->setBoxShadow(0);
}

int RenderThemeMac::popupInternalPaddingLeft(RenderStyle* style) const
{
    if (style->appearance() == MenulistPart)
        return popupButtonPadding(controlSizeForFont(style))[leftPadding] * style->effectiveZoom();
    if (style->appearance() == MenulistButtonPart)
        return styledPopupPaddingLeft * style->effectiveZoom();
    return 0;
}

int RenderThemeMac::popupInternalPaddingRight(RenderStyle* style) const
{
    if (style->appearance() == MenulistPart)
        return popupButtonPadding(controlSizeForFont(style))[rightPadding] * style->effectiveZoom();
    if (style->appearance() == MenulistButtonPart) {
        float fontScale = style->fontSize() / baseFontSize;
        float arrowWidth = baseArrowWidth * fontScale;
        return static_cast<int>(ceilf(arrowWidth + (arrowPaddingLeft + arrowPaddingRight + paddingBeforeSeparator) * style->effectiveZoom()));
    }
    return 0;
}

int RenderThemeMac::popupInternalPaddingTop(RenderStyle* style) const
{
    if (style->appearance() == MenulistPart)
        return popupButtonPadding(controlSizeForFont(style))[topPadding] * style->effectiveZoom();
    if (style->appearance() == MenulistButtonPart)
        return styledPopupPaddingTop * style->effectiveZoom();
    return 0;
}

int RenderThemeMac::popupInternalPaddingBottom(RenderStyle* style) const
{
    if (style->appearance() == MenulistPart)
        return popupButtonPadding(controlSizeForFont(style))[bottomPadding] * style->effectiveZoom();
    if (style->appearance() == MenulistButtonPart)
        return styledPopupPaddingBottom * style->effectiveZoom();
    return 0;
}

void RenderThemeMac::adjustMenuListButtonStyle(CSSStyleSelector*, RenderStyle* style, Element*) const
{
    float fontScale = style->fontSize() / baseFontSize;

    style->resetPadding();
    style->setBorderRadius(IntSize(int(baseBorderRadius + fontScale - 1), int(baseBorderRadius + fontScale - 1))); // FIXME: Round up?

    const int minHeight = 15;
    style->setMinHeight(Length(minHeight, Fixed));
    
    style->setLineHeight(RenderStyle::initialLineHeight());
}

void RenderThemeMac::setPopupButtonCellState(const RenderObject* o, const IntRect& r)
{
    NSPopUpButtonCell* popupButton = this->popupButton();

    // Set the control size based off the rectangle we're painting into.
    setControlSize(popupButton, popupButtonSizes(), r.size(), o->style()->effectiveZoom());

    // Update the various states we respond to.
    updateCheckedState(popupButton, o);
    updateEnabledState(popupButton, o);
    updatePressedState(popupButton, o);
    updateFocusedState(popupButton, o);
}

const IntSize* RenderThemeMac::menuListSizes() const
{
    static const IntSize sizes[3] = { IntSize(9, 0), IntSize(5, 0), IntSize(0, 0) };
    return sizes;
}

int RenderThemeMac::minimumMenuListSize(RenderStyle* style) const
{
    return sizeForSystemFont(style, menuListSizes()).width();
}

const int trackWidth = 5;
const int trackRadius = 2;

void RenderThemeMac::adjustSliderTrackStyle(CSSStyleSelector*, RenderStyle* style, Element*) const
{
    style->setBoxShadow(0);
}

bool RenderThemeMac::paintSliderTrack(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    IntRect bounds = r;
    float zoomLevel = o->style()->effectiveZoom();
    float zoomedTrackWidth = trackWidth * zoomLevel;

    if (o->style()->appearance() ==  SliderHorizontalPart || o->style()->appearance() ==  MediaSliderPart) {
        bounds.setHeight(zoomedTrackWidth);
        bounds.setY(r.y() + r.height() / 2 - zoomedTrackWidth / 2);
    } else if (o->style()->appearance() == SliderVerticalPart) {
        bounds.setWidth(zoomedTrackWidth);
        bounds.setX(r.x() + r.width() / 2 - zoomedTrackWidth / 2);
    }

    LocalCurrentGraphicsContext localContext(paintInfo.context);
    CGContextRef context = paintInfo.context->platformContext();
    RetainPtr<CGColorSpaceRef> cspace(AdoptCF, CGColorSpaceCreateDeviceRGB());

    paintInfo.context->save();
    CGContextClipToRect(context, bounds);

    struct CGFunctionCallbacks mainCallbacks = { 0, TrackGradientInterpolate, NULL };
    RetainPtr<CGFunctionRef> mainFunction(AdoptCF, CGFunctionCreate(NULL, 1, NULL, 4, NULL, &mainCallbacks));
    RetainPtr<CGShadingRef> mainShading;
    if (o->style()->appearance() == SliderVerticalPart)
        mainShading.adoptCF(CGShadingCreateAxial(cspace.get(), CGPointMake(bounds.x(),  bounds.bottom()), CGPointMake(bounds.right(), bounds.bottom()), mainFunction.get(), false, false));
    else
        mainShading.adoptCF(CGShadingCreateAxial(cspace.get(), CGPointMake(bounds.x(),  bounds.y()), CGPointMake(bounds.x(), bounds.bottom()), mainFunction.get(), false, false));

    IntSize radius(trackRadius, trackRadius);
    paintInfo.context->addRoundedRectClip(bounds,
        radius, radius,
        radius, radius);
    CGContextDrawShading(context, mainShading.get());
    paintInfo.context->restore();
    
    return false;
}

void RenderThemeMac::adjustSliderThumbStyle(CSSStyleSelector*, RenderStyle* style, Element*) const
{
    style->setBoxShadow(0);
}

const float verticalSliderHeightPadding = 0.1f;

bool RenderThemeMac::paintSliderThumb(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    ASSERT(o->parent()->isSlider());

    NSSliderCell* sliderThumbCell = o->style()->appearance() == SliderThumbVerticalPart
        ? sliderThumbVertical()
        : sliderThumbHorizontal();

    LocalCurrentGraphicsContext localContext(paintInfo.context);

    // Update the various states we respond to.
    updateEnabledState(sliderThumbCell, o->parent());
    updateFocusedState(sliderThumbCell, o->parent());

    // Update the pressed state using the NSCell tracking methods, since that's how NSSliderCell keeps track of it.
    bool oldPressed;
    if (o->style()->appearance() == SliderThumbVerticalPart)
        oldPressed = m_isSliderThumbVerticalPressed;
    else
        oldPressed = m_isSliderThumbHorizontalPressed;

    bool pressed = toRenderSlider(o->parent())->inDragMode();

    if (o->style()->appearance() == SliderThumbVerticalPart)
        m_isSliderThumbVerticalPressed = pressed;
    else
        m_isSliderThumbHorizontalPressed = pressed;

    if (pressed != oldPressed) {
        if (pressed)
            [sliderThumbCell startTrackingAt:NSPoint() inView:nil];
        else
            [sliderThumbCell stopTracking:NSPoint() at:NSPoint() inView:nil mouseIsUp:YES];
    }

    FloatRect bounds = r;
    // Make the height of the vertical slider slightly larger so NSSliderCell will draw a vertical slider.
    if (o->style()->appearance() == SliderThumbVerticalPart)
        bounds.setHeight(bounds.height() + verticalSliderHeightPadding * o->style()->effectiveZoom());

    paintInfo.context->save();
    float zoomLevel = o->style()->effectiveZoom();
    
    FloatRect unzoomedRect = bounds;
    if (zoomLevel != 1.0f) {
        unzoomedRect.setWidth(unzoomedRect.width() / zoomLevel);
        unzoomedRect.setHeight(unzoomedRect.height() / zoomLevel);
        paintInfo.context->translate(unzoomedRect.x(), unzoomedRect.y());
        paintInfo.context->scale(FloatSize(zoomLevel, zoomLevel));
        paintInfo.context->translate(-unzoomedRect.x(), -unzoomedRect.y());
    }

    [sliderThumbCell drawWithFrame:unzoomedRect inView:ThemeMac::ensuredView(o->view()->frameView())];
    [sliderThumbCell setControlView:nil];

    paintInfo.context->restore();

    return false;
}

bool RenderThemeMac::paintSearchField(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    NSSearchFieldCell* search = this->search();
    LocalCurrentGraphicsContext localContext(paintInfo.context);

    setSearchCellState(o, r);

    paintInfo.context->save();

    float zoomLevel = o->style()->effectiveZoom();

    IntRect unzoomedRect = r;
    
    if (zoomLevel != 1.0f) {
        unzoomedRect.setWidth(unzoomedRect.width() / zoomLevel);
        unzoomedRect.setHeight(unzoomedRect.height() / zoomLevel);
        paintInfo.context->translate(unzoomedRect.x(), unzoomedRect.y());
        paintInfo.context->scale(FloatSize(zoomLevel, zoomLevel));
        paintInfo.context->translate(-unzoomedRect.x(), -unzoomedRect.y());
    }

    // Set the search button to nil before drawing.  Then reset it so we can draw it later.
    [search setSearchButtonCell:nil];

    [search drawWithFrame:NSRect(unzoomedRect) inView:ThemeMac::ensuredView(o->view()->frameView())];
#ifdef BUILDING_ON_TIGER
    if ([search showsFirstResponder])
        wkDrawTextFieldCellFocusRing(search, NSRect(unzoomedRect));
#endif

    [search setControlView:nil];
    [search resetSearchButtonCell];

    paintInfo.context->restore();

    return false;
}

void RenderThemeMac::setSearchCellState(RenderObject* o, const IntRect&)
{
    NSSearchFieldCell* search = this->search();

    [search setControlSize:controlSizeForFont(o->style())];

    // Update the various states we respond to.
    updateEnabledState(search, o);
    updateFocusedState(search, o);
}

const IntSize* RenderThemeMac::searchFieldSizes() const
{
    static const IntSize sizes[3] = { IntSize(0, 22), IntSize(0, 19), IntSize(0, 17) };
    return sizes;
}

void RenderThemeMac::setSearchFieldSize(RenderStyle* style) const
{
    // If the width and height are both specified, then we have nothing to do.
    if (!style->width().isIntrinsicOrAuto() && !style->height().isAuto())
        return;
    
    // Use the font size to determine the intrinsic width of the control.
    setSizeFromFont(style, searchFieldSizes());
}

void RenderThemeMac::adjustSearchFieldStyle(CSSStyleSelector* selector, RenderStyle* style, Element*) const
{
    // Override border.
    style->resetBorder();
    const short borderWidth = 2 * style->effectiveZoom();
    style->setBorderLeftWidth(borderWidth);
    style->setBorderLeftStyle(INSET);
    style->setBorderRightWidth(borderWidth);
    style->setBorderRightStyle(INSET);
    style->setBorderBottomWidth(borderWidth);
    style->setBorderBottomStyle(INSET);
    style->setBorderTopWidth(borderWidth);
    style->setBorderTopStyle(INSET);    
    
    // Override height.
    style->setHeight(Length(Auto));
    setSearchFieldSize(style);
    
    // Override padding size to match AppKit text positioning.
    const int padding = 1 * style->effectiveZoom();
    style->setPaddingLeft(Length(padding, Fixed));
    style->setPaddingRight(Length(padding, Fixed));
    style->setPaddingTop(Length(padding, Fixed));
    style->setPaddingBottom(Length(padding, Fixed));
    
    NSControlSize controlSize = controlSizeForFont(style);
    setFontFromControlSize(selector, style, controlSize);

    style->setBoxShadow(0);
}

bool RenderThemeMac::paintSearchFieldCancelButton(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* input = o->node()->shadowAncestorNode();
    if (!input->renderer()->isBox())
        return false;

    setSearchCellState(input->renderer(), r);

    NSSearchFieldCell* search = this->search();

    updatePressedState([search cancelButtonCell], o);

    paintInfo.context->save();

    float zoomLevel = o->style()->effectiveZoom();

    FloatRect localBounds = [search cancelButtonRectForBounds:NSRect(input->renderBox()->borderBoxRect())];
    localBounds = convertToPaintingRect(input->renderer(), o, localBounds, r);

    FloatRect unzoomedRect(localBounds);
    if (zoomLevel != 1.0f) {
        unzoomedRect.setWidth(unzoomedRect.width() / zoomLevel);
        unzoomedRect.setHeight(unzoomedRect.height() / zoomLevel);
        paintInfo.context->translate(unzoomedRect.x(), unzoomedRect.y());
        paintInfo.context->scale(FloatSize(zoomLevel, zoomLevel));
        paintInfo.context->translate(-unzoomedRect.x(), -unzoomedRect.y());
    }

    [[search cancelButtonCell] drawWithFrame:unzoomedRect inView:ThemeMac::ensuredView(o->view()->frameView())];
    [[search cancelButtonCell] setControlView:nil];

    paintInfo.context->restore();
    return false;
}

const IntSize* RenderThemeMac::cancelButtonSizes() const
{
    static const IntSize sizes[3] = { IntSize(16, 13), IntSize(13, 11), IntSize(13, 9) };
    return sizes;
}

void RenderThemeMac::adjustSearchFieldCancelButtonStyle(CSSStyleSelector*, RenderStyle* style, Element*) const
{
    IntSize size = sizeForSystemFont(style, cancelButtonSizes());
    style->setWidth(Length(size.width(), Fixed));
    style->setHeight(Length(size.height(), Fixed));
    style->setBoxShadow(0);
}

const IntSize* RenderThemeMac::resultsButtonSizes() const
{
    static const IntSize sizes[3] = { IntSize(19, 13), IntSize(17, 11), IntSize(17, 9) };
    return sizes;
}

const int emptyResultsOffset = 9;
void RenderThemeMac::adjustSearchFieldDecorationStyle(CSSStyleSelector*, RenderStyle* style, Element*) const
{
    IntSize size = sizeForSystemFont(style, resultsButtonSizes());
    style->setWidth(Length(size.width() - emptyResultsOffset, Fixed));
    style->setHeight(Length(size.height(), Fixed));
    style->setBoxShadow(0);
}

bool RenderThemeMac::paintSearchFieldDecoration(RenderObject*, const RenderObject::PaintInfo&, const IntRect&)
{
    return false;
}

void RenderThemeMac::adjustSearchFieldResultsDecorationStyle(CSSStyleSelector*, RenderStyle* style, Element*) const
{
    IntSize size = sizeForSystemFont(style, resultsButtonSizes());
    style->setWidth(Length(size.width(), Fixed));
    style->setHeight(Length(size.height(), Fixed));
    style->setBoxShadow(0);
}

bool RenderThemeMac::paintSearchFieldResultsDecoration(RenderObject* o, const RenderObject::PaintInfo&, const IntRect& r)
{
    Node* input = o->node()->shadowAncestorNode();
    if (!input->renderer()->isBox())
        return false;

    setSearchCellState(input->renderer(), r);

    NSSearchFieldCell* search = this->search();

    if ([search searchMenuTemplate] != nil)
        [search setSearchMenuTemplate:nil];

    FloatRect localBounds = [search searchButtonRectForBounds:NSRect(input->renderBox()->borderBoxRect())];
    localBounds = convertToPaintingRect(input->renderer(), o, localBounds, r);

    [[search searchButtonCell] drawWithFrame:localBounds inView:ThemeMac::ensuredView(o->view()->frameView())];
    [[search searchButtonCell] setControlView:nil];
    return false;
}

const int resultsArrowWidth = 5;
void RenderThemeMac::adjustSearchFieldResultsButtonStyle(CSSStyleSelector*, RenderStyle* style, Element*) const
{
    IntSize size = sizeForSystemFont(style, resultsButtonSizes());
    style->setWidth(Length(size.width() + resultsArrowWidth, Fixed));
    style->setHeight(Length(size.height(), Fixed));
    style->setBoxShadow(0);
}

bool RenderThemeMac::paintSearchFieldResultsButton(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* input = o->node()->shadowAncestorNode();
    if (!input->renderer()->isBox())
        return false;

    setSearchCellState(input->renderer(), r);

    NSSearchFieldCell* search = this->search();

    if (![search searchMenuTemplate])
        [search setSearchMenuTemplate:searchMenuTemplate()];

    paintInfo.context->save();

    float zoomLevel = o->style()->effectiveZoom();

    FloatRect localBounds = [search searchButtonRectForBounds:NSRect(input->renderBox()->borderBoxRect())];
    localBounds = convertToPaintingRect(input->renderer(), o, localBounds, r);
    
    IntRect unzoomedRect(localBounds);
    if (zoomLevel != 1.0f) {
        unzoomedRect.setWidth(unzoomedRect.width() / zoomLevel);
        unzoomedRect.setHeight(unzoomedRect.height() / zoomLevel);
        paintInfo.context->translate(unzoomedRect.x(), unzoomedRect.y());
        paintInfo.context->scale(FloatSize(zoomLevel, zoomLevel));
        paintInfo.context->translate(-unzoomedRect.x(), -unzoomedRect.y());
    }

    [[search searchButtonCell] drawWithFrame:unzoomedRect inView:ThemeMac::ensuredView(o->view()->frameView())];
    [[search searchButtonCell] setControlView:nil];
    
    paintInfo.context->restore();

    return false;
}

#if ENABLE(VIDEO)
typedef enum {
    MediaControllerThemeClassic   = 1,
    MediaControllerThemeQuickTime = 2
} MediaControllerThemeStyle;

static int mediaControllerTheme()
{
    static int controllerTheme = -1;
    
    if (controllerTheme != -1)
        return controllerTheme;

    controllerTheme = MediaControllerThemeClassic;

    Boolean validKey;
    Boolean useQTMediaUIPref = CFPreferencesGetAppBooleanValue(CFSTR("UseQuickTimeMediaUI"), CFSTR("com.apple.WebCore"), &validKey);

#if !defined(BUILDING_ON_TIGER)
    if (validKey && !useQTMediaUIPref)
        return controllerTheme;
#else
    if (!validKey || !useQTMediaUIPref)
        return controllerTheme;
#endif

    controllerTheme = MediaControllerThemeQuickTime;
    return controllerTheme;
}
#endif

const int sliderThumbWidth = 15;
const int sliderThumbHeight = 15;
const int mediaSliderThumbWidth = 13;
const int mediaSliderThumbHeight = 14;

void RenderThemeMac::adjustSliderThumbSize(RenderObject* o) const
{
    float zoomLevel = o->style()->effectiveZoom();
    if (o->style()->appearance() == SliderThumbHorizontalPart || o->style()->appearance() == SliderThumbVerticalPart) {
        o->style()->setWidth(Length(static_cast<int>(sliderThumbWidth * zoomLevel), Fixed));
        o->style()->setHeight(Length(static_cast<int>(sliderThumbHeight * zoomLevel), Fixed));
    } 

#if ENABLE(VIDEO)
    else if (o->style()->appearance() == MediaSliderThumbPart) {
        int width = mediaSliderThumbWidth;
        int height = mediaSliderThumbHeight;
        
        if (mediaControllerTheme() == MediaControllerThemeQuickTime) {
            CGSize  size;
            
            wkMeasureMediaUIPart(MediaSliderThumb, MediaControllerThemeQuickTime, NULL, &size);
            width = size.width;
            height = size.height;
        }

        o->style()->setWidth(Length(static_cast<int>(width * zoomLevel), Fixed));
        o->style()->setHeight(Length(static_cast<int>(height * zoomLevel), Fixed));
    }
#endif
}


#if ENABLE(VIDEO)

enum WKMediaControllerThemeState { 
    MediaUIPartDisabledFlag = 1 << 0,
    MediaUIPartPressedFlag = 1 << 1,
    MediaUIPartDrawEndCapsFlag = 1 << 3,
};

static unsigned getMediaUIPartStateFlags(Node* node)
{
    unsigned flags = 0;

    if (node->disabled())
        flags |= MediaUIPartDisabledFlag;
    else if (node->active())
        flags |= MediaUIPartPressedFlag;
    return flags;
}

// Utility to scale when the UI part are not scaled by wkDrawMediaUIPart
static FloatRect getUnzoomedRectAndAdjustCurrentContext(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect &originalRect)
{
    float zoomLevel = o->style()->effectiveZoom();
    FloatRect unzoomedRect(originalRect);
    if (zoomLevel != 1.0f && mediaControllerTheme() == MediaControllerThemeQuickTime) {
        unzoomedRect.setWidth(unzoomedRect.width() / zoomLevel);
        unzoomedRect.setHeight(unzoomedRect.height() / zoomLevel);
        paintInfo.context->translate(unzoomedRect.x(), unzoomedRect.y());
        paintInfo.context->scale(FloatSize(zoomLevel, zoomLevel));
        paintInfo.context->translate(-unzoomedRect.x(), -unzoomedRect.y());
    }
    return unzoomedRect;
}


bool RenderThemeMac::paintMediaFullscreenButton(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* node = o->node();
    if (!node)
        return false;

    LocalCurrentGraphicsContext localContext(paintInfo.context);
    wkDrawMediaUIPart(MediaFullscreenButton, mediaControllerTheme(), paintInfo.context->platformContext(), r, getMediaUIPartStateFlags(node));
    return false;
}

bool RenderThemeMac::paintMediaMuteButton(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* node = o->node();
    Node* mediaNode = node ? node->shadowAncestorNode() : 0;
    if (!mediaNode || (!mediaNode->hasTagName(videoTag) && !mediaNode->hasTagName(audioTag)))
        return false;

    if (MediaControlMuteButtonElement* btn = static_cast<MediaControlMuteButtonElement*>(node)) {
        LocalCurrentGraphicsContext localContext(paintInfo.context);
        wkDrawMediaUIPart(btn->displayType(), mediaControllerTheme(), paintInfo.context->platformContext(), r, getMediaUIPartStateFlags(node));

    }
    return false;
}

bool RenderThemeMac::paintMediaPlayButton(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* node = o->node();
    Node* mediaNode = node ? node->shadowAncestorNode() : 0;
    if (!mediaNode || (!mediaNode->hasTagName(videoTag) && !mediaNode->hasTagName(audioTag)))
        return false;

    if (MediaControlPlayButtonElement* btn = static_cast<MediaControlPlayButtonElement*>(node)) {
        LocalCurrentGraphicsContext localContext(paintInfo.context);
        wkDrawMediaUIPart(btn->displayType(), mediaControllerTheme(), paintInfo.context->platformContext(), r, getMediaUIPartStateFlags(node));
    }
    return false;
}

bool RenderThemeMac::paintMediaSeekBackButton(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* node = o->node();
    if (!node)
        return false;

    LocalCurrentGraphicsContext localContext(paintInfo.context);
    wkDrawMediaUIPart(MediaSeekBackButton, mediaControllerTheme(), paintInfo.context->platformContext(), r, getMediaUIPartStateFlags(node));
    return false;
}

bool RenderThemeMac::paintMediaSeekForwardButton(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* node = o->node();
    if (!node)
        return false;

    LocalCurrentGraphicsContext localContext(paintInfo.context);
    wkDrawMediaUIPart(MediaSeekForwardButton, mediaControllerTheme(), paintInfo.context->platformContext(), r, getMediaUIPartStateFlags(node));
    return false;
}

bool RenderThemeMac::paintMediaSliderTrack(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* node = o->node();
    Node* mediaNode = node ? node->shadowAncestorNode() : 0;
    if (!mediaNode || (!mediaNode->hasTagName(videoTag) && !mediaNode->hasTagName(audioTag)))
        return false;

    HTMLMediaElement* mediaElement = static_cast<HTMLMediaElement*>(mediaNode);
    if (!mediaElement)
        return false;

    RefPtr<TimeRanges> timeRanges = mediaElement->buffered();
    ExceptionCode ignoredException;
    float timeLoaded = timeRanges->length() ? timeRanges->end(0, ignoredException) : 0;
    float currentTime = mediaElement->currentTime();
    float duration = mediaElement->duration();
    if (isnan(duration))
        duration = 0;
 
    paintInfo.context->save();
    FloatRect unzoomedRect = getUnzoomedRectAndAdjustCurrentContext(o, paintInfo, r);
    wkDrawMediaSliderTrack(mediaControllerTheme(), paintInfo.context->platformContext(), unzoomedRect, 
        timeLoaded, currentTime, duration, getMediaUIPartStateFlags(node));
    
    paintInfo.context->restore();
    return false;
}

bool RenderThemeMac::paintMediaSliderThumb(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* node = o->node();
    if (!node)
        return false;

    LocalCurrentGraphicsContext localContext(paintInfo.context);
    wkDrawMediaUIPart(MediaSliderThumb, mediaControllerTheme(), paintInfo.context->platformContext(), r, getMediaUIPartStateFlags(node));
    return false;
}
    
bool RenderThemeMac::paintMediaRewindButton(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* node = o->node();
    if (!node)
        return false;
    
    LocalCurrentGraphicsContext localContext(paintInfo.context);
    wkDrawMediaUIPart(MediaRewindButton, mediaControllerTheme(), paintInfo.context->platformContext(), r, getMediaUIPartStateFlags(node));
    return false;
}

bool RenderThemeMac::paintMediaReturnToRealtimeButton(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* node = o->node();
    if (!node)
        return false;
    
    LocalCurrentGraphicsContext localContext(paintInfo.context);
    wkDrawMediaUIPart(MediaReturnToRealtimeButton, mediaControllerTheme(), paintInfo.context->platformContext(), r, getMediaUIPartStateFlags(node));
    return false;
}

bool RenderThemeMac::paintMediaToggleClosedCaptionsButton(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    HTMLInputElement* node = static_cast<HTMLInputElement*>(o->node());
    if (!node)
        return false;
    
    MediaControlToggleClosedCaptionsButtonElement* btn = static_cast<MediaControlToggleClosedCaptionsButtonElement*>(node);
    if (!btn)
        return false;

    LocalCurrentGraphicsContext localContext(paintInfo.context);
    wkDrawMediaUIPart(btn->displayType(), mediaControllerTheme(), paintInfo.context->platformContext(), r, getMediaUIPartStateFlags(node));

    return false;
}
 
bool RenderThemeMac::paintMediaControlsBackground(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* node = o->node();
    if (!node)
        return false;

    LocalCurrentGraphicsContext localContext(paintInfo.context);
    wkDrawMediaUIPart(MediaTimelineContainer, mediaControllerTheme(), paintInfo.context->platformContext(), r, getMediaUIPartStateFlags(node));
    return false;
}

bool RenderThemeMac::paintMediaCurrentTime(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* node = o->node();
    if (!node)
        return false;

    paintInfo.context->save();
    FloatRect unzoomedRect = getUnzoomedRectAndAdjustCurrentContext(o, paintInfo, r);
    wkDrawMediaUIPart(MediaCurrentTimeDisplay, mediaControllerTheme(), paintInfo.context->platformContext(), unzoomedRect, getMediaUIPartStateFlags(node));
    paintInfo.context->restore();
    return false;
}

bool RenderThemeMac::paintMediaTimeRemaining(RenderObject* o, const RenderObject::PaintInfo& paintInfo, const IntRect& r)
{
    Node* node = o->node();
    if (!node)
        return false;

    paintInfo.context->save();
    FloatRect unzoomedRect = getUnzoomedRectAndAdjustCurrentContext(o, paintInfo, r);
    wkDrawMediaUIPart(MediaTimeRemainingDisplay, mediaControllerTheme(), paintInfo.context->platformContext(), unzoomedRect, getMediaUIPartStateFlags(node));
    paintInfo.context->restore();
    return false;
}

String RenderThemeMac::extraMediaControlsStyleSheet()
{
    if (mediaControllerTheme() == MediaControllerThemeQuickTime)
        return String(mediaControlsQuickTimeUserAgentStyleSheet, sizeof(mediaControlsQuickTimeUserAgentStyleSheet));
    else
        return String();
}

bool RenderThemeMac::shouldRenderMediaControlPart(ControlPart part, Element* element)
{
    if (part == MediaToggleClosedCaptionsButtonPart) {

        // We rely on QTKit to render captions so don't enable the button unless it will be able to do so.
        if (!element->hasTagName(videoTag))
            return false;
    }

    return RenderTheme::shouldRenderMediaControlPart(part, element);
}

#endif // ENABLE(VIDEO)

NSPopUpButtonCell* RenderThemeMac::popupButton() const
{
    if (!m_popupButton) {
        m_popupButton.adoptNS([[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO]);
        [m_popupButton.get() setUsesItemFromMenu:NO];
        [m_popupButton.get() setFocusRingType:NSFocusRingTypeExterior];
    }
    
    return m_popupButton.get();
}

NSSearchFieldCell* RenderThemeMac::search() const
{
    if (!m_search) {
        m_search.adoptNS([[NSSearchFieldCell alloc] initTextCell:@""]);
        [m_search.get() setBezelStyle:NSTextFieldRoundedBezel];
        [m_search.get() setBezeled:YES];
        [m_search.get() setEditable:YES];
        [m_search.get() setFocusRingType:NSFocusRingTypeExterior];
    }

    return m_search.get();
}

NSMenu* RenderThemeMac::searchMenuTemplate() const
{
    if (!m_searchMenuTemplate)
        m_searchMenuTemplate.adoptNS([[NSMenu alloc] initWithTitle:@""]);

    return m_searchMenuTemplate.get();
}

NSSliderCell* RenderThemeMac::sliderThumbHorizontal() const
{
    if (!m_sliderThumbHorizontal) {
        m_sliderThumbHorizontal.adoptNS([[NSSliderCell alloc] init]);
        [m_sliderThumbHorizontal.get() setTitle:nil];
        [m_sliderThumbHorizontal.get() setSliderType:NSLinearSlider];
        [m_sliderThumbHorizontal.get() setControlSize:NSSmallControlSize];
        [m_sliderThumbHorizontal.get() setFocusRingType:NSFocusRingTypeExterior];
    }
    
    return m_sliderThumbHorizontal.get();
}

NSSliderCell* RenderThemeMac::sliderThumbVertical() const
{
    if (!m_sliderThumbVertical) {
        m_sliderThumbVertical.adoptNS([[NSSliderCell alloc] init]);
        [m_sliderThumbVertical.get() setTitle:nil];
        [m_sliderThumbVertical.get() setSliderType:NSLinearSlider];
        [m_sliderThumbVertical.get() setControlSize:NSSmallControlSize];
        [m_sliderThumbVertical.get() setFocusRingType:NSFocusRingTypeExterior];
    }
    
    return m_sliderThumbVertical.get();
}

} // namespace WebCore
