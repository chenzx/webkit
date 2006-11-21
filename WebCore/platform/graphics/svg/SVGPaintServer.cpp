/*
 * Copyright (C) 2006 Nikolas Zimmermann <zimmermann@kde.org>
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

#ifdef SVG_SUPPORT
#include "SVGPaintServer.h"

namespace WebCore {

SVGPaintServer::SVGPaintServer()
    : m_activeClient(0)
    , m_paintingText(false)
{
}

SVGPaintServer::~SVGPaintServer()
{
}

const RenderPath* SVGPaintServer::activeClient() const
{
    return m_activeClient;
}

void SVGPaintServer::setActiveClient(const RenderPath* client)
{
    m_activeClient = client;
}

bool SVGPaintServer::isPaintingText() const
{
    return m_paintingText;
}

void SVGPaintServer::setPaintingText(bool paintingText)
{
    m_paintingText = paintingText;
}

TextStream& operator<<(TextStream& ts, const SVGPaintServer& paintServer)
{
    return paintServer.externalRepresentation(ts);
}

SVGPaintServer* getPaintServerById(Document* document, const AtomicString& id)
{
    SVGResource* resource = getResourceById(document, id);
    if (resource && resource->isPaintServer())
        return static_cast<SVGPaintServer*>(resource);

    return 0;
}

} // namespace WebCore

#endif
