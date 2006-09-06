/*
    Copyright (C) 2004, 2005 Nikolas Zimmermann <wildfox@kde.org>
                  2004, 2005 Rob Buis <buis@kde.org>

    This file is part of the KDE project

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Library General Public License for more details.

    You should have received a copy of the GNU Library General Public License
    along with this library; see the file COPYING.LIB.  If not, write to
    the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
    Boston, MA 02111-1307, USA.
*/

#ifndef KSVG_SVGFEBlendElementImpl_H
#define KSVG_SVGFEBlendElementImpl_H
#ifdef SVG_SUPPORT

#include "SVGFilterPrimitiveStandardAttributes.h"
#include "KCanvasFilters.h"

namespace WebCore
{

    class SVGFEBlendElement : public SVGFilterPrimitiveStandardAttributes
    {
    public:
        SVGFEBlendElement(const QualifiedName&, Document*);
        virtual ~SVGFEBlendElement();

        // 'SVGFEBlendElement' functions
        // Derived from: 'Element'
        virtual void parseMappedAttribute(MappedAttribute *attr);

        virtual KCanvasFEBlend *filterEffect() const;

    protected:
        virtual const SVGElement* contextElement() const { return this; }

    private:
        ANIMATED_PROPERTY_DECLARATIONS(String, String, In, in)
        ANIMATED_PROPERTY_DECLARATIONS(String, String, In2, in2)
        ANIMATED_PROPERTY_DECLARATIONS(int, int, Mode, mode)
        mutable KCanvasFEBlend *m_filterEffect;
    };

} // namespace WebCore

#endif // SVG_SUPPORT
#endif

