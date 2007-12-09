/*
    Copyright (C) 2004, 2005, 2007 Nikolas Zimmermann <zimmermann@kde.org>
                  2004, 2005, 2006 Rob Buis <buis@kde.org>

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
    the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
    Boston, MA 02110-1301, USA.
*/

#ifndef SVGFEMergeElement_h
#define SVGFEMergeElement_h

#if ENABLE(SVG) && ENABLE(SVG_FILTERS)
#include "SVGFEMerge.h"
#include "SVGFilterPrimitiveStandardAttributes.h"

namespace WebCore
{
    class SVGFEMergeElement : public SVGFilterPrimitiveStandardAttributes
    {
    public:
        SVGFEMergeElement(const QualifiedName&, Document*);
        virtual ~SVGFEMergeElement();

        virtual SVGFEMerge* filterEffect(SVGResourceFilter*) const;

    protected:
        virtual const SVGElement* contextElement() const { return this; }

    private:
        mutable SVGFEMerge* m_filterEffect;
    };

} // namespace WebCore

#endif // ENABLE(SVG)
#endif
