/*
 * Copyright (C) 1999 Lars Knoll (knoll@kde.org)
 *           (C) 2000 Simon Hausmann <hausmann@kde.org>
 *           (C) 2000 Stefan Schimanski (1Stein@gmx.de)
 * Copyright (C) 2004, 2005, 2006, 2008, 2009, 2010 Apple Inc. All rights reserved.
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
 *
 */

#include "config.h"
#include "RenderEmbeddedObject.h"

#include "Chrome.h"
#include "ChromeClient.h"
#include "Cursor.h"
#include "CSSValueKeywords.h"
#include "Font.h"
#include "FontSelector.h"
#include "Frame.h"
#include "FrameLoaderClient.h"
#include "GraphicsContext.h"
#include "HTMLEmbedElement.h"
#include "HTMLIFrameElement.h"
#include "HTMLNames.h"
#include "HTMLObjectElement.h"
#include "HTMLParamElement.h"
#include "HitTestResult.h"
#include "LocalizedStrings.h"
#include "MIMETypeRegistry.h"
#include "MouseEvent.h"
#include "Page.h"
#include "PaintInfo.h"
#include "Path.h"
#include "PluginViewBase.h"
#include "RenderTheme.h"
#include "RenderView.h"
#include "RenderWidgetProtector.h"
#include "Settings.h"
#include "Text.h"
#include "TextRun.h"

#if ENABLE(PLUGIN_PROXY_FOR_VIDEO)
#include "HTMLMediaElement.h"
#endif

namespace WebCore {

using namespace HTMLNames;
    
static const float replacementTextRoundedRectHeight = 18;
static const float replacementTextRoundedRectLeftRightTextMargin = 6;
static const float replacementTextRoundedRectOpacity = 0.20f;
static const float replacementTextPressedRoundedRectOpacity = 0.65f;
static const float replacementTextRoundedRectRadius = 5;
static const float replacementTextTextOpacity = 0.55f;
static const float replacementTextPressedTextOpacity = 0.65f;

static const Color& replacementTextRoundedRectPressedColor()
{
    static const Color lightGray(205, 205, 205);
    return lightGray;
}
    
RenderEmbeddedObject::RenderEmbeddedObject(Element* element)
    : RenderPart(element)
    , m_hasFallbackContent(false)
    , m_showsUnavailablePluginIndicator(false)
    , m_unavailablePluginIndicatorIsPressed(false)
    , m_mouseDownWasInUnavailablePluginIndicator(false)
{
    view()->frameView()->setIsVisuallyNonEmpty();
}

RenderEmbeddedObject::~RenderEmbeddedObject()
{
    if (frameView())
        frameView()->removeWidgetToUpdate(this);
}

#if USE(ACCELERATED_COMPOSITING)
bool RenderEmbeddedObject::requiresLayer() const
{
    if (RenderPart::requiresLayer())
        return true;
    
    return allowsAcceleratedCompositing();
}

bool RenderEmbeddedObject::allowsAcceleratedCompositing() const
{
    return widget() && widget()->isPluginViewBase() && static_cast<PluginViewBase*>(widget())->platformLayer();
}
#endif

static String unavailablePluginReplacementText(RenderEmbeddedObject::PluginUnavailabilityReason pluginUnavailabilityReason)
{
    switch (pluginUnavailabilityReason) {
    case RenderEmbeddedObject::PluginMissing:
        return missingPluginText();
    case RenderEmbeddedObject::PluginCrashed:
        return crashedPluginText();
    case RenderEmbeddedObject::PluginBlockedByContentSecurityPolicy:
        return blockedPluginByContentSecurityPolicyText();
    case RenderEmbeddedObject::InsecurePluginVersion:
        return insecurePluginVersionText();
    case RenderEmbeddedObject::PluginInactive:
        return inactivePluginText();
    }

    ASSERT_NOT_REACHED();
    return String();
}

void RenderEmbeddedObject::setPluginUnavailabilityReason(PluginUnavailabilityReason pluginUnavailabilityReason)
{
    ASSERT(!m_showsUnavailablePluginIndicator);
    m_showsUnavailablePluginIndicator = true;
    m_pluginUnavailabilityReason = pluginUnavailabilityReason;

    m_unavailablePluginReplacementText = unavailablePluginReplacementText(pluginUnavailabilityReason);
}

bool RenderEmbeddedObject::showsUnavailablePluginIndicator() const
{
    return m_showsUnavailablePluginIndicator;
}

void RenderEmbeddedObject::setUnavailablePluginIndicatorIsPressed(bool pressed)
{
    if (m_unavailablePluginIndicatorIsPressed == pressed)
        return;
    
    m_unavailablePluginIndicatorIsPressed = pressed;
    repaint();
}

void RenderEmbeddedObject::paint(PaintInfo& paintInfo, const LayoutPoint& paintOffset)
{
    Page* page = 0;
    if (Frame* frame = this->frame())
        page = frame->page();

    if (showsUnavailablePluginIndicator()) {
        if (page && paintInfo.phase == PaintPhaseForeground)
            page->addRelevantUnpaintedObject(this, visualOverflowRect());
        RenderReplaced::paint(paintInfo, paintOffset);
        return;
    }

    if (page && paintInfo.phase == PaintPhaseForeground)
        page->addRelevantRepaintedObject(this, visualOverflowRect());

    RenderPart::paint(paintInfo, paintOffset);
}

void RenderEmbeddedObject::paintReplaced(PaintInfo& paintInfo, const LayoutPoint& paintOffset)
{
    if (!showsUnavailablePluginIndicator())
        return;

    if (paintInfo.phase == PaintPhaseSelection)
        return;
    
    GraphicsContext* context = paintInfo.context;
    if (context->paintingDisabled())
        return;
    
    FloatRect contentRect;
    Path path;
    FloatRect replacementTextRect;
    Font font;
    TextRun run("");
    float textWidth;
    if (!getReplacementTextGeometry(paintOffset, contentRect, path, replacementTextRect, font, run, textWidth))
        return;
    
    GraphicsContextStateSaver stateSaver(*context);
    context->clip(contentRect);
    context->setAlpha(m_unavailablePluginIndicatorIsPressed ? replacementTextPressedRoundedRectOpacity : replacementTextRoundedRectOpacity);
    context->setFillColor(m_unavailablePluginIndicatorIsPressed ? replacementTextRoundedRectPressedColor() : Color::white, style()->colorSpace());
    context->fillPath(path);

    const FontMetrics& fontMetrics = font.fontMetrics();
    float labelX = roundf(replacementTextRect.location().x() + (replacementTextRect.size().width() - textWidth) / 2);
    float labelY = roundf(replacementTextRect.location().y() + (replacementTextRect.size().height() - fontMetrics.height()) / 2 + fontMetrics.ascent());
    context->setAlpha(m_unavailablePluginIndicatorIsPressed ? replacementTextPressedTextOpacity : replacementTextTextOpacity);
    context->setFillColor(Color::black, style()->colorSpace());
    context->drawBidiText(font, run, FloatPoint(labelX, labelY));
}

bool RenderEmbeddedObject::getReplacementTextGeometry(const LayoutPoint& accumulatedOffset, FloatRect& contentRect, Path& path, FloatRect& replacementTextRect, Font& font, TextRun& run, float& textWidth) const
{
    contentRect = contentBoxRect();
    contentRect.moveBy(roundedIntPoint(accumulatedOffset));
    
    FontDescription fontDescription;
    RenderTheme::defaultTheme()->systemFont(CSSValueWebkitSmallControl, fontDescription);
    fontDescription.setWeight(FontWeightBold);
    Settings* settings = document()->settings();
    ASSERT(settings);
    if (!settings)
        return false;
    fontDescription.setRenderingMode(settings->fontRenderingMode());
    fontDescription.setComputedSize(fontDescription.specifiedSize());
    font = Font(fontDescription, 0, 0);
    font.update(0);

    run = TextRun(m_unavailablePluginReplacementText);
    textWidth = font.width(run);
    
    replacementTextRect.setSize(FloatSize(textWidth + replacementTextRoundedRectLeftRightTextMargin * 2, replacementTextRoundedRectHeight));
    float x = (contentRect.size().width() / 2 - replacementTextRect.size().width() / 2) + contentRect.location().x();
    float y = (contentRect.size().height() / 2 - replacementTextRect.size().height() / 2) + contentRect.location().y();
    replacementTextRect.setLocation(FloatPoint(x, y));
    
    path.addRoundedRect(replacementTextRect, FloatSize(replacementTextRoundedRectRadius, replacementTextRoundedRectRadius));

    return true;
}

void RenderEmbeddedObject::computeLogicalHeight()
{
    RenderPart::computeLogicalHeight();
    if (!flattenFrame())
         return;

    HTMLObjectElement* frame = static_cast<HTMLObjectElement*>(node());
    bool isScrollable = frame->scrollingMode() != ScrollbarAlwaysOff;

    if (isScrollable || !style()->height().isFixed()) {
        FrameView* view = static_cast<FrameView*>(widget());
        if (!view)
            return;
        int border = borderTop() + borderBottom();
        setHeight(max(height(), view->contentsHeight() + border));
    }
}

void RenderEmbeddedObject::computeLogicalWidth()
{
    RenderPart::computeLogicalWidth();
    if (!flattenFrame())
        return;

    HTMLObjectElement* frame = static_cast<HTMLObjectElement*>(node());
    bool isScrollable = frame->scrollingMode() != ScrollbarAlwaysOff;

    if (isScrollable || !style()->width().isFixed()) {
        FrameView* view = static_cast<FrameView*>(widget());
        if (!view)
            return;
        int border = borderLeft() + borderRight();
        setWidth(max(width(), view->contentsWidth() + border));
    }
}

bool RenderEmbeddedObject::flattenFrame()
{
    if (!node() || !node()->hasTagName(objectTag))
        return false;

    HTMLObjectElement* element = static_cast<HTMLObjectElement*>(node());
    bool isScrollable = element->scrollingMode() != ScrollbarAlwaysOff;

    if (style()->width().isFixed() && style()->height().isFixed()) {
        if (!isScrollable)
            return false;
        if (style()->width().value() <= 0 || style()->height().value() <= 0)
            return false;
    }

    Frame* frame = element->document()->frame();
    bool enabled = frame && frame->settings()->frameFlatteningEnabled();

    if (!enabled || !frame->page())
        return false;

    FrameView* view = frame->page()->mainFrame()->view();
    if (!view)
        return false;

    // Do not flatten offscreen inner frames during frame flattening, as flattening might make them visible.
    IntRect boundingRect = absoluteBoundingBoxRect();
    return boundingRect.maxX() > 0 && boundingRect.maxY() > 0;
}

void RenderEmbeddedObject::layoutWithFlattening(bool fixedWidth, bool fixedHeight)
{
    FrameView* childFrameView = static_cast<FrameView*>(widget());
    RenderView* childRoot = childFrameView ? static_cast<RenderView*>(childFrameView->frame()->contentRenderer()) : 0;

    // Do not expand frames which has zero width or height
    if (!width() || !height() || !childRoot) {
        updateWidgetPosition();
        if (childFrameView)
            childFrameView->layout();
        setNeedsLayout(false);
        return;
    }

    // need to update to calculate min/max correctly
    updateWidgetPosition();
    if (childRoot->preferredLogicalWidthsDirty())
        childRoot->computePreferredLogicalWidths();

    // if scrollbars are off, and the width or height are fixed
    // we obey them and do not expand. With frame flattening
    // no subframe much ever become scrollable.

    HTMLObjectElement* element = static_cast<HTMLObjectElement*>(node());
    bool isScrollable = element->scrollingMode() != ScrollbarAlwaysOff;

    // consider iframe inset border
    int hBorder = borderLeft() + borderRight();
    int vBorder = borderTop() + borderBottom();

    // make sure minimum preferred width is enforced
    if (isScrollable || !fixedWidth) {
        setWidth(max(width(), childRoot->minPreferredLogicalWidth() + hBorder));
        // update again to pass the new width to the child frame
        updateWidgetPosition();
        childFrameView->layout();
    }

    // expand the frame by setting frame height = content height
    if (isScrollable || !fixedHeight || childRoot->isFrameSet())
        setHeight(max(height(), childFrameView->contentsHeight() + vBorder));
    if (isScrollable || !fixedWidth || childRoot->isFrameSet())
        setWidth(max(width(), childFrameView->contentsWidth() + hBorder));

    updateWidgetPosition();

    ASSERT(!childFrameView->layoutPending());
    ASSERT(!childRoot->needsLayout());
    ASSERT(!childRoot->firstChild() || !childRoot->firstChild()->firstChild() || !childRoot->firstChild()->firstChild()->needsLayout());

    setNeedsLayout(false);
}

void RenderEmbeddedObject::layout()
{
    StackStats::LayoutCheckPoint layoutCheckPoint;
    ASSERT(needsLayout());

#if ENABLE(PLUGIN_PROXY_FOR_VIDEO)
    LayoutSize oldSize = contentBoxRect().size();
#endif

    RenderPart::computeLogicalWidth();
    RenderPart::computeLogicalHeight();

    if (flattenFrame()) {
        layoutWithFlattening(style()->width().isFixed(), style()->height().isFixed());
        return;
    }

    RenderPart::layout();

    m_overflow.clear();
    addVisualEffectOverflow();

    updateLayerTransform();

    if (!widget() && frameView())
        frameView()->addWidgetToUpdate(this);

    setNeedsLayout(false);

#if ENABLE(PLUGIN_PROXY_FOR_VIDEO)
    // This code copied from RenderMedia::layout().
    RenderBox* controlsRenderer = toRenderBox(m_children.firstChild());
    if (!controlsRenderer)
        return;
    
    LayoutSize newSize = contentBoxRect().size();
    if (newSize == oldSize && !controlsRenderer->needsLayout())
        return;
    
    // When calling layout() on a child node, a parent must either push a LayoutStateMaintainter, or
    // instantiate LayoutStateDisabler. Since using a LayoutStateMaintainer is slightly more efficient,
    // and this method will be called many times per second during playback, use a LayoutStateMaintainer:
    LayoutStateMaintainer statePusher(view(), this, locationOffset(), hasTransform() || hasReflection() || style()->isFlippedBlocksWritingMode());
    
    controlsRenderer->setLocation(LayoutPoint(borderLeft(), borderTop()) + LayoutSize(paddingLeft(), paddingTop()));
    controlsRenderer->style()->setHeight(Length(newSize.height(), Fixed));
    controlsRenderer->style()->setWidth(Length(newSize.width(), Fixed));
    controlsRenderer->setNeedsLayout(true, MarkOnlyThis);
    controlsRenderer->layout();
    setChildNeedsLayout(false);
    
    statePusher.pop();
#endif
}

void RenderEmbeddedObject::viewCleared()
{
    // This is required for <object> elements whose contents are rendered by WebCore (e.g. src="foo.html").
    if (node() && widget() && widget()->isFrameView()) {
        FrameView* view = static_cast<FrameView*>(widget());
        int marginWidth = -1;
        int marginHeight = -1;
        if (node()->hasTagName(iframeTag)) {
            HTMLIFrameElement* frame = static_cast<HTMLIFrameElement*>(node());
            marginWidth = frame->marginWidth();
            marginHeight = frame->marginHeight();
        }
        if (marginWidth != -1)
            view->setMarginWidth(marginWidth);
        if (marginHeight != -1)
            view->setMarginHeight(marginHeight);
    }
}

bool RenderEmbeddedObject::nodeAtPoint(const HitTestRequest& request, HitTestResult& result, const HitTestLocation& locationInContainer, const LayoutPoint& accumulatedOffset, HitTestAction hitTestAction)
{
    if (!RenderPart::nodeAtPoint(request, result, locationInContainer, accumulatedOffset, hitTestAction))
        return false;

    if (!widget() || !widget()->isPluginViewBase())
        return true;

    PluginViewBase* view = static_cast<PluginViewBase*>(widget());
    IntPoint roundedPoint = locationInContainer.roundedPoint();

    if (Scrollbar* horizontalScrollbar = view->horizontalScrollbar()) {
        if (horizontalScrollbar->shouldParticipateInHitTesting() && horizontalScrollbar->frameRect().contains(roundedPoint)) {
            result.setScrollbar(horizontalScrollbar);
            return true;
        }
    }

    if (Scrollbar* verticalScrollbar = view->verticalScrollbar()) {
        if (verticalScrollbar->shouldParticipateInHitTesting() && verticalScrollbar->frameRect().contains(roundedPoint)) {
            result.setScrollbar(verticalScrollbar);
            return true;
        }
    }

    return true;
}

bool RenderEmbeddedObject::scroll(ScrollDirection direction, ScrollGranularity granularity, float, Node**)
{
    if (!widget() || !widget()->isPluginViewBase())
        return false;

    return static_cast<PluginViewBase*>(widget())->scroll(direction, granularity);
}

bool RenderEmbeddedObject::logicalScroll(ScrollLogicalDirection direction, ScrollGranularity granularity, float multiplier, Node** stopNode)
{
    // Plugins don't expose a writing direction, so assuming horizontal LTR.
    return scroll(logicalToPhysical(direction, true, false), granularity, multiplier, stopNode);
}


bool RenderEmbeddedObject::isInUnavailablePluginIndicator(const LayoutPoint& point) const
{
    FloatRect contentRect;
    Path path;
    FloatRect replacementTextRect;
    Font font;
    TextRun run("");
    float textWidth;
    return getReplacementTextGeometry(IntPoint(), contentRect, path, replacementTextRect, font, run, textWidth)
        && path.contains(point);
}

bool RenderEmbeddedObject::isInUnavailablePluginIndicator(MouseEvent* event) const
{
    return isInUnavailablePluginIndicator(roundedLayoutPoint(absoluteToLocal(event->absoluteLocation(), UseTransforms)));
}

static bool shouldUnavailablePluginMessageBeButton(Document* document, RenderEmbeddedObject::PluginUnavailabilityReason pluginUnavailabilityReason)
{
    Page* page = document->page();
    return page && page->chrome()->client()->shouldUnavailablePluginMessageBeButton(pluginUnavailabilityReason);
}

void RenderEmbeddedObject::handleUnavailablePluginIndicatorEvent(Event* event)
{
    if (!shouldUnavailablePluginMessageBeButton(document(), m_pluginUnavailabilityReason))
        return;
    
    if (!event->isMouseEvent())
        return;
    
    MouseEvent* mouseEvent = static_cast<MouseEvent*>(event);
    HTMLPlugInElement* element = static_cast<HTMLPlugInElement*>(node());
    if (event->type() == eventNames().mousedownEvent && static_cast<MouseEvent*>(event)->button() == LeftButton) {
        m_mouseDownWasInUnavailablePluginIndicator = isInUnavailablePluginIndicator(mouseEvent);
        if (m_mouseDownWasInUnavailablePluginIndicator) {
            if (Frame* frame = document()->frame()) {
                frame->eventHandler()->setCapturingMouseEventsNode(element);
                element->setIsCapturingMouseEvents(true);
            }
            setUnavailablePluginIndicatorIsPressed(true);
        }
        event->setDefaultHandled();
    }        
    if (event->type() == eventNames().mouseupEvent && static_cast<MouseEvent*>(event)->button() == LeftButton) {
        if (m_unavailablePluginIndicatorIsPressed) {
            if (Frame* frame = document()->frame()) {
                frame->eventHandler()->setCapturingMouseEventsNode(0);
                element->setIsCapturingMouseEvents(false);
            }
            setUnavailablePluginIndicatorIsPressed(false);
        }
        if (m_mouseDownWasInUnavailablePluginIndicator && isInUnavailablePluginIndicator(mouseEvent)) {
            if (Page* page = document()->page())
                page->chrome()->client()->unavailablePluginButtonClicked(element, m_pluginUnavailabilityReason);
        }
        m_mouseDownWasInUnavailablePluginIndicator = false;
        event->setDefaultHandled();
    }
    if (event->type() == eventNames().mousemoveEvent) {
        setUnavailablePluginIndicatorIsPressed(m_mouseDownWasInUnavailablePluginIndicator && isInUnavailablePluginIndicator(mouseEvent));
        event->setDefaultHandled();
    }
}

CursorDirective RenderEmbeddedObject::getCursor(const LayoutPoint& point, Cursor& cursor) const
{
    if (showsUnavailablePluginIndicator() && shouldUnavailablePluginMessageBeButton(document(), m_pluginUnavailabilityReason) && isInUnavailablePluginIndicator(point)) {
        cursor = handCursor();
        return SetCursor;
    }
    return RenderPart::getCursor(point, cursor);
}

}
