/*
 * Copyright (C) 2004 Apple Computer, Inc.  All rights reserved.
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

#ifndef Selection_h
#define Selection_h

#include "TextGranularity.h"
#include "VisiblePosition.h"

namespace WebCore {

class Position;

const EAffinity SEL_DEFAULT_AFFINITY = DOWNSTREAM;

class Selection {
public:
    enum SelectionType { NoSelection, CaretSelection, RangeSelection };

    Selection();

    Selection(const Position&, EAffinity);
    Selection(const Position&, const Position&, EAffinity);

    Selection(const Range*, EAffinity = SEL_DEFAULT_AFFINITY);
    
    Selection(const VisiblePosition&);
    Selection(const VisiblePosition&, const VisiblePosition&);

    static Selection selectionFromContentsOfNode(Node*);

    SelectionType selectionType() const { return m_selectionType; }

    void setAffinity(EAffinity affinity) { m_affinity = affinity; }
    EAffinity affinity() const { return m_affinity; }

    void setBase(const Position&);
    void setBase(const VisiblePosition&);
    void setExtent(const Position&);
    void setExtent(const VisiblePosition&);
    
    Position base() const { return m_base; }
    Position extent() const { return m_extent; }
    Position start() const { return m_start; }
    Position end() const { return m_end; }
    
    VisiblePosition visibleStart() const { return VisiblePosition(m_start, isRange() ? DOWNSTREAM : affinity()); }
    VisiblePosition visibleEnd() const { return VisiblePosition(m_end, isRange() ? UPSTREAM : affinity()); }

    bool isNone() const { return selectionType() == NoSelection; }
    bool isCaret() const { return selectionType() == CaretSelection; }
    bool isRange() const { return selectionType() == RangeSelection; }
    bool isCaretOrRange() const { return selectionType() != NoSelection; }

    bool isBaseFirst() const { return m_baseIsFirst; }

    void appendTrailingWhitespace();

    bool expandUsingGranularity(TextGranularity granularity);
    TextGranularity granularity() const { return m_granularity; }

    PassRefPtr<Range> toRange() const;
    
    Element* rootEditableElement() const;
    bool isContentEditable() const;
    bool isContentRichlyEditable() const;
    Node* shadowTreeRootNode() const;
    
    void debugPosition() const;

#ifndef NDEBUG
    void formatForDebugger(char* buffer, unsigned length) const;
    void showTreeForThis() const;
#endif

    void setWithoutValidation(const Position&, const Position&);

private:
    void validate();

    // Support methods for validate()
    void setBaseAndExtentToDeepEquivalents();
    void setStartAndEndFromBaseAndExtentRespectingGranularity();
    void adjustSelectionToAvoidCrossingEditingBoundaries();
    void updateSelectionType();

    Position m_base;   // Where the first click happened
    Position m_extent; // Where the end click happened
    Position m_start;  // Leftmost position when expanded to respect granularity
    Position m_end;    // Rightmost position when expanded to respect granularity

    EAffinity m_affinity;           // the upstream/downstream affinity of the caret
    TextGranularity m_granularity;  // granularity of start/end selection

    // these are cached, can be recalculated by validate()
    SelectionType m_selectionType;    // None, Caret, Range
    bool m_baseIsFirst;               // true if base is before the extent
};

inline bool operator==(const Selection& a, const Selection& b)
{
    return a.start() == b.start() && a.end() == b.end() && a.affinity() == b.affinity() && a.granularity() == b.granularity() && a.isBaseFirst() == b.isBaseFirst();
}

inline bool operator!=(const Selection& a, const Selection& b)
{
    return !(a == b);
}

} // namespace WebCore

#ifndef NDEBUG
// Outside the WebCore namespace for ease of invocation from gdb.
void showTree(const WebCore::Selection&);
void showTree(const WebCore::Selection*);
#endif

#endif // Selection_h
