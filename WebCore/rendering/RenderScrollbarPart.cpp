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
#include "RenderScrollbarPart.h"
#include "RenderScrollbar.h"
#include "RenderScrollbarTheme.h"

using namespace std;

namespace WebCore {

RenderScrollbarPart::RenderScrollbarPart(Node* node, RenderScrollbar* scrollbar, ScrollbarPart part)
    : RenderBlock(node)
    , m_scrollbar(scrollbar)
    , m_part(part)
{
}

RenderScrollbarPart::~RenderScrollbarPart()
{
}

void RenderScrollbarPart::layout()
{
    setPos(0, 0); // We don't worry about positioning ourselves.  We're just determining our minimum width/height.
    if (m_scrollbar->orientation() == HorizontalScrollbar)
        layoutHorizontalPart();
    else
        layoutVerticalPart();

    m_overflowWidth = max(m_width, m_overflowWidth);
    m_overflowHeight = max(m_height, m_overflowHeight);
    
    setNeedsLayout(false);
}

void RenderScrollbarPart::layoutHorizontalPart()
{
    if (m_part == ScrollbarBGPart) {
        m_width = m_scrollbar->width();
        computeScrollbarHeight();
    } else {
        computeScrollbarWidth();
        m_height = m_scrollbar->height();
    }
}

void RenderScrollbarPart::layoutVerticalPart()
{
    if (m_part == ScrollbarBGPart) {
        computeScrollbarWidth();
        m_height = m_scrollbar->height();
    } else {
        m_width = m_scrollbar->width();
        computeScrollbarHeight();
    } 
}

static int calcScrollbarThicknessUsing(const Length& l, int containingLength)
{
    if (l.isIntrinsicOrAuto())
        return ScrollbarTheme::nativeTheme()->scrollbarThickness();
    return l.calcMinValue(containingLength);
}

void RenderScrollbarPart::computeScrollbarWidth()
{
    int visibleSize = m_scrollbar->owningRenderer()->width() - m_scrollbar->owningRenderer()->borderLeft() - m_scrollbar->owningRenderer()->borderRight();
    int width = calcScrollbarThicknessUsing(style()->width(), visibleSize);
    int minWidth = calcScrollbarThicknessUsing(style()->minWidth(), visibleSize);
    int maxWidth = style()->maxWidth().isUndefined() ? width : calcScrollbarThicknessUsing(style()->maxWidth(), visibleSize);
    m_width = max(minWidth, min(maxWidth, width));
    
    // Allow the track pieces to have negative margins so that they can overlap buttons. This is required to emulate the
    // Aqua look in CSS.
    if (m_part == TrackBGPart) {
        m_marginLeft = min(0, style()->marginLeft().calcMinValue(visibleSize));
        m_marginRight = min(0, style()->marginRight().calcMinValue(visibleSize));
    }
}

void RenderScrollbarPart::computeScrollbarHeight()
{
    int visibleSize = m_scrollbar->owningRenderer()->height() -  m_scrollbar->owningRenderer()->borderTop() - m_scrollbar->owningRenderer()->borderBottom();
    int height = calcScrollbarThicknessUsing(style()->height(), visibleSize);
    int minHeight = calcScrollbarThicknessUsing(style()->minHeight(), visibleSize);
    int maxHeight = style()->maxHeight().isUndefined() ? height : calcScrollbarThicknessUsing(style()->maxHeight(), visibleSize);
    m_height = max(minHeight, min(maxHeight, height));

    // Allow the track pieces to have negative margins so that they can overlap buttons. This is required to emulate the
    // Aqua look in CSS.
    if (m_part == TrackBGPart) {
        m_marginTop = min(0, style()->marginTop().calcMinValue(visibleSize));
        m_marginBottom = min(0, style()->marginBottom().calcMinValue(visibleSize));
    }
}

void RenderScrollbarPart::calcPrefWidths()
{
    if (!prefWidthsDirty())
        return;
    
    m_minPrefWidth = m_maxPrefWidth = 0;

    setPrefWidthsDirty(false);
}

void RenderScrollbarPart::styleDidChange(RenderStyle::Diff diff, const RenderStyle* oldStyle)
{
    RenderBlock::styleDidChange(diff, oldStyle);
    setInline(false);
    setPositioned(false);
    setFloating(false);
    setHasOverflowClip(false);
    if (oldStyle && m_scrollbar && m_part != NoPart)
        m_scrollbar->theme()->invalidatePart(m_scrollbar, m_part);
}

void RenderScrollbarPart::imageChanged(WrappedImagePtr)
{
    if (m_scrollbar && m_part != NoPart)
        m_scrollbar->theme()->invalidatePart(m_scrollbar, m_part);
}

void RenderScrollbarPart::paintIntoRect(GraphicsContext* graphicsContext, int tx, int ty, const IntRect& rect)
{
    // Make sure our dimensions match the rect.
    setPos(rect.x() - tx, rect.y() - ty);
    setWidth(rect.width());
    setHeight(rect.height());
    setOverflowWidth(max(rect.width(), overflowWidth()));
    setOverflowHeight(max(rect.height(), overflowHeight()));

    // Now do the paint.
    RenderObject::PaintInfo paintInfo(graphicsContext, rect, PaintPhaseBlockBackground, false, 0, 0);
    paint(paintInfo, tx, ty);
    paintInfo.phase = PaintPhaseChildBlockBackgrounds;
    paint(paintInfo, tx, ty);
    paintInfo.phase = PaintPhaseFloat;
    paint(paintInfo, tx, ty);
    paintInfo.phase = PaintPhaseForeground;
    paint(paintInfo, tx, ty);
    paintInfo.phase = PaintPhaseOutline;
    paint(paintInfo, tx, ty);
}

}
