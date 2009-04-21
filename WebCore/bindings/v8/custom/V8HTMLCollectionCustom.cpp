/*
 * Copyright (C) 2009 Google Inc. All rights reserved.
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
#include "HTMLCollection.h"

#include "V8Binding.h"
#include "V8CustomBinding.h"
#include "V8NamedNodesCollection.h"
#include "V8Proxy.h"

namespace WebCore {

static v8::Handle<v8::Value> getNamedItems(HTMLCollection* collection, AtomicString name)
{
    Vector<RefPtr<Node> > namedItems;
    collection->namedItems(name, namedItems);

    if (!namedItems.size())
        return v8::Handle<v8::Value>();

    if (namedItems.size() == 1)
        return V8Proxy::NodeToV8Object(namedItems.at(0).get());

    NodeList* list = new V8NamedNodesCollection(namedItems);
    return V8Proxy::ToV8Object(V8ClassIndex::NODELIST, list);
}

static v8::Handle<v8::Value> getItem(HTMLCollection* collection, v8::Handle<v8::Value> argument)
{
    v8::Local<v8::Uint32> index = argument->ToArrayIndex();
    if (index.IsEmpty()) {
        v8::Handle<v8::Value> result = getNamedItems(collection, toWebCoreString(argument->ToString()));

        if (result.IsEmpty())
            return v8::Undefined();

        return result;
    }

    RefPtr<Node> result = collection->item(index->Uint32Value());
    return V8Proxy::NodeToV8Object(result.get());
}

NAMED_PROPERTY_GETTER(HTMLCollection)
{
    INC_STATS("DOM.HTMLCollection.NamedPropertyGetter");
    // Search the prototype chain first.
    v8::Handle<v8::Value> value = info.Holder()->GetRealNamedPropertyInPrototypeChain(name);

    if (!value.IsEmpty())
        return value;

    // Search local callback properties next to find IDL defined
    // properties.
    if (info.Holder()->HasRealNamedCallbackProperty(name))
        return v8::Handle<v8::Value>();

    // Finally, search the DOM structure.
    HTMLCollection* imp = V8Proxy::ToNativeObject<HTMLCollection>(V8ClassIndex::HTMLCOLLECTION, info.Holder());
    return getNamedItems(imp, v8StringToAtomicWebCoreString(name));
}

CALLBACK_FUNC_DECL(HTMLCollectionItem)
{
    INC_STATS("DOM.HTMLCollection.item()");
    HTMLCollection* imp = V8Proxy::ToNativeObject<HTMLCollection>(V8ClassIndex::HTMLCOLLECTION, args.Holder());
    return getItem(imp, args[0]);
}

CALLBACK_FUNC_DECL(HTMLCollectionNamedItem)
{
    INC_STATS("DOM.HTMLCollection.namedItem()");
    HTMLCollection* imp = V8Proxy::ToNativeObject<HTMLCollection>(V8ClassIndex::HTMLCOLLECTION, args.Holder());
    v8::Handle<v8::Value> result = getNamedItems(imp, toWebCoreString(args[0]));

    if (result.IsEmpty())
        return v8::Undefined();

    return result;
}

CALLBACK_FUNC_DECL(HTMLCollectionCallAsFunction)
{
    INC_STATS("DOM.HTMLCollection.callAsFunction()");
    if (args.Length() < 1)
        return v8::Undefined();

    HTMLCollection* imp = V8Proxy::ToNativeObject<HTMLCollection>(V8ClassIndex::HTMLCOLLECTION, args.Holder());

    if (args.Length() == 1)
        return getItem(imp, args[0]);

    // If there is a second argument it is the index of the item we want.
    String name = toWebCoreString(args[0]);
    v8::Local<v8::Uint32> index = args[1]->ToArrayIndex();
    if (index.IsEmpty())
        return v8::Undefined();

    unsigned current = index->Uint32Value();
    Node* node = imp->namedItem(name);
    while (node) {
        if (!current)
            return V8Proxy::NodeToV8Object(node);

        node = imp->nextNamedItem(name);
        current--;
    }

    return v8::Undefined();
}

} // namespace WebCore
