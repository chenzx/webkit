/*
 * Copyright (C) 2007 Apple Inc.  All rights reserved.
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
#include "HashTable.h"
#include "ClipboardQt.h"
#include "IntPoint.h"
#include "PlatformString.h"
#include "StringHash.h"

#define notImplemented() qDebug("FIXME: UNIMPLEMENTED: %s:%d (%s)", __FILE__, __LINE__, __FUNCTION__)

namespace WebCore {
    
ClipboardQt::ClipboardQt(ClipboardAccessPolicy policy, bool forDragging) 
    : Clipboard(policy, forDragging)
    , m_isForDragging(forDragging)
{
    notImplemented();
}

void ClipboardQt::clearData(const String& type)
{
    notImplemented();
}

void ClipboardQt::clearAllData() 
{
    notImplemented();
}

String ClipboardQt::getData(const String& type, bool& success) const 
{
    notImplemented();
    return ""; 
}

bool ClipboardQt::setData(const String& type, const String& data) 
{
    notImplemented();
    return false;
}

// extensions beyond IE's API
HashSet<String> ClipboardQt::types() const 
{
    notImplemented();
    HashSet<String> result;
    return result;
}

IntPoint ClipboardQt::dragLocation() const 
{ 
    notImplemented();
    return IntPoint(0,0);
}

CachedImage* ClipboardQt::dragImage() const 
{
    notImplemented();
    return 0; 
}

void ClipboardQt::setDragImage(CachedImage*, const IntPoint&) 
{
    notImplemented();
}

Node* ClipboardQt::dragImageElement() 
{
    notImplemented();
    return 0; 
}

void ClipboardQt::setDragImageElement(Node*, const IntPoint&)
{
    notImplemented();
}

DragImageRef ClipboardQt::createDragImage(IntPoint& dragLoc) const
{ 
    notImplemented();
    return 0;
}

void ClipboardQt::declareAndWriteDragImage(Element*, const KURL&, const String&, Frame*) 
{
    notImplemented();
}

void ClipboardQt::writeURL(const KURL&, const String&, Frame*) 
{
    notImplemented();
}

void ClipboardQt::writeRange(Range*, Frame*) 
{
    notImplemented();
}

bool ClipboardQt::hasData() 
{
    notImplemented();
    return false;
}

}
