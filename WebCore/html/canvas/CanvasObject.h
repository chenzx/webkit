/*
 * Copyright (C) 2009 Apple Inc. All rights reserved.
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

#ifndef CanvasObject_h
#define CanvasObject_h

#include <wtf/PassRefPtr.h>
#include <wtf/RefCounted.h>

#include "GraphicsContext3D.h"

namespace WebCore {

    class GraphicsContext3D;
    
    class CanvasObject : public RefCounted<CanvasObject> {
    public:
        virtual ~CanvasObject();
        
        Platform3DObject object() const { return m_object; }
        void setObject(Platform3DObject);
        void deleteObject();
        
        void detachContext()
        {
            deleteObject();
            m_context = 0;
        }
        
    protected:
        CanvasObject(GraphicsContext3D*);
        virtual void _deleteObject(Platform3DObject) = 0;
        
        GraphicsContext3D* context() const { return m_context; }
    
    private:
        Platform3DObject m_object;
        GraphicsContext3D* m_context;
    };
    
} // namespace WebCore

#endif // CanvasObject_h
