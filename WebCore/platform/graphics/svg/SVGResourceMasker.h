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

#ifndef SVGResourceMasker_H
#define SVGResourceMasker_H

#ifdef SVG_SUPPORT

#include "SVGResource.h"

namespace WebCore {

    class FloatRect;
    class SVGResourceImage;

    class SVGResourceMasker : public SVGResource {
    public:
        SVGResourceMasker();
        virtual ~SVGResourceMasker();

        void setMask(const PassRefPtr<SVGResourceImage>&);
        SVGResourceImage* mask() const;

        virtual bool isMasker() const { return true; }
        virtual TextStream& externalRepresentation(TextStream&) const;

        // To be implemented by the specific rendering devices
        void applyMask(const FloatRect& boundingBox) const;

    private:
        RefPtr<SVGResourceImage> m_mask;
    };

    SVGResourceMasker* getMaskerById(Document*, const AtomicString&);

} // namespace WebCore

#endif

#endif // SVGResourceMasker_H
