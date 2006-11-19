/*
 * Copyright (C) 2005 Apple Computer, Inc.  All rights reserved.
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
#include "AffineTransform.h"
#include "FoundationExtras.h"
#include "KRenderingDeviceQuartz.h"
#include "SVGResourceFilter.h"

#include <QuartzCore/CoreImage.h>

namespace WebCore {

static const char* const SVGPreviousFilterOutputName = "__previousOutput__";

SVGResourceFilter::SVGResourceFilter()
    : m_filterCIContext(0)
    , m_filterCGLayer(0)
{
    m_imagesByName = HardRetainWithNSRelease([[NSMutableDictionary alloc] init]);
}

SVGResourceFilter::~SVGResourceFilter()
{
    ASSERT(!m_filterCGLayer);
    ASSERT(!m_filterCIContext);
    HardRelease(m_imagesByName);
}

void SVGResourceFilter::prepareFilter(const FloatRect &bbox)
{
    if (bbox.isEmpty() || !KRenderingDeviceQuartz::filtersEnabled() || m_effects.isEmpty())
        return;

    CGContextRef cgContext = static_cast<KRenderingDeviceQuartz*>(renderingDevice())->currentCGContext();

    // get a CIContext, and CGLayer for drawing in.
    bool useSoftware = ! KRenderingDeviceQuartz::hardwareRenderingEnabled();
    NSDictionary *contextOptions = nil;

    if (useSoftware)
        contextOptions = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], kCIContextUseSoftwareRenderer, nil];

    // Use of CGBegin/EndTransparencyLayer around this call causes over release
    // of cgContext due to it being created on an autorelease pool, and released
    // after CGEndTransparencyLayer. Create local pool to fix.
    // <http://bugs.webkit.org/show_bug.cgi?id=8425>
    // <http://bugs.webkit.org/show_bug.cgi?id=6947>
    // <rdar://problem/4647735>
    NSAutoreleasePool *filterContextPool = [[NSAutoreleasePool alloc] init];
    m_filterCIContext = HardRetain([CIContext contextWithCGContext:cgContext options:contextOptions]);
    [filterContextPool drain];

    m_filterCGLayer = [m_filterCIContext createCGLayerWithSize:CGRect(bbox).size info:NULL];

    KRenderingDeviceContext* filterContext = new KRenderingDeviceContextQuartz(CGLayerGetContext(m_filterCGLayer));
    renderingDevice()->pushContext(filterContext);

    filterContext->concatCTM(AffineTransform().translate(-1.0f * bbox.x(), -1.0f * bbox.y()));
}

void SVGResourceFilter::applyFilter(const FloatRect &bbox)
{
    if (bbox.isEmpty() || !KRenderingDeviceQuartz::filtersEnabled() || m_effects.isEmpty())
        return;

    // restore the previous context, delete the filter context.
    delete (renderingDevice()->popContext());

    // actually apply the filter effects
    CIImage *inputImage = [CIImage imageWithCGLayer:m_filterCGLayer];
    NSArray *filterStack = getCIFilterStack(inputImage);
    if ([filterStack count]) {
        CIImage *outputImage = [[filterStack lastObject] valueForKey:@"outputImage"];
        if (outputImage) {
            CGRect filterRect = CGRect(filterBBoxForItemBBox(bbox));
            CGRect translated = filterRect;
            CGPoint bboxOrigin = CGRect(bbox).origin;
            CGRect sourceRect = CGRectIntersection(translated,[outputImage extent]);

            CGPoint destOrigin = sourceRect.origin;
            destOrigin.x += bboxOrigin.x;
            destOrigin.y += bboxOrigin.y;

            [m_filterCIContext drawImage:outputImage atPoint:destOrigin fromRect:sourceRect];
        }
    }

    CGLayerRelease(m_filterCGLayer);
    m_filterCGLayer = 0;

    HardRelease(m_filterCIContext);
    m_filterCIContext = 0;
}

NSArray* SVGResourceFilter::getCIFilterStack(CIImage* inputImage)
{
    NSMutableArray* filterEffects = [NSMutableArray array];

    setImageForName(inputImage, "SourceGraphic"); // input

    for (unsigned int i = 0; i < m_effects.size(); i++) {
        CIFilter* filter = m_effects[i]->getCIFilter(this);
        if (filter)
            [filterEffects addObject:filter];
    }

    [m_imagesByName removeAllObjects]; // clean up before next time.

    return filterEffects;
}

CIImage *SVGResourceFilter::imageForName(const String& name) const
{
    return [m_imagesByName objectForKey:name];
}

void SVGResourceFilter::setImageForName(CIImage *image, const String &name)
{
    [m_imagesByName setValue:image forKey:name];
}

void SVGResourceFilter::setOutputImage(const SVGFilterEffect *filterEffect, CIImage *output)
{
    if (!filterEffect->result().isEmpty())
        setImageForName(output, filterEffect->result());
    setImageForName(output, SVGPreviousFilterOutputName);
}

static inline CIImage *alphaImageForImage(CIImage *image)
{
    CIFilter *onlyAlpha = [CIFilter filterWithName:@"CIColorMatrix"];
    CGFloat zero[4] = {0, 0, 0, 0};
    [onlyAlpha setDefaults];
    [onlyAlpha setValue:image forKey:@"inputImage"];
    [onlyAlpha setValue:[CIVector vectorWithValues:zero count:4] forKey:@"inputRVector"];
    [onlyAlpha setValue:[CIVector vectorWithValues:zero count:4] forKey:@"inputGVector"];
    [onlyAlpha setValue:[CIVector vectorWithValues:zero count:4] forKey:@"inputBVector"];
    return [onlyAlpha valueForKey:@"outputImage"];
}

CIImage *SVGResourceFilter::inputImage(const SVGFilterEffect *filterEffect)
{
    if (filterEffect->in().isEmpty()) {
        CIImage *inImage = imageForName(SVGPreviousFilterOutputName);
        if (!inImage)
            inImage = imageForName("SourceGraphic");
        return inImage;
    } else if (filterEffect->in() == "SourceAlpha") {
        CIImage *sourceAlpha = imageForName(filterEffect->in());
        if (!sourceAlpha) {
            CIImage *sourceGraphic = imageForName("SourceGraphic");
            if (!sourceGraphic)
                return nil;
            sourceAlpha = alphaImageForImage(sourceGraphic);
            setImageForName(sourceAlpha, "SourceAlpha");
        }
        return sourceAlpha;
    }

    return imageForName(filterEffect->in());
}

}

#endif // SVG_SUPPORT
