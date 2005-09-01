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

#include <kstaticdeleter.h>

#include <kdom/kdom.h>
#include <kdom/Helper.h>
#include <kdom/DOMString.h>
#include <kdom/Namespace.h>
#include <kdom/core/ElementImpl.h>
#include <kdom/core/DocumentImpl.h>
#include <kdom/core/DOMExceptionImpl.h>
#include <kdom/core/DocumentTypeImpl.h>
#include <kdom/css/MediaListImpl.h>

#include "ksvg.h"
#include "ksvgevents.h"
#include "CDFInterface.h"
#include "SVGRenderStyle.h"
#include "SVGDocumentImpl.h"
#include "SVGSVGElementImpl.h"
#include "SVGCSSStyleSelector.h"
#include "SVGCSSStyleSheetImpl.h"
#include "SVGDOMImplementationImpl.h"

using namespace KSVG;

static KStaticDeleter<SVGDOMImplementationImpl> instanceDeleter;
SVGDOMImplementationImpl *SVGDOMImplementationImpl::s_instance = 0;
QStringList SVGDOMImplementationImpl::s_features;

SVGDOMImplementationImpl::SVGDOMImplementationImpl() : KDOM::DOMImplementationImpl()
{
    m_animationContext = false;
}

SVGDOMImplementationImpl::~SVGDOMImplementationImpl()
{
    // clean up static data
    SVGCSSStyleSelector::clear();
    SVGRenderStyle::cleanup();
}

SVGDOMImplementationImpl *SVGDOMImplementationImpl::self()
{
    if(!s_instance)
    {
        s_instance = instanceDeleter.setObject(s_instance, new SVGDOMImplementationImpl());
        
        // 1.1 features
        s_features.append(QString::fromLatin1("SVG"));
        s_features.append(QString::fromLatin1("SVGDOM"));
        s_features.append(QString::fromLatin1("SVG-STATIC"));
        s_features.append(QString::fromLatin1("SVGDOM-STATIC"));
        s_features.append(QString::fromLatin1("SVG-ANIMATION"));
        s_features.append(QString::fromLatin1("SVGDOM-ANIMATION"));
        s_features.append(QString::fromLatin1("SVG-DYNAMIC"));
        s_features.append(QString::fromLatin1("COREATTRIBUTE"));
        s_features.append(QString::fromLatin1("STRUCTURE"));
        s_features.append(QString::fromLatin1("CONTAINERATTRIBUTE"));
        s_features.append(QString::fromLatin1("CONDITIOANLPROCESSING"));
        s_features.append(QString::fromLatin1("IMAGE"));
        s_features.append(QString::fromLatin1("STYLE"));
        s_features.append(QString::fromLatin1("VIEWPORTATTRIBUTE"));
        s_features.append(QString::fromLatin1("SHAPE"));
        s_features.append(QString::fromLatin1("TEXT"));
        s_features.append(QString::fromLatin1("PAINTATTRIBUTE"));
        s_features.append(QString::fromLatin1("OPACITYATTRIBUTE"));
        s_features.append(QString::fromLatin1("GRAPHICSATTRIBUTE"));
        s_features.append(QString::fromLatin1("MARKER"));
        s_features.append(QString::fromLatin1("COLORPROFILE"));
        s_features.append(QString::fromLatin1("GRADIENT"));
        s_features.append(QString::fromLatin1("PATTERN"));
        s_features.append(QString::fromLatin1("CLIP"));
        s_features.append(QString::fromLatin1("MASK"));
        s_features.append(QString::fromLatin1("FILTER"));
        s_features.append(QString::fromLatin1("XLINKATTRIBUTE"));
        s_features.append(QString::fromLatin1("FONT"));
        s_features.append(QString::fromLatin1("EXTENSIBILITY"));

        // 1.0 features
        //s_features.append(QString::fromLatin1("SVG"));
        s_features.append(QString::fromLatin1("SVG.STATIC"));
        s_features.append(QString::fromLatin1("SVG.ANIMATION"));
        s_features.append(QString::fromLatin1("SVG.DYNAMIC"));
        s_features.append(QString::fromLatin1("DOM"));
        s_features.append(QString::fromLatin1("DOM.SVG"));
        s_features.append(QString::fromLatin1("DOM.SVG.STATIC"));
        s_features.append(QString::fromLatin1("DOM.SVG.ANIMATION"));
        s_features.append(QString::fromLatin1("DOM.SVG.DYNAMIC"));
        s_features.append(QString::fromLatin1("SVG.ALL"));
        s_features.append(QString::fromLatin1("DOM.SVG.ALL"));
    }

    return s_instance;
}

bool SVGDOMImplementationImpl::hasFeature(KDOM::DOMStringImpl *_feature, KDOM::DOMStringImpl *_version) const
{
    QString feature = KDOM::DOMString(_feature).upper().string();
    KDOM::DOMString version(_version);
    if((version.isEmpty() || version == "1.1") &&
       feature.startsWith(QString::fromLatin1("HTTP://WWW.W3.ORG/TR/SVG11/FEATURE#")))
    {
        if(s_features.contains(feature.right(feature.length() - 35)))
            return true;
    }

    if((version.isEmpty() || version == "1.0") &&
       feature.startsWith(QString::fromLatin1("ORG.W3C.")))
    {
        if(s_features.contains(feature.right(feature.length() - 8)))
            return true;
    }

    return KDOM::DOMImplementationImpl::hasFeature(_feature, _version);
}

KDOM::DocumentTypeImpl *SVGDOMImplementationImpl::createDocumentType(KDOM::DOMStringImpl *qualifiedName, KDOM::DOMStringImpl *publicId, KDOM::DOMStringImpl *systemId) const
{
    // INVALID_CHARACTER_ERR: Raised if the specified qualified name contains an illegal character.
    if((qualifiedName && !qualifiedName->isEmpty()) || !KDOM::Helper::ValidateAttributeName(qualifiedName))
        throw new KDOM::DOMExceptionImpl(KDOM::INVALID_CHARACTER_ERR);

    // NAMESPACE_ERR: Raised if no qualifiedName supplied (not mentioned in the spec!)
    if(!qualifiedName || qualifiedName->isEmpty())
        throw new KDOM::DOMExceptionImpl(KDOM::NAMESPACE_ERR);

    // NAMESPACE_ERR: Raised if the qualifiedName is malformed.
    KDOM::Helper::CheckMalformedQualifiedName(qualifiedName);

    return new KDOM::DocumentTypeImpl(new KDOM::DocumentPtr(), qualifiedName, publicId, systemId);
}

KDOM::DocumentImpl *SVGDOMImplementationImpl::createDocument(KDOM::DOMStringImpl *namespaceURI, KDOM::DOMStringImpl *qualifiedNameImpl, KDOM::DocumentTypeImpl *doctype) const
{
    return createDocument(namespaceURI, qualifiedNameImpl, doctype, true, 0);
}

KDOM::DocumentImpl *SVGDOMImplementationImpl::createDocument(KDOM::DOMStringImpl *namespaceURI, KDOM::DOMStringImpl *qualifiedNameImpl, KDOM::DocumentTypeImpl *doctype, bool createDocElement, KDOM::KDOMView *view) const
{
    KDOM::DOMString qualifiedName(qualifiedNameImpl);
    if((namespaceURI && KDOM::DOMString(namespaceURI) != KDOM::NS_SVG) || (qualifiedName != "svg" && qualifiedName != "svg:svg"))
        return KDOM::DOMImplementationImpl::createDocument(namespaceURI, qualifiedNameImpl, doctype, createDocElement, view);

    int dummy;
    KDOM::Helper::CheckQualifiedName(qualifiedNameImpl, namespaceURI, dummy, true /*nameCanBeNull*/, true /*nameCanBeEmpty, see #61650*/);

    // WRONG_DOCUMENT_ERR: Raised if docType has already been used with a different
    //                     document or was created from a different implementation.
    if(doctype != 0 && doctype->ownerDocument() != 0)
            throw new KDOM::DOMExceptionImpl(KDOM::WRONG_DOCUMENT_ERR);

    SVGDocumentImpl *doc = new SVGDocumentImpl(const_cast<SVGDOMImplementationImpl *>(this), view);

    // TODO : what to do when doctype is null?
    if(doctype)
        doc->setDocType(doctype);

    // Add root element...
    if(createDocElement)
    {
        KDOM::ElementImpl *svg = doc->createElementNS(namespaceURI, qualifiedNameImpl);
        doc->appendChild(svg);
    }

    return doc;
}

KDOM::CSSStyleSheetImpl *SVGDOMImplementationImpl::createCSSStyleSheet(KDOM::DOMStringImpl *title, KDOM::DOMStringImpl *media) const
{
    // TODO : check whether media is valid
    SVGCSSStyleSheetImpl *parent = 0;
    SVGCSSStyleSheetImpl *sheet = new SVGCSSStyleSheetImpl(parent, 0);
    sheet->setTitle(title);
    sheet->setMedia(new KDOM::MediaListImpl(sheet, media));
    return sheet;
}

KDOM::DocumentTypeImpl *SVGDOMImplementationImpl::defaultDocumentType() const
{
    return 0;
    /*
    return createDocumentType("svg:svg", "-//W3C//DTD SVG20010904//EN",
                             "http://www.w3.org/TR/2001/REC-SVG-20010904/DTD/svg10.dtd");
    */
}

int SVGDOMImplementationImpl::typeToId(KDOM::DOMStringImpl *typeImpl)
{
    KDOM::DOMString type(typeImpl);

    if(type == "load") return KDOM::LOAD_EVENT;
    else if(type == "unload") return KDOM::UNLOAD_EVENT;
    else if(type == "abort") return KDOM::ABORT_EVENT;
    else if(type == "error") return KDOM::ERROR_EVENT;
    else if(type == "resize") return KDOM::RESIZE_EVENT;
    else if(type == "scroll") return KDOM::SCROLL_EVENT;
    else if(type == "zoom") return ZOOM_EVENT;

    return KDOM::DOMImplementationImpl::typeToId(typeImpl);
}

KDOM::DOMStringImpl *SVGDOMImplementationImpl::idToType(int eventId)
{
    QString ret;
    switch(eventId)
    {
        case KDOM::LOAD_EVENT: ret = "load"; break;
        case KDOM::UNLOAD_EVENT: ret = "unload"; break;
        case KDOM::ABORT_EVENT: ret = "abort"; break;
        case KDOM::ERROR_EVENT: ret = "error"; break;
        case KDOM::RESIZE_EVENT: ret = "resize"; break;
        case KDOM::SCROLL_EVENT: ret = "scroll"; break;
        case ZOOM_EVENT: ret = "zoom"; break;
        default: return KDOM::DOMImplementationImpl::idToType(eventId);
    }

    return new KDOM::DOMStringImpl(ret);
}

bool SVGDOMImplementationImpl::inAnimationContext() const
{
    return m_animationContext;
}

void SVGDOMImplementationImpl::setAnimationContext(bool value)
{
    m_animationContext = value;
}

KDOM::CDFInterface *SVGDOMImplementationImpl::createCDFInterface() const
{
    return new KSVG::CDFInterface();
}

// vim:ts=4:noet
