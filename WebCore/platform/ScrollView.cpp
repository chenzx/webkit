/*
 * Copyright (C) 2006, 2007, 2008 Apple Inc. All rights reserved.
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
#include "ScrollView.h"

#include "GraphicsContext.h"
#include "HostWindow.h"
#include "PlatformMouseEvent.h"
#include "PlatformWheelEvent.h"
#include "Scrollbar.h"
#include "ScrollbarTheme.h"

using std::max;

namespace WebCore {

void ScrollView::init()
{
    m_canBlitOnScroll = true;
    m_horizontalScrollbarMode = m_verticalScrollbarMode = ScrollbarAuto;
    if (platformWidget())
        platformSetCanBlitOnScroll();
    m_scrollbarsAvoidingResizer = 0;
    m_scrollbarsSuppressed = false;
    m_drawPanScrollIcon = false;
}

void ScrollView::addChild(Widget* child) 
{
    ASSERT(child != this && !child->parent());
    child->setParent(this);
    m_children.add(child);
    if (!child->platformWidget()) {
        child->setContainingWindow(containingWindow());
        return;
    }
    platformAddChild(child);
}

void ScrollView::removeChild(Widget* child)
{
    ASSERT(child->parent() == this);
    child->setParent(0);
    m_children.remove(child);
    if (child->platformWidget())
        platformRemoveChild(child);
}

void ScrollView::setScrollbarModes(ScrollbarMode horizontalMode, ScrollbarMode verticalMode)
{
    if (horizontalMode == horizontalScrollbarMode() && verticalMode == verticalScrollbarMode())
        return;
    m_horizontalScrollbarMode = horizontalMode;
    m_verticalScrollbarMode = verticalMode;
    if (platformWidget())
        platformSetScrollbarModes();
    else
        updateScrollbars(scrollOffset());
}

void ScrollView::scrollbarModes(ScrollbarMode& horizontalMode, ScrollbarMode& verticalMode) const
{
    if (platformWidget()) {
        platformScrollbarModes(horizontalMode, verticalMode);
        return;
    }
    horizontalMode = m_horizontalScrollbarMode;
    verticalMode = m_verticalScrollbarMode;
}

void ScrollView::setCanHaveScrollbars(bool canScroll)
{
    ScrollbarMode newHorizontalMode;
    ScrollbarMode newVerticalMode;
    
    scrollbarModes(newHorizontalMode, newVerticalMode);
    
    if (canScroll && newVerticalMode == ScrollbarAlwaysOff)
        newVerticalMode = ScrollbarAuto;
    else if (!canScroll)
        newVerticalMode = ScrollbarAlwaysOff;
    
    if (canScroll && newHorizontalMode == ScrollbarAlwaysOff)
        newHorizontalMode = ScrollbarAuto;
    else if (!canScroll)
        newHorizontalMode = ScrollbarAlwaysOff;
    
    setScrollbarModes(newHorizontalMode, newVerticalMode);
}

void ScrollView::setCanBlitOnScroll(bool b)
{
    if (m_canBlitOnScroll == b)
        return;
    m_canBlitOnScroll = b;
    if (platformWidget())
        platformSetCanBlitOnScroll();
}

IntRect ScrollView::visibleContentRect(bool includeScrollbars) const
{
    if (platformWidget())
        return platformVisibleContentRect(includeScrollbars);
    return IntRect(IntPoint(m_scrollOffset.width(), m_scrollOffset.height()),
                   IntSize(max(0, width() - (verticalScrollbar() && !includeScrollbars ? verticalScrollbar()->width() : 0)), 
                           max(0, height() - (horizontalScrollbar() && !includeScrollbars ? horizontalScrollbar()->height() : 0))));
}

IntSize ScrollView::contentsSize() const
{
    if (platformWidget())
        return platformContentsSize();
    return m_contentsSize;
}

void ScrollView::setContentsSize(const IntSize& newSize)
{
    if (contentsSize() == newSize)
        return;
    m_contentsSize = newSize;
    if (platformWidget())
        platformSetContentsSize();
    else
        updateScrollbars(scrollOffset());
}

IntPoint ScrollView::maximumScrollPosition() const
{
    IntSize maximumOffset = contentsSize() - visibleContentRect().size();
    maximumOffset.clampNegativeToZero();
    return IntPoint(maximumOffset.width(), maximumOffset.height());
}

void ScrollView::scrollRectIntoViewRecursively(const IntRect& r)
{
    IntPoint p(max(0, r.x()), max(0, r.y()));
    ScrollView* view = this;
    while (view) {
        view->setScrollPosition(p);
        p.move(view->x() - view->scrollOffset().width(), view->y() - view->scrollOffset().height());
        view = view->parent();
    }
}

void ScrollView::setScrollPosition(const IntPoint& scrollPoint)
{
    if (platformWidget()) {
        platformSetScrollPosition(scrollPoint);
        return;
    }

    IntPoint newScrollPosition = scrollPoint.shrunkTo(maximumScrollPosition());
    newScrollPosition.clampNegativeToZero();

    if (newScrollPosition == scrollPosition())
        return;

    updateScrollbars(IntSize(newScrollPosition.x(), newScrollPosition.y()));
}

bool ScrollView::scroll(ScrollDirection direction, ScrollGranularity granularity)
{
    if (platformWidget())
        return platformScroll(direction, granularity);

    if (direction == ScrollUp || direction == ScrollDown) {
        if (m_verticalScrollbar)
            return m_verticalScrollbar->scroll(direction, granularity);
    } else {
        if (m_horizontalScrollbar)
            return m_horizontalScrollbar->scroll(direction, granularity);
    }
    return false;
}

IntPoint ScrollView::windowToContents(const IntPoint& windowPoint) const
{
    IntPoint viewPoint = convertFromContainingWindow(windowPoint);
    return viewPoint + scrollOffset();
}

IntPoint ScrollView::contentsToWindow(const IntPoint& contentsPoint) const
{
    IntPoint viewPoint = contentsPoint - scrollOffset();
    return convertToContainingWindow(viewPoint);  
}

IntRect ScrollView::windowToContents(const IntRect& windowRect) const
{
    IntRect viewRect = convertFromContainingWindow(windowRect);
    viewRect.move(scrollOffset());
    return viewRect;
}

IntRect ScrollView::contentsToWindow(const IntRect& contentsRect) const
{
    IntRect viewRect = contentsRect;
    viewRect.move(-scrollOffset());
    return convertToContainingWindow(viewRect);
}

IntRect ScrollView::contentsToScreen(const IntRect& rect) const
{
    if (platformWidget())
        return platformContentsToScreen(rect);
    return hostWindow()->windowToScreen(contentsToWindow(rect));
}

IntPoint ScrollView::screenToContents(const IntPoint& point) const
{
    if (platformWidget())
        return platformScreenToContents(point);
    return windowToContents(hostWindow()->screenToWindow(point));
}

bool ScrollView::containsScrollbarsAvoidingResizer() const
{
    return !m_scrollbarsAvoidingResizer;
}

void ScrollView::adjustScrollbarsAvoidingResizerCount(int overlapDelta)
{
    int oldCount = m_scrollbarsAvoidingResizer;
    m_scrollbarsAvoidingResizer += overlapDelta;
    if (parent())
        parent()->adjustScrollbarsAvoidingResizerCount(overlapDelta);
    else if (!scrollbarsSuppressed()) {
        // If we went from n to 0 or from 0 to n and we're the outermost view,
        // we need to invalidate the windowResizerRect(), since it will now need to paint
        // differently.
        if (oldCount > 0 && m_scrollbarsAvoidingResizer == 0 ||
            oldCount == 0 && m_scrollbarsAvoidingResizer > 0)
            invalidateRect(windowResizerRect());
    }
}

void ScrollView::setParent(ScrollView* parentView)
{
    if (parentView == parent())
        return;

    if (m_scrollbarsAvoidingResizer && parent())
        parent()->adjustScrollbarsAvoidingResizerCount(-m_scrollbarsAvoidingResizer);

    Widget::setParent(parentView);
    
    if (m_scrollbarsAvoidingResizer && parent())
        parent()->adjustScrollbarsAvoidingResizerCount(m_scrollbarsAvoidingResizer);
}

void ScrollView::setScrollbarsSuppressed(bool suppressed, bool repaintOnUnsuppress)
{
    if (suppressed == m_scrollbarsSuppressed)
        return;

    m_scrollbarsSuppressed = suppressed;

    if (platformWidget())
        platformSetScrollbarsSuppressed(repaintOnUnsuppress);
    else if (repaintOnUnsuppress && !suppressed) {
        if (m_horizontalScrollbar)
            m_horizontalScrollbar->invalidate();
        if (m_verticalScrollbar)
            m_verticalScrollbar->invalidate();

        // Invalidate the scroll corner too on unsuppress.
        IntRect hCorner;
        if (m_horizontalScrollbar && width() - m_horizontalScrollbar->width() > 0) {
            hCorner = IntRect(m_horizontalScrollbar->width(),
                              height() - m_horizontalScrollbar->height(),
                              width() - m_horizontalScrollbar->width(),
                              m_horizontalScrollbar->height());
            invalidateRect(hCorner);
        }

        if (m_verticalScrollbar && height() - m_verticalScrollbar->height() > 0) {
            IntRect vCorner(width() - m_verticalScrollbar->width(),
                            m_verticalScrollbar->height(),
                            m_verticalScrollbar->width(),
                            height() - m_verticalScrollbar->height());
            if (vCorner != hCorner)
                invalidateRect(vCorner);
        }
    }
}

Scrollbar* ScrollView::scrollbarUnderMouse(const PlatformMouseEvent& mouseEvent)
{
    if (platformWidget())
        return 0;

    IntPoint viewPoint = convertFromContainingWindow(mouseEvent.pos());
    if (m_horizontalScrollbar && m_horizontalScrollbar->frameRect().contains(viewPoint))
        return m_horizontalScrollbar.get();
    if (m_verticalScrollbar && m_verticalScrollbar->frameRect().contains(viewPoint))
        return m_verticalScrollbar.get();
    return 0;
}

void ScrollView::wheelEvent(PlatformWheelEvent& e)
{
    // We don't allow mouse wheeling to happen in a ScrollView that has had its scrollbars explicitly disabled.
    if (!canHaveScrollbars() || platformWidget())
        return;

    // Determine how much we want to scroll.  If we can move at all, we will accept the event.
    IntSize maxScrollDelta = maximumScrollPosition() - scrollPosition();
    if ((e.deltaX() < 0 && maxScrollDelta.width() > 0) ||
        (e.deltaX() > 0 && scrollOffset().width() > 0) ||
        (e.deltaY() < 0 && maxScrollDelta.height() > 0) ||
        (e.deltaY() > 0 && scrollOffset().height() > 0)) {
        e.accept();
        float deltaX = e.deltaX();
        float deltaY = e.deltaY();
        if (e.granularity() == ScrollByLineWheelEvent) {
            deltaX *= cMouseWheelPixelsPerLineStep;
            deltaY *= cMouseWheelPixelsPerLineStep;
        } else if (e.granularity() == ScrollByPageWheelEvent) {
            ASSERT(deltaX == 0);
            bool negative = deltaY < 0;
            deltaY = max(0, visibleHeight() - cAmountToKeepWhenPaging);
            if (negative)
                deltaY = -deltaY;
        }
        scrollBy(IntSize(-deltaX, -deltaY));
    }
}

void ScrollView::setFrameRect(const IntRect& newRect)
{
    IntRect oldRect = frameRect();
    
    if (newRect == oldRect)
        return;

    Widget::setFrameRect(newRect);

    if (platformWidget())
        return;
    
    if (newRect.width() != oldRect.width() || newRect.height() != oldRect.height()) {
        updateScrollbars(m_scrollOffset);
        contentsResized();
    }

    frameRectsChanged();
}

void ScrollView::frameRectsChanged() const
{
    if (platformWidget())
        return;

    HashSet<Widget*>::const_iterator end = m_children.end();
    for (HashSet<Widget*>::const_iterator current = m_children.begin(); current != end; ++current)
        (*current)->frameRectsChanged();
}

void ScrollView::repaintContentRectangle(const IntRect& rect, bool now)
{
    if (rect.isEmpty())
        return;

    if (platformWidget()) {
        platformRepaintContentRectangle(rect, now);
        return;
    }

    hostWindow()->repaint(contentsToWindow(rect), true, now);
}

void ScrollView::paint(GraphicsContext* context, const IntRect& rect)
{
    if (platformWidget()) {
        Widget::paint(context, rect);
        return;
    }

    if (context->paintingDisabled() && !context->updatingControlTints())
        return;

    IntRect documentDirtyRect = rect;
    documentDirtyRect.intersect(frameRect());

    context->save();

    context->translate(x(), y());
    documentDirtyRect.move(-x(), -y());

    context->translate(-scrollX(), -scrollY());
    documentDirtyRect.move(scrollX(), scrollY());

    context->clip(visibleContentRect());

    paintContents(context, documentDirtyRect);

    context->restore();

    // Now paint the scrollbars.
    if (!m_scrollbarsSuppressed && (m_horizontalScrollbar || m_verticalScrollbar)) {
        context->save();
        IntRect scrollViewDirtyRect = rect;
        scrollViewDirtyRect.intersect(frameRect());
        context->translate(x(), y());
        scrollViewDirtyRect.move(-x(), -y());
        if (m_horizontalScrollbar)
            m_horizontalScrollbar->paint(context, scrollViewDirtyRect);
        if (m_verticalScrollbar)
            m_verticalScrollbar->paint(context, scrollViewDirtyRect);

        IntRect hCorner;
        if (m_horizontalScrollbar && width() - m_horizontalScrollbar->width() > 0) {
            hCorner = IntRect(m_horizontalScrollbar->width(),
                              height() - m_horizontalScrollbar->height(),
                              width() - m_horizontalScrollbar->width(),
                              m_horizontalScrollbar->height());
            if (hCorner.intersects(scrollViewDirtyRect))
                ScrollbarTheme::nativeTheme()->paintScrollCorner(this, context, hCorner);
        }

        if (m_verticalScrollbar && height() - m_verticalScrollbar->height() > 0) {
            IntRect vCorner(width() - m_verticalScrollbar->width(),
                            m_verticalScrollbar->height(),
                            m_verticalScrollbar->width(),
                            height() - m_verticalScrollbar->height());
            if (vCorner != hCorner && vCorner.intersects(scrollViewDirtyRect))
                ScrollbarTheme::nativeTheme()->paintScrollCorner(this, context, vCorner);
        }

        context->restore();
    }

    // Paint the panScroll Icon
    static RefPtr<Image> panScrollIcon;
    if (m_drawPanScrollIcon) {
        if (!panScrollIcon)
            panScrollIcon = Image::loadPlatformResource("panIcon");
        context->drawImage(panScrollIcon.get(), m_panScrollIconPoint);
    }
}

void ScrollView::setParentVisible(bool visible)
{
    if (isParentVisible() == visible)
        return;
    
    Widget::setParentVisible(visible);

    if (!isVisible())
        return;
        
    HashSet<Widget*>::iterator end = m_children.end();
    for (HashSet<Widget*>::iterator it = m_children.begin(); it != end; ++it)
        (*it)->setParentVisible(visible);
}

void ScrollView::show()
{
    if (!isSelfVisible()) {
        setSelfVisible(true);
        if (isParentVisible()) {
            HashSet<Widget*>::iterator end = m_children.end();
            for (HashSet<Widget*>::iterator it = m_children.begin(); it != end; ++it)
                (*it)->setParentVisible(true);
        }
    }

    Widget::show();
}

void ScrollView::hide()
{
    if (isSelfVisible()) {
        if (isParentVisible()) {
            HashSet<Widget*>::iterator end = m_children.end();
            for (HashSet<Widget*>::iterator it = m_children.begin(); it != end; ++it)
                (*it)->setParentVisible(false);
        }
        setSelfVisible(false);
    }

    Widget::hide();
}

bool ScrollView::isOffscreen() const
{
    if (platformWidget())
        return platformIsOffscreen();
    
    if (!isVisible())
        return true;
    
    // FIXME: Add a HostWindow::isOffscreen method here.  Since only Mac implements this method
    // currently, we can add the method when the other platforms decide to implement this concept.
    return false;
}

#if !PLATFORM(MAC)
void ScrollView::platformSetCanBlitOnScroll()
{
}

void ScrollView::platformSetScrollbarsSuppressed(bool repaintOnUnsuppress)
{
}
#endif

#if !PLATFORM(MAC) && !PLATFORM(WX)
void ScrollView::platformSetScrollbarModes()
{
}

void ScrollView::platformScrollbarModes(ScrollbarMode& horizontal, ScrollbarMode& vertical) const
{
}

IntRect ScrollView::platformVisibleContentRect(bool) const
{
    return IntRect();
}

IntSize ScrollView::platformContentsSize() const
{
    return IntSize();
}

void ScrollView::platformSetContentsSize()
{
}

IntRect ScrollView::platformContentsToScreen(const IntRect& rect) const
{
    return rect;
}

IntPoint ScrollView::platformScreenToContents(const IntPoint& point) const
{
    return point;
}

void ScrollView::platformSetScrollPosition(const IntPoint&)
{
}

bool ScrollView::platformScroll(ScrollDirection, ScrollGranularity)
{
    return true;
}

void ScrollView::platformRepaintContentRectangle(const IntRect&, bool now)
{
}

bool ScrollView::platformIsOffscreen() const
{
    return false;
}
#endif

}

