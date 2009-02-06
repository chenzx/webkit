/*
 * Copyright (c) 2008, 2009, Google Inc. All rights reserved.
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

#ifndef KURLGooglePrivate_h
#define KURLGooglePrivate_h

#include "CString.h"

#include <googleurl/src/url_parse.h>
#include <googleurl/src/url_canon.h>

namespace WebCore {

    class KURL;
    class TextEncoding;

    // Wraps the internals related to using Google-URL as the bnackend for KURL.
    // This maintains the state and has auxiliary functions so that we don't need
    // to uglify KURL.h while allowing Google-URL to be evaluated.
    class KURLGooglePrivate {
    public:
        KURLGooglePrivate();
        KURLGooglePrivate(const url_parse::Parsed&, bool isValid);

        // Initializes the object. This will call through to one of the backend
        // initializers below depending on whether the string's internal
        // representation is 8 or 16 bit.
        void init(const KURL& base, const String& relative,
                  const TextEncoding* queryEncoding);

        // Backend initializers. The query encoding parameters are optional and can
        // be NULL (this implies UTF-8). These initializers require that the object
        // has just been created and the strings are NULL. Do not call on an
        // already-constructed object.
        void init(const KURL& base, const char* rel, int relLength,
                  const TextEncoding* queryEncoding);
        void init(const KURL& base, const UChar* rel, int relLength,
                  const TextEncoding* queryEncoding);

        // Does a deep copy to the given output object.
        void copyTo(KURLGooglePrivate* dest) const;

        // Returns the substring of the input identified by the given component.
        String componentString(const url_parse::Component&) const;

        // Replaces the given components, modifying the current URL. The current
        // URL must be valid.
        typedef url_canon::Replacements<url_parse::UTF16Char> Replacements;
        void replaceComponents(const Replacements&);

        // Setters for the data. Using the ASCII version when you know the
        // data is ASCII will be slightly more efficient. The UTF-8 version
        // will always be correct if the caller is unsure.
        void setUtf8(const char* data, int dataLength);
        void setAscii(const char* data, int dataLength);

        // TODO(brettw) we can support an additional optimization.  Make this
        // buffer support both optinal Strings and UTF-8 data. This way, we can use
        // the optimization from the original KURL which uses = with the original
        // string when canonicalization did not change it. This allows the strings
        // to share a buffer internally, and saves a malloc.

        // Getters for the data.
        const CString& utf8String() const { return m_utf8; }
        const String& string() const;

        bool m_isValid;
        bool m_protocolInHTTPFamily;
        url_parse::Parsed m_parsed; // Indexes into the UTF-8 version of the string.

    private:
        void initProtocolInHTTPFamily();

        CString m_utf8;

        // Set to true when the caller set us using the ASCII setter. We can
        // be more efficient when we know there is no UTF-8 to worry about.
        // This flag is currently always correct, but should be changed to be a
        // hint (see setUtf8).
        bool m_utf8IsASCII;

        mutable bool m_stringIsValid;
        mutable String m_string;
    };

} // namespace WebCore

#endif
