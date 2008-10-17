/*
 * Copyright (C) 2008 Apple Inc. All Rights Reserved.
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
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */

#include "config.h"
#include "RenderScrollbar.h"
#include "RenderScrollbarPart.h"
#include "RenderScrollbarTheme.h"

namespace WebCore {

PassRefPtr<Scrollbar> RenderScrollbar::createCustomScrollbar(ScrollbarClient* client, ScrollbarOrientation orientation, RenderObject* renderer)
{
    return adoptRef(new RenderScrollbar(client, orientation, renderer));
}

RenderScrollbar::RenderScrollbar(ScrollbarClient* client, ScrollbarOrientation orientation, RenderObject* renderer)
    : Scrollbar(client, orientation, RegularScrollbar, RenderScrollbarTheme::renderScrollbarTheme())
    , m_owner(renderer)
{
}

RenderScrollbar::~RenderScrollbar()
{
    ASSERT(m_parts.isEmpty());
}

void RenderScrollbar::setParent(ScrollView* parent)
{
    Scrollbar::setParent(parent);
    if (!parent) {
        // Destroy all of the scrollbar's RenderObjects.
        updateScrollbarParts(true);
    }
}

void RenderScrollbar::setEnabled(bool e)
{
    bool wasEnabled = enabled();
    Scrollbar::setEnabled(e);
    if (wasEnabled != e)
        updateScrollbarParts();
}

void RenderScrollbar::styleChanged()
{
    updateScrollbarParts();
}

void RenderScrollbar::paint(GraphicsContext* context, const IntRect& damageRect)
{
    if (context->updatingControlTints()) {
        updateScrollbarParts();
        return;
    }
    Scrollbar::paint(context, damageRect);
}

void RenderScrollbar::setHoveredPart(ScrollbarPart part)
{
    if (part == m_hoveredPart)
        return;

    ScrollbarPart oldPart = m_hoveredPart;
    m_hoveredPart = part;

    updateScrollbarPart(oldPart);
    updateScrollbarPart(m_hoveredPart);

    updateScrollbarPart(ScrollbarBGPart);
    updateScrollbarPart(TrackBGPart);
}

void RenderScrollbar::setPressedPart(ScrollbarPart part)
{
    ScrollbarPart oldPart = m_pressedPart;
    Scrollbar::setPressedPart(part);
    
    updateScrollbarPart(oldPart);
    updateScrollbarPart(part);
    
    updateScrollbarPart(ScrollbarBGPart);
    updateScrollbarPart(TrackBGPart);
}

static ScrollbarPart s_styleResolvePart;
static RenderScrollbar* s_styleResolveScrollbar;

RenderScrollbar* RenderScrollbar::scrollbarForStyleResolve()
{
    return s_styleResolveScrollbar;
}

ScrollbarPart RenderScrollbar::partForStyleResolve()
{
    return s_styleResolvePart;
}

PassRefPtr<RenderStyle> RenderScrollbar::getScrollbarPseudoStyle(ScrollbarPart partType, RenderStyle::PseudoId pseudoId)
{
    s_styleResolvePart = partType;
    s_styleResolveScrollbar = this;
    RefPtr<RenderStyle> result = m_owner->getUncachedPseudoStyle(pseudoId, m_owner->style());
    s_styleResolvePart = NoPart;
    s_styleResolveScrollbar = 0;
    return result;
}

void RenderScrollbar::updateScrollbarParts(bool destroy)
{
    updateScrollbarPart(ScrollbarBGPart, destroy);
    updateScrollbarPart(BackButtonStartPart, destroy);
    updateScrollbarPart(ForwardButtonStartPart, destroy);
    updateScrollbarPart(BackTrackPart, destroy);
    updateScrollbarPart(ThumbPart, destroy);
    updateScrollbarPart(ForwardTrackPart, destroy);
    updateScrollbarPart(BackButtonEndPart, destroy);
    updateScrollbarPart(ForwardButtonEndPart, destroy);
    updateScrollbarPart(TrackBGPart, destroy);
    
    if (destroy)
        return;

    // See if the scrollbar's thickness changed.  If so, we need to mark our owning object as needing a layout.
    bool isHorizontal = orientation() == HorizontalScrollbar;    
    int oldThickness = isHorizontal ? height() : width();
    int newThickness = 0;
    RenderScrollbarPart* part = m_parts.get(ScrollbarBGPart);
    if (part) {
        part->layout();
        newThickness = isHorizontal ? part->height() : part->width();
    }
    
    if (newThickness != oldThickness) {
        setFrameRect(IntRect(x(), y(), isHorizontal ? width() : newThickness, isHorizontal ? newThickness : height()));
        m_owner->setChildNeedsLayout(true);
    }
}

static RenderStyle::PseudoId pseudoForScrollbarPart(ScrollbarPart part)
{
    switch (part) {
        case BackButtonStartPart:
        case ForwardButtonStartPart:
        case BackButtonEndPart:
        case ForwardButtonEndPart:
            return RenderStyle::SCROLLBAR_BUTTON;
        case BackTrackPart:
        case ForwardTrackPart:
            return RenderStyle::SCROLLBAR_TRACK_PIECE;
        case ThumbPart:
            return RenderStyle::SCROLLBAR_THUMB;
        case TrackBGPart:
            return RenderStyle::SCROLLBAR_TRACK;
        default:
            return RenderStyle::SCROLLBAR;
    }
}

void RenderScrollbar::updateScrollbarPart(ScrollbarPart partType, bool destroy)
{
    if (partType == NoPart)
        return;

    RefPtr<RenderStyle> partStyle = !destroy ? getScrollbarPseudoStyle(partType,  pseudoForScrollbarPart(partType)) : 0;
    
    bool needRenderer = !destroy && partStyle && partStyle->display() != NONE && partStyle->visibility() == VISIBLE;
    
    if (needRenderer && partStyle->display() != BLOCK) {
        // See if we are a button that should not be visible according to OS settings.
        ScrollbarButtonsPlacement buttonsPlacement = theme()->buttonsPlacement();
        switch (partType) {
            case BackButtonStartPart:
                needRenderer = (buttonsPlacement == ScrollbarButtonsSingle || buttonsPlacement == ScrollbarButtonsDoubleStart ||
                                buttonsPlacement == ScrollbarButtonsDoubleBoth);
                break;
            case ForwardButtonStartPart:
                needRenderer = (buttonsPlacement == ScrollbarButtonsDoubleStart || buttonsPlacement == ScrollbarButtonsDoubleBoth);
                break;
            case BackButtonEndPart:
                needRenderer = (buttonsPlacement == ScrollbarButtonsDoubleEnd || buttonsPlacement == ScrollbarButtonsDoubleBoth);
                break;
            case ForwardButtonEndPart:
                needRenderer = (buttonsPlacement == ScrollbarButtonsSingle || buttonsPlacement == ScrollbarButtonsDoubleEnd ||
                                buttonsPlacement == ScrollbarButtonsDoubleBoth);
                break;
            default:
                break;
        }
    }
    
    RenderScrollbarPart* partRenderer = m_parts.get(partType);
    if (!partRenderer && needRenderer) {
        partRenderer = new (m_owner->renderArena()) RenderScrollbarPart(m_owner->document(), this, partType);
        m_parts.set(partType, partRenderer);
    } else if (partRenderer && !needRenderer) {
        m_parts.remove(partType);
        partRenderer->destroy();
        partRenderer = 0;
    }
    
    if (partRenderer)
        partRenderer->setStyle(partStyle.release());
}

void RenderScrollbar::paintPart(GraphicsContext* graphicsContext, ScrollbarPart partType, const IntRect& rect)
{
    RenderScrollbarPart* partRenderer = m_parts.get(partType);
    if (!partRenderer)
        return;
    partRenderer->paintIntoRect(graphicsContext, x(), y(), rect);
}

IntRect RenderScrollbar::buttonRect(ScrollbarPart partType)
{
    RenderScrollbarPart* partRenderer = m_parts.get(partType);
    if (!partRenderer)
        return IntRect();
        
    partRenderer->layout();
    
    bool isHorizontal = orientation() == HorizontalScrollbar;
    if (partType == BackButtonStartPart)
        return IntRect(x(), y(), isHorizontal ? partRenderer->width() : width(), isHorizontal ? height() : partRenderer->height());
    if (partType == ForwardButtonEndPart)
        return IntRect(isHorizontal ? x() + width() - partRenderer->width() : x(),
        
                       isHorizontal ? y() : y() + height() - partRenderer->height(),
                       isHorizontal ? partRenderer->width() : width(),
                       isHorizontal ? height() : partRenderer->height());
    
    if (partType == ForwardButtonStartPart) {
        IntRect previousButton = buttonRect(BackButtonStartPart);
        return IntRect(isHorizontal ? x() + previousButton.width() : x(),
                       isHorizontal ? y() : y() + previousButton.height(),
                       isHorizontal ? partRenderer->width() : width(),
                       isHorizontal ? height() : partRenderer->height());
    }
    
    IntRect followingButton = buttonRect(ForwardButtonEndPart);
    return IntRect(isHorizontal ? x() + width() - followingButton.width() - partRenderer->width() : x(),
                   isHorizontal ? y() : y() + height() - followingButton.height() - partRenderer->height(),
                   isHorizontal ? partRenderer->width() : width(),
                   isHorizontal ? height() : partRenderer->height());
}

IntRect RenderScrollbar::trackRect(int startLength, int endLength)
{
    RenderScrollbarPart* part = m_parts.get(TrackBGPart);
    if (part)
        part->layout();

    if (orientation() == HorizontalScrollbar) {
        int marginLeft = part ? part->marginLeft() : 0;
        int marginRight = part ? part->marginRight() : 0;
        startLength += marginLeft;
        endLength += marginRight;
        int totalLength = startLength + endLength;
        return IntRect(x() + startLength, y(), width() - totalLength, height());
    }
    
    int marginTop = part ? part->marginTop() : 0;
    int marginBottom = part ? part->marginBottom() : 0;
    startLength += marginTop;
    endLength += marginBottom;
    int totalLength = startLength + endLength;

    return IntRect(x(), y() + startLength, width(), height() - totalLength);
}

IntRect RenderScrollbar::trackPieceRectWithMargins(ScrollbarPart partType, const IntRect& oldRect)
{
    RenderScrollbarPart* partRenderer = m_parts.get(partType);
    if (!partRenderer)
        return oldRect;
    
    partRenderer->layout();
    
    IntRect rect = oldRect;
    if (orientation() == HorizontalScrollbar) {
        rect.setX(rect.x() + partRenderer->marginLeft());
        rect.setWidth(rect.width() - (partRenderer->marginLeft() + partRenderer->marginRight()));
    } else {
        rect.setY(rect.y() + partRenderer->marginTop());
        rect.setHeight(rect.height() - (partRenderer->marginTop() + partRenderer->marginBottom()));
    }
    return rect;
}

int RenderScrollbar::minimumThumbLength()
{
    RenderScrollbarPart* partRenderer = m_parts.get(ThumbPart);
    if (!partRenderer)
        return 0;    
    partRenderer->layout();
    return orientation() == HorizontalScrollbar ? partRenderer->width() : partRenderer->height();
}

}
