/*
 * Copyright (C) 2007-2009 Google Inc. All rights reserved.
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

#include "config.h"
#include "Node.h"

#include "Document.h"
#include "EventListener.h"

#include "V8Binding.h"
#include "V8CustomBinding.h"
#include "V8CustomEventListener.h"
#include "V8Proxy.h"

#include <wtf/RefPtr.h>

namespace WebCore {

CALLBACK_FUNC_DECL(NodeAddEventListener)
{
    INC_STATS("DOM.Node.addEventListener()");
    Node* node = V8Proxy::DOMWrapperToNode<Node>(args.Holder());

    V8Proxy* proxy = V8Proxy::retrieve(node->document()->frame());
    if (!proxy)
        return v8::Undefined();

    RefPtr<EventListener> listener = proxy->FindOrCreateV8EventListener(args[1], false);
    if (listener) {
        String type = toWebCoreString(args[0]);
        bool useCapture = args[2]->BooleanValue();
        node->addEventListener(type, listener, useCapture);
    }
    return v8::Undefined();
}

CALLBACK_FUNC_DECL(NodeRemoveEventListener)
{
    INC_STATS("DOM.Node.removeEventListener()");
    Node* node = V8Proxy::DOMWrapperToNode<Node>(args.Holder());

    V8Proxy* proxy = V8Proxy::retrieve(node->document()->frame());
    // It is possbile that the owner document of the node is detached
    // from the frame, return immediately in this case.
    // See issue http://b/878909
    if (!proxy)
        return v8::Undefined();

    RefPtr<EventListener> listener = proxy->FindV8EventListener(args[1], false);
    if (listener) {
        String type = toWebCoreString(args[0]);
        bool useCapture = args[2]->BooleanValue();
        node->removeEventListener(type, listener.get(), useCapture);
    }

    return v8::Undefined();
}

} // namespace WebCore
