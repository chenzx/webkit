/*
 * Copyright (C) 2010 Google Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


#ifndef LayerRendererSkia_h
#define LayerRendererSkia_h

#if USE(ACCELERATED_COMPOSITING)

#include "IntRect.h"
#include "LayerSkia.h"
#include <wtf/Noncopyable.h>
#include <wtf/PassOwnPtr.h>
#include <wtf/Vector.h>

namespace skia {
class PlatformCanvas;
}

namespace WebCore {

class LayerRendererChromium : public Noncopyable {
public:
    static PassOwnPtr<LayerRendererChromium> create();

    LayerRendererChromium();
    ~LayerRendererChromium();

#if PLATFORM(SKIA)
    void drawLayersInCanvas(skia::PlatformCanvas*, const IntRect& clipRect);
#endif
    void updateLayerContents();

    void setRootLayer(PassRefPtr<LayerChromium> layer) { m_rootLayer = layer; }
    LayerChromium* rootLayer() { return m_rootLayer.get(); }

    void setNeedsDisplay() { m_needsDisplay = true; }

    void setScrollFrame(SkIRect& scrollFrame) { m_scrollFrame = scrollFrame; }

private:
#if PLATFORM(SKIA)
    void drawLayerInCanvasRecursive(skia::PlatformCanvas*, LayerChromium*, float opacity);
#endif
    void updateLayerContentsRecursive(LayerChromium*);

    RefPtr<LayerChromium> m_rootLayer;

    bool m_needsDisplay;
    SkIRect m_scrollFrame;
};

}

#endif // USE(ACCELERATED_COMPOSITING)

#endif
