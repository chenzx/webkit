/*
 * Copyright (C) 2007 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1.  Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 * 2.  Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 * 3.  Neither the name of Apple Computer, Inc. ("Apple") nor the names of
 *     its contributors may be used to endorse or promote products derived
 *     from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE AND ITS CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL APPLE OR ITS CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef SecurityOrigin_h
#define SecurityOrigin_h

#include <wtf/RefCounted.h>
#include <wtf/PassRefPtr.h>

#include "PlatformString.h"

namespace WebCore {

    class Frame;
    class KURL;
    class SecurityOriginData;
    
    class SecurityOrigin : public RefCounted<SecurityOrigin> {
    public:
        static PassRefPtr<SecurityOrigin> createForFrame(Frame*);

        void setDomainFromDOM(const String& newDomain);
        String domain() const { return m_host; }

        bool canAccess(const SecurityOrigin*) const;
        bool isSecureTransitionTo(const KURL&) const;

        String toString() const;
        
        SecurityOriginData securityOriginData() const;
        
    private:
        SecurityOrigin();
        bool isEmpty() const;

        void clear();
        void setForURL(const KURL& url);

        String m_protocol;
        String m_host;
        unsigned short m_port;
        bool m_portSet;
        bool m_noAccess;
        bool m_domainWasSetInDOM;
    };

} // namespace WebCore

#endif // SecurityOrigin_h
