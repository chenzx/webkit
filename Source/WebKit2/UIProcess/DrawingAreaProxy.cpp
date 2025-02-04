/*
 * Copyright (C) 2010 Apple Inc. All rights reserved.
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
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"
#include "DrawingAreaProxy.h"

#include "WebPageProxy.h"

#if USE(COORDINATED_GRAPHICS)
#include "CoordinatedLayerTreeHostProxy.h"
#include <CoreIPC/MessageID.h>
#endif

using namespace WebCore;

namespace WebKit {

DrawingAreaProxy::DrawingAreaProxy(DrawingAreaType type, WebPageProxy* webPageProxy)
    : m_type(type)
    , m_webPageProxy(webPageProxy)
    , m_size(webPageProxy->viewSize())
{
}

DrawingAreaProxy::~DrawingAreaProxy()
{
}

void DrawingAreaProxy::setSize(const IntSize& size, const IntSize& scrollOffset)
{ 
    if (m_size == size && scrollOffset.isZero())
        return;

    m_size = size;
    m_scrollOffset += scrollOffset;
    sizeDidChange();
}

#if USE(COORDINATED_GRAPHICS)
void DrawingAreaProxy::updateViewport()
{
    m_webPageProxy->setViewNeedsDisplay(viewportVisibleRect());
}

WebCore::IntRect DrawingAreaProxy::contentsRect() const
{
    return IntRect(IntPoint::zero(), m_webPageProxy->viewSize());
}

void DrawingAreaProxy::didReceiveCoordinatedLayerTreeHostProxyMessage(CoreIPC::Connection*, CoreIPC::MessageID, CoreIPC::MessageDecoder&)
{
}
#endif

} // namespace WebKit
