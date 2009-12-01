/*
 * Copyright (C) 2009 Google Inc. All rights reserved.
 * Copyright (C) 2009 Joseph Pecoraro
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

WebInspector.DOMNode = function(doc, payload) {
    this.ownerDocument = doc;

    this.id = payload.id;
    this.nodeType = payload.nodeType;
    this.nodeName = payload.nodeName;
    this.localName = payload.localName;
    this._nodeValue = payload.nodeValue;
    this.textContent = this.nodeValue;

    this.attributes = [];
    this._attributesMap = {};
    if (payload.attributes)
        this._setAttributesPayload(payload.attributes);

    this._childNodeCount = payload.childNodeCount;
    this.children = null;

    this.nextSibling = null;
    this.prevSibling = null;
    this.firstChild = null;
    this.lastChild = null;
    this.parentNode = null;

    if (payload.children)
        this._setChildrenPayload(payload.children);

    this._computedStyle = null;
    this.style = null;
    this._matchedCSSRules = [];

    if (this.nodeType == Node.ELEMENT_NODE) {
        // HTML and BODY from internal iframes should not overwrite top-level ones.
        if (!this.ownerDocument.documentElement && this.nodeName === "HTML")
            this.ownerDocument.documentElement = this;
        if (!this.ownerDocument.body && this.nodeName === "BODY")
            this.ownerDocument.body = this;
    }
}

WebInspector.DOMNode.prototype = {
    hasAttributes: function()
    {
        return this.attributes.length > 0;
    },

    hasChildNodes: function()  {
        return this._childNodeCount > 0;
    },

    get nodeValue() {
        return this._nodeValue;
    },

    set nodeValue(value) {
        if (this.nodeType != Node.TEXT_NODE)
            return;
        var self = this;
        var callback = function()
        {
            self._nodeValue = value;
            self.textContent = value;
        };
        this.ownerDocument._domAgent.setTextNodeValueAsync(this, value, callback);
    },

    getAttribute: function(name)
    {
        var attr = this._attributesMap[name];
        return attr ? attr.value : undefined;
    },

    setAttribute: function(name, value)
    {
        var self = this;
        var callback = function()
        {
            var attr = self._attributesMap[name];
            if (attr)
                attr.value = value;
            else
                attr = self._addAttribute(name, value);
        };
        this.ownerDocument._domAgent.setAttributeAsync(this, name, value, callback);
    },

    removeAttribute: function(name)
    {
        var self = this;
        var callback = function()
        {
            delete self._attributesMap[name];
            for (var i = 0;  i < self.attributes.length; ++i) {
                if (self.attributes[i].name == name) {
                    self.attributes.splice(i, 1);
                    break;
                }
            }
        };
        this.ownerDocument._domAgent.removeAttributeAsync(this, name, callback);
    },

    _setAttributesPayload: function(attrs)
    {
        for (var i = 0; i < attrs.length; i += 2)
            this._addAttribute(attrs[i], attrs[i + 1]);
    },

    _insertChild: function(prev, payload)
    {
        var node = new WebInspector.DOMNode(this.ownerDocument, payload);
        if (!prev)
            // First node
            this.children = [ node ];
        else
            this.children.splice(this.children.indexOf(prev) + 1, 0, node);
        this._renumber();
        return node;
    },

    removeChild_: function(node)
    {
        this.children.splice(this.children.indexOf(node), 1);
        node.parentNode = null;
        this._renumber();
    },

    _setChildrenPayload: function(payloads)
    {
        this.children = [];
        for (var i = 0; i < payloads.length; ++i) {
            var payload = payloads[i];
            var node = new WebInspector.DOMNode(this.ownerDocument, payload);
            this.children.push(node);
        }
        this._renumber();
    },

    _renumber: function()
    {
        this._childNodeCount = this.children.length;
        if (this._childNodeCount == 0) {
            this.firstChild = null;
            this.lastChild = null;
            return;
        }
        this.firstChild = this.children[0];
        this.lastChild = this.children[this._childNodeCount - 1];
        for (var i = 0; i < this._childNodeCount; ++i) {
            var child = this.children[i];
            child.nextSibling = i + 1 < this._childNodeCount ? this.children[i + 1] : null;
            child.prevSibling = i - 1 >= 0 ? this.children[i - 1] : null;
            child.parentNode = this;
        }
    },

    _addAttribute: function(name, value)
    {
        var attr = {
            "name": name,
            "value": value,
            "_node": this
        };
        this._attributesMap[name] = attr;
        this.attributes.push(attr);
    },

    _setStyles: function(computedStyle, inlineStyle, styleAttributes, matchedCSSRules)
    {
        this._computedStyle = new WebInspector.CSSStyleDeclaration(computedStyle);
        this.style = new WebInspector.CSSStyleDeclaration(inlineStyle);

        for (var name in styleAttributes) {
            if (this._attributesMap[name])
                this._attributesMap[name].style = new WebInspector.CSSStyleDeclaration(styleAttributes[name]);
        }

        this._matchedCSSRules = [];
        for (var i = 0; i < matchedCSSRules.length; i++)
            this._matchedCSSRules.push(WebInspector.CSSStyleDeclaration.parseRule(matchedCSSRules[i]));
    },

    _clearStyles: function()
    {
        this.computedStyle = null;
        this.style = null;
        for (var name in this._attributesMap)
            this._attributesMap[name].style = null;
        this._matchedCSSRules = null;
    }
}

WebInspector.DOMDocument = function(domAgent, defaultView, payload)
{
    WebInspector.DOMNode.call(this, this, payload);
    this._listeners = {};
    this._domAgent = domAgent;
    this.defaultView = defaultView;
}

WebInspector.DOMDocument.prototype = {

    addEventListener: function(name, callback)
    {
        var listeners = this._listeners[name];
        if (!listeners) {
            listeners = [];
            this._listeners[name] = listeners;
        }
        listeners.push(callback);
    },

    removeEventListener: function(name, callback)
    {
        var listeners = this._listeners[name];
        if (!listeners)
            return;

        var index = listeners.indexOf(callback);
        if (index != -1)
            listeners.splice(index, 1);
    },

    _fireDomEvent: function(name, event)
    {
        var listeners = this._listeners[name];
        if (!listeners)
            return;

        for (var i = 0; i < listeners.length; ++i) {
            var listener = listeners[i];
            listener.call(this, event);
        }
    }
}

WebInspector.DOMDocument.prototype.__proto__ = WebInspector.DOMNode.prototype;


WebInspector.DOMWindow = function(domAgent)
{
    this._domAgent = domAgent;
}

WebInspector.DOMWindow.prototype = {
    get document()
    {
        return this._domAgent.document;
    },

    get Node()
    {
        return WebInspector.DOMNode;
    },

    get Element()
    {
        return WebInspector.DOMNode;
    },

    Object: function()
    {
    },

    getComputedStyle: function(node)
    {
        return node._computedStyle;
    },

    getMatchedCSSRules: function(node, pseudoElement, authorOnly)
    {
        return node._matchedCSSRules;
    }
}

WebInspector.DOMAgent = function() {
    this._window = new WebInspector.DOMWindow(this);
    this._idToDOMNode = null;
    this.document = null;
}

WebInspector.DOMAgent.prototype = {
    get domWindow()
    {
        return this._window;
    },

    getChildNodesAsync: function(parent, callback)
    {
        var children = parent.children;
        if (children) {
            callback(children);
            return;
        }
        function mycallback() {
            callback(parent.children);
        }
        var callId = WebInspector.Callback.wrap(mycallback);
        InspectorBackend.getChildNodes(callId, parent.id);
    },

    setAttributeAsync: function(node, name, value, callback)
    {
        var mycallback = this._didApplyDomChange.bind(this, node, callback);
        InspectorBackend.setAttribute(WebInspector.Callback.wrap(mycallback), node.id, name, value);
    },

    removeAttributeAsync: function(node, name, callback)
    {
        var mycallback = this._didApplyDomChange.bind(this, node, callback);
        InspectorBackend.removeAttribute(WebInspector.Callback.wrap(mycallback), node.id, name);
    },

    setTextNodeValueAsync: function(node, text, callback)
    {
        var mycallback = this._didApplyDomChange.bind(this, node, callback);
        InspectorBackend.setTextNodeValue(WebInspector.Callback.wrap(mycallback), node.id, text);
    },

    _didApplyDomChange: function(node, callback, success)
    {
        if (!success)
            return;
        callback();
        // TODO(pfeldman): Fix this hack.
        var elem = WebInspector.panels.elements.treeOutline.findTreeElement(node);
        if (elem) {
            elem._updateTitle();
        }
    },

    _attributesUpdated: function(nodeId, attrsArray)
    {
        var node = this._idToDOMNode[nodeId];
        node._setAttributesPayload(attrsArray);
    },

    nodeForId: function(nodeId) {
        return this._idToDOMNode[nodeId];
    },

    _setDocument: function(payload)
    {
        this._idToDOMNode = {};
        if (payload) {
            this.document = new WebInspector.DOMDocument(this, this._window, payload);
            this._idToDOMNode[payload.id] = this.document;
            this._bindNodes(this.document.children);
        } else
            this.document = null;
        WebInspector.panels.elements.reset();
    },

    _setDetachedRoot: function(payload)
    {
        var root = new WebInspector.DOMNode(this.document, payload);
        this._idToDOMNode[payload.id] = root;
    },

    _setChildNodes: function(parentId, payloads)
    {
        var parent = this._idToDOMNode[parentId];
        parent._setChildrenPayload(payloads);
        this._bindNodes(parent.children);
    },

    _bindNodes: function(children)
    {
        for (var i = 0; i < children.length; ++i) {
            var child = children[i];
            this._idToDOMNode[child.id] = child;
            if (child.children)
                this._bindNodes(child.children);
        }
    },

    _childNodeCountUpdated: function(nodeId, newValue)
    {
        var node = this._idToDOMNode[nodeId];
        node._childNodeCount = newValue;
        var outline = WebInspector.panels.elements.treeOutline;
        var treeElement = outline.findTreeElement(node);
        if (treeElement)
            treeElement.hasChildren = newValue;
    },

    _childNodeInserted: function(parentId, prevId, payload)
    {
        var parent = this._idToDOMNode[parentId];
        var prev = this._idToDOMNode[prevId];
        var node = parent._insertChild(prev, payload);
        this._idToDOMNode[node.id] = node;
        var event = { target : node, relatedNode : parent };
        this.document._fireDomEvent("DOMNodeInserted", event);
    },

    _childNodeRemoved: function(parentId, nodeId)
    {
        var parent = this._idToDOMNode[parentId];
        var node = this._idToDOMNode[nodeId];
        parent.removeChild_(node);
        var event = { target : node, relatedNode : parent };
        this.document._fireDomEvent("DOMNodeRemoved", event);
        delete this._idToDOMNode[nodeId];
    }
}

WebInspector.Cookies = {}

WebInspector.Cookies.getCookiesAsync = function(callback, cookieDomain)
{
    function mycallback(cookies, cookiesString) {
        if (cookiesString)
            callback(WebInspector.Cookies.buildCookiesFromString(cookiesString), false);
        else
            callback(cookies, true);
    }
    var callId = WebInspector.Callback.wrap(mycallback);
    InspectorBackend.getCookies(callId, cookieDomain);
}

WebInspector.Cookies.buildCookiesFromString = function(rawCookieString)
{
    var rawCookies = rawCookieString.split(/;\s*/);
    var cookies = [];

    if (!(/^\s*$/.test(rawCookieString))) {
        for (var i = 0; i < rawCookies.length; ++i) {
            var cookie = rawCookies[i];
            var delimIndex = cookie.indexOf("=");
            var name = cookie.substring(0, delimIndex);
            var value = cookie.substring(delimIndex + 1);
            var size = name.length + value.length;
            cookies.push({ name: name, value: value, size: size });
        }
    }

    return cookies;
}

WebInspector.EventListeners = {}

WebInspector.EventListeners.getEventListenersForNodeAsync = function(node, callback)
{
    if (!node)
        return;

    var callId = WebInspector.Callback.wrap(callback);
    InspectorBackend.getEventListenersForNode(callId, node.id);
}

WebInspector.CSSStyleDeclaration = function(payload)
{
    this.id = payload.id;
    this.width = payload.width;
    this.height = payload.height;
    this.__disabledProperties = payload.__disabledProperties;
    this.__disabledPropertyValues = payload.__disabledPropertyValues;
    this.__disabledPropertyPriorities = payload.__disabledPropertyPriorities;
    this.uniqueStyleProperties = payload.uniqueStyleProperties;
    this._shorthandValues = payload.shorthandValues;
    this._propertyMap = {};
    this._longhandProperties = {};
    this.length = payload.properties.length;

    for (var i = 0; i < this.length; ++i) {
        var property = payload.properties[i];
        var name = property.name;
        this[i] = name;
        this._propertyMap[name] = property;
    }

    // Index longhand properties.
    for (var i = 0; i < this.uniqueStyleProperties.length; ++i) {
        var name = this.uniqueStyleProperties[i];
        var property = this._propertyMap[name];
        if (property.shorthand) {
            var longhands = this._longhandProperties[property.shorthand];
            if (!longhands) {
                longhands = [];
                this._longhandProperties[property.shorthand] = longhands;
            }
            longhands.push(name);
        }
    }
}

WebInspector.CSSStyleDeclaration.parseStyle = function(payload)
{
    return new WebInspector.CSSStyleDeclaration(payload);
}

WebInspector.CSSStyleDeclaration.parseRule = function(payload)
{
    var rule = {};
    rule.id = payload.id;
    rule.selectorText = payload.selectorText;
    rule.style = new WebInspector.CSSStyleDeclaration(payload.style);
    rule.style.parentRule = rule;
    rule.isUserAgent = payload.isUserAgent;
    rule.isUser = payload.isUser;
    rule.isViaInspector = payload.isViaInspector;
    if (payload.parentStyleSheet)
        rule.parentStyleSheet = { href: payload.parentStyleSheet.href };

    return rule;
}

WebInspector.CSSStyleDeclaration.prototype = {
    getPropertyValue: function(name)
    {
        var property = this._propertyMap[name];
        return property ? property.value : "";
    },

    getPropertyPriority: function(name)
    {
        var property = this._propertyMap[name];
        return property ? property.priority : "";
    },

    getPropertyShorthand: function(name)
    {
        var property = this._propertyMap[name];
        return property ? property.shorthand : "";
    },

    isPropertyImplicit: function(name)
    {
        var property = this._propertyMap[name];
        return property ? property.implicit : "";
    },

    styleTextWithShorthands: function()
    {
        var cssText = "";
        var foundProperties = {};
        for (var i = 0; i < this.length; ++i) {
            var individualProperty = this[i];
            var shorthandProperty = this.getPropertyShorthand(individualProperty);
            var propertyName = (shorthandProperty || individualProperty);

            if (propertyName in foundProperties)
                continue;

            if (shorthandProperty) {
                var value = this.getPropertyValue(shorthandProperty);
                var priority = this.getShorthandPriority(shorthandProperty);
            } else {
                var value = this.getPropertyValue(individualProperty);
                var priority = this.getPropertyPriority(individualProperty);
            }

            foundProperties[propertyName] = true;

            cssText += propertyName + ": " + value;
            if (priority)
                cssText += " !" + priority;
            cssText += "; ";
        }

        return cssText;
    },

    getLonghandProperties: function(name)
    {
        return this._longhandProperties[name] || [];
    },

    getShorthandValue: function(shorthandProperty)
    {
        return this._shorthandValues[shorthandProperty];
    },

    getShorthandPriority: function(shorthandProperty)
    {
        var priority = this.getPropertyPriority(shorthandProperty);
        if (priority)
            return priority;

        var longhands = this._longhandProperties[shorthandProperty];
        return longhands ? this.getPropertyPriority(longhands[0]) : null;
    }
}

WebInspector.attributesUpdated = function()
{
    this.domAgent._attributesUpdated.apply(this.domAgent, arguments);
}

WebInspector.setDocument = function()
{
    this.domAgent._setDocument.apply(this.domAgent, arguments);
}

WebInspector.setDetachedRoot = function()
{
    this.domAgent._setDetachedRoot.apply(this.domAgent, arguments);
}

WebInspector.setChildNodes = function()
{
    this.domAgent._setChildNodes.apply(this.domAgent, arguments);
}

WebInspector.childNodeCountUpdated = function()
{
    this.domAgent._childNodeCountUpdated.apply(this.domAgent, arguments);
}

WebInspector.childNodeInserted = function()
{
    this.domAgent._childNodeInserted.apply(this.domAgent, arguments);
}

WebInspector.childNodeRemoved = function()
{
    this.domAgent._childNodeRemoved.apply(this.domAgent, arguments);
}

WebInspector.didGetCookies = WebInspector.Callback.processCallback;
WebInspector.didGetChildNodes = WebInspector.Callback.processCallback;
WebInspector.didPerformSearch = WebInspector.Callback.processCallback;
WebInspector.didApplyDomChange = WebInspector.Callback.processCallback;
WebInspector.didRemoveAttribute = WebInspector.Callback.processCallback;
WebInspector.didSetTextNodeValue = WebInspector.Callback.processCallback;
WebInspector.didGetEventListenersForNode = WebInspector.Callback.processCallback;
