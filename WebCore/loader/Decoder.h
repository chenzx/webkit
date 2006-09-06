/*
    This file is part of the KDE libraries

    Copyright (C) 1999 Lars Knoll (knoll@mpi-hd.mpg.de)
    Copyright (C) 2006 Alexey Proskuryakov (ap@nypop.com)
    Copyright (C) 2006 Apple Computer, Inc.

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

#ifndef Decoder_h
#define Decoder_h

#include "PlatformString.h"
#include "Shared.h"
#include "TextDecoder.h"
#include <wtf/Vector.h>

namespace WebCore {

class Decoder : public Shared<Decoder> {
public:
    enum EncodingSource {
        DefaultEncoding,
        AutoDetectedEncoding,
        EncodingFromXMLHeader,
        EncodingFromMetaTag,
        EncodingFromCSSCharset,
        EncodingFromHTTPHeader,
        UserChosenEncoding
    };

    Decoder(const String& mimeType, const TextEncoding& defaultEncoding = TextEncoding());
    ~Decoder();

    void setEncoding(const TextEncoding&, EncodingSource);
    const TextEncoding& encoding() const { return m_decoder.encoding(); }

    String decode(const char* data, size_t length);
    String flush();

private:
    enum ContentType { PlainText, HTML, XML, CSS }; // PlainText is equivalent to directly using TextDecoder.
    static ContentType determineContentType(const String& mimeType);
    static const TextEncoding& defaultEncoding(ContentType, const TextEncoding& defaultEncoding);

    void checkForBOM(const char*, size_t);
    void checkForCSSCharset(const char*, size_t);
    bool checkForHeadCharset(const char*, size_t, bool& movedDataToBuffer);
    void detectJapaneseEncoding(const char*, size_t);

    ContentType m_contentType;
    TextDecoder m_decoder;
    EncodingSource m_source;
    Vector<char> m_buffer;
    bool m_checkedForBOM;
    bool m_checkedForCSSCharset;
    bool m_checkedForHeadCharset;
};

}

#endif
