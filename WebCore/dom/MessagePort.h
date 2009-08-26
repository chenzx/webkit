/*
 * Copyright (C) 2008 Apple Inc. All Rights Reserved.
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
 *
 */

#ifndef MessagePort_h
#define MessagePort_h

#include "AtomicStringHash.h"
#include "EventListener.h"
#include "EventTarget.h"
#include "MessagePortChannel.h"

#include <wtf/HashMap.h>
#include <wtf/OwnPtr.h>
#include <wtf/PassOwnPtr.h>
#include <wtf/PassRefPtr.h>
#include <wtf/RefPtr.h>
#include <wtf/Vector.h>

namespace WebCore {

    class AtomicStringImpl;
    class Event;
    class Frame;
    class MessagePort;
    class ScriptExecutionContext;
    class String;

    // The overwhelmingly common case is sending a single port, so handle that efficiently with an inline buffer of size 1.
    typedef Vector<RefPtr<MessagePort>, 1> MessagePortArray;

    class MessagePort : public RefCounted<MessagePort>, public EventTarget {
    public:
        static PassRefPtr<MessagePort> create(ScriptExecutionContext& scriptExecutionContext) { return adoptRef(new MessagePort(scriptExecutionContext)); }
        ~MessagePort();

        void postMessage(const String& message, ExceptionCode&);
        void postMessage(const String& message, const MessagePortArray*, ExceptionCode&);
        // FIXME: remove this when we update the JS bindings (bug #28460).
        void postMessage(const String& message, MessagePort*, ExceptionCode&);

        void start();
        void close();

        void entangle(PassOwnPtr<MessagePortChannel>);
        PassOwnPtr<MessagePortChannel> disentangle(ExceptionCode&);

        // Disentangle an array of ports, returning the entangled channels.
        // Per section 8.3.3 of the HTML5 spec, generates an INVALID_STATE_ERR exception if any of the passed ports are null or not entangled.
        // Returns 0 if there is an exception, or if the passed-in array is 0/empty.
        static PassOwnPtr<MessagePortChannelArray> disentanglePorts(const MessagePortArray*, ExceptionCode&);

        // Entangles an array of channels, returning an array of MessagePorts in matching order.
        // Returns 0 if the passed array is 0/empty.
        static PassOwnPtr<MessagePortArray> entanglePorts(ScriptExecutionContext&, PassOwnPtr<MessagePortChannelArray>);

        void messageAvailable();
        bool started() const { return m_started; }

        void contextDestroyed();

        virtual ScriptExecutionContext* scriptExecutionContext() const;

        virtual MessagePort* toMessagePort() { return this; }

        void dispatchMessages();

        virtual void addEventListener(const AtomicString& eventType, PassRefPtr<EventListener>, bool useCapture);
        virtual void removeEventListener(const AtomicString& eventType, EventListener*, bool useCapture);
        virtual bool dispatchEvent(PassRefPtr<Event>, ExceptionCode&);

        typedef Vector<RefPtr<EventListener> > ListenerVector;
        typedef HashMap<AtomicString, ListenerVector> EventListenersMap;
        EventListenersMap& eventListeners() { return m_eventListeners; }

        using RefCounted<MessagePort>::ref;
        using RefCounted<MessagePort>::deref;

        bool hasPendingActivity();

        void setOnmessage(PassRefPtr<EventListener>);
        EventListener* onmessage() const { return m_onMessageListener.get(); }

        // Returns null if there is no entangled port, or if the entangled port is run by a different thread.
        // Returns null otherwise.
        // NOTE: This is used solely to enable a GC optimization. Some platforms may not be able to determine ownership of the remote port (since it may live cross-process) - those platforms may always return null.
        MessagePort* locallyEntangledPort();
        bool isEntangled() { return m_entangledChannel; }

    private:
        MessagePort(ScriptExecutionContext&);

        virtual void refEventTarget() { ref(); }
        virtual void derefEventTarget() { deref(); }

        OwnPtr<MessagePortChannel> m_entangledChannel;

        bool m_started;

        ScriptExecutionContext* m_scriptExecutionContext;

        RefPtr<EventListener> m_onMessageListener;

        EventListenersMap m_eventListeners;
    };

} // namespace WebCore

#endif // MessagePort_h
