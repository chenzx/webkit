/*
 * Copyright (C) 2005 Allan Sandfeld Jensen (kde@carewolf.com)
 * Copyright (C) 2006, 2007 Apple Inc. All rights reserved.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this library; see the file COPYING.LIB.  If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 */

#include "config.h"
#include "CounterNode.h"

#include "RenderObject.h"
#include <stdio.h>

// FIXME: There's currently no strategy for getting the counter tree updated when new
// elements with counter-reset and counter-increment styles are added to the render tree.
// Also, the code can't handle changes where an existing node needs to change into a
// "reset" node, or from a "reset" node back to not a "reset" node. As of this writing,
// at least some of these problems manifest as failures in the t1204-increment and
// t1204-reset tests in the CSS 2.1 test suite.

namespace WebCore {

CounterNode::CounterNode(RenderObject* o, bool hasResetType, int value)
    : m_hasResetType(hasResetType)
    , m_value(value)
    , m_countInParent(0)
    , m_renderer(o)
    , m_parent(0)
    , m_previousSibling(0)
    , m_nextSibling(0)
    , m_firstChild(0)
    , m_lastChild(0)
{
}

CounterNode* CounterNode::nextInPreOrderAfterChildren(const CounterNode* stayWithin) const
{
    if (this == stayWithin)
        return 0;

    const CounterNode* current = this;
    CounterNode* next;
    while (!(next = current->m_nextSibling)) {
        current = current->m_parent;
        if (!current || current == stayWithin)
            return 0;
    }
    return next;
}

CounterNode* CounterNode::nextInPreOrder(const CounterNode* stayWithin) const
{
    if (CounterNode* next = m_firstChild)
        return next;

    return nextInPreOrderAfterChildren(stayWithin);
}

CounterNode* CounterNode::lastDescendant() const
{
    CounterNode* last = m_lastChild;
    if (!last)
        return 0;

    while (CounterNode* lastChild = last->m_lastChild)
        last = lastChild;

    return last;
}

CounterNode* CounterNode::previousInPreOrder() const
{
    CounterNode* previous = m_previousSibling;
    if (!previous)
        return m_parent;

    while (CounterNode* lastChild = previous->m_lastChild)
        previous = lastChild;

    return previous;
}

int CounterNode::computeCountInParent() const
{
    int increment = actsAsReset() ? 0 : m_value;
    if (m_previousSibling)
        return m_previousSibling->m_countInParent + increment;
    ASSERT(m_parent->m_firstChild == this);
    return m_parent->m_value + increment;
}

void CounterNode::resetRenderer(const AtomicString& identifier) const
{
    if (!m_renderer || m_renderer->documentBeingDestroyed())
        return;
    if (RenderObjectChildList* children = m_renderer->virtualChildren())
        children->invalidateCounters(m_renderer, identifier);
}

void CounterNode::resetRenderers(const AtomicString& identifier) const
{
    const CounterNode* node = this;
    do {
        node->resetRenderer(identifier);
        node = node->nextInPreOrder(this);
    } while (node);
}

void CounterNode::recount(const AtomicString& identifier)
{
    for (CounterNode* node = this; node; node = node->m_nextSibling) {
        int oldCount = node->m_countInParent;
        int newCount = node->computeCountInParent();
        if (oldCount == newCount)
            break;
        node->m_countInParent = newCount;
        node->resetRenderers(identifier);
    }
}

void CounterNode::insertAfter(CounterNode* newChild, CounterNode* refChild, const AtomicString& identifier)
{
    ASSERT(newChild);
    ASSERT(!newChild->m_parent);
    ASSERT(!newChild->m_previousSibling);
    ASSERT(!newChild->m_nextSibling);
    ASSERT(!refChild || refChild->m_parent == this);

    CounterNode* next;

    if (refChild) {
        next = refChild->m_nextSibling;
        refChild->m_nextSibling = newChild;
    } else {
        next = m_firstChild;
        m_firstChild = newChild;
    }

    if (next) {
        ASSERT(next->m_previousSibling == refChild);
        next->m_previousSibling = newChild;
    } else {
        ASSERT(m_lastChild == refChild);
        m_lastChild = newChild;
    }

    newChild->m_parent = this;
    newChild->m_previousSibling = refChild;
    newChild->m_nextSibling = next;

    newChild->m_countInParent = newChild->computeCountInParent();
    if (next)
        next->recount(identifier);
}

void CounterNode::removeChild(CounterNode* oldChild, const AtomicString& identifier)
{
    ASSERT(oldChild);
    ASSERT(!oldChild->m_firstChild);
    ASSERT(!oldChild->m_lastChild);

    CounterNode* next = oldChild->m_nextSibling;
    CounterNode* previous = oldChild->m_previousSibling;

    oldChild->m_nextSibling = 0;
    oldChild->m_previousSibling = 0;
    oldChild->m_parent = 0;

    if (previous) 
        previous->m_nextSibling = next;
    else {
        ASSERT(m_firstChild == oldChild);
        m_firstChild = next;
    }

    if (next)
        next->m_previousSibling = previous;
    else {
        ASSERT(m_lastChild == oldChild);
        m_lastChild = previous;
    }

    if (next)
        next->recount(identifier);
}

#ifndef NDEBUG

static void showTreeAndMark(const CounterNode* node)
{
    const CounterNode* root = node;
    while (root->parent())
        root = root->parent();

    for (const CounterNode* current = root; current; current = current->nextInPreOrder()) {
        fwrite((current == node) ? "*" : " ", 1, 1, stderr);
        for (const CounterNode* parent = current; parent && parent != root; parent = parent->parent())
            fwrite("  ", 1, 2, stderr);
        fprintf(stderr, "%p %s: %d %d P:%p PS:%p NS:%p R:%p\n",
            current, current->actsAsReset() ? "reset____" : "increment", current->value(),
            current->countInParent(), current->parent(), current->previousSibling(),
            current->nextSibling(), current->renderer());
    }
}

#endif

} // namespace WebCore

#ifndef NDEBUG

void showTree(const WebCore::CounterNode* counter)
{
    if (counter)
        showTreeAndMark(counter);
}

#endif
