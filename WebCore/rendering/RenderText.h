/*
 * This file is part of the DOM implementation for KDE.
 *
 * (C) 1999 Lars Knoll (knoll@kde.org)
 * (C) 2000 Dirk Mueller (mueller@kde.org)
 * Copyright (C) 2004, 2005, 2006, 2007 Apple Computer, Inc.
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
 * the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 */

#ifndef RenderText_h
#define RenderText_h

#include "RenderObject.h"
#include "Text.h"

namespace WebCore {

// Define a constant for soft hyphen's unicode value.
const unsigned short SOFT_HYPHEN = 173;

class DocumentMarker;
class InlineBox;
class InlineTextBox;
class Position;
class String;
class StringImpl;

class RenderText : public RenderObject {
    friend class InlineTextBox;
public:
    RenderText(Node*, StringImpl*);

    virtual const char* renderName() const { return "RenderText"; }

    virtual bool isTextFragment() const { return false; }

    virtual PassRefPtr<StringImpl> originalString() const;

    virtual void setStyle(RenderStyle*);

    void extractTextBox(InlineTextBox*);
    void attachTextBox(InlineTextBox*);
    void removeTextBox(InlineTextBox*);
    void deleteTextBoxes();
    virtual void destroy();

    String data() const { return m_str.get(); }
    StringImpl* string() const { return m_str.get(); }

    virtual InlineBox* createInlineBox(bool,bool, bool isOnlyRun = false);
    virtual void dirtyLineBoxes(bool fullLayout, bool isRootInlineBox = false);

    virtual void paint(PaintInfo&, int tx, int ty) { ASSERT_NOT_REACHED(); }
    virtual void layout() { ASSERT_NOT_REACHED(); }

    virtual bool nodeAtPoint(const HitTestRequest&, HitTestResult&, int, int, int, int, HitTestAction) { ASSERT_NOT_REACHED(); return false; }

    virtual void absoluteRects(Vector<IntRect>&, int tx, int ty);
    virtual void addLineBoxRects(Vector<IntRect>&, unsigned startOffset = 0, unsigned endOffset = UINT_MAX);

    virtual VisiblePosition positionForCoordinates(int x, int y);

    virtual unsigned length() const { return m_str->length(); }
    const UChar* text() const { return m_str->characters(); }
    unsigned stringLength() const { return m_str->length(); } // non virtual implementation of length()
    virtual void position(InlineBox*);

    virtual unsigned width(unsigned from, unsigned len, const Font*, int xPos) const;
    virtual unsigned width(unsigned from, unsigned len, int xPos, bool firstLine = false) const;
    virtual int width() const;
    virtual int height() const;

    virtual short lineHeight(bool firstLine, bool isRootLineBox = false) const;

    // overrides
    virtual void calcMinMaxWidth();
    virtual int minWidth() const { return m_minWidth; }
    virtual int maxWidth() const { return m_maxWidth; }

    // widths
    void calcMinMaxWidth(int leadWidth);
    virtual void trimmedMinMaxWidth(int leadWidth,
                                    int& beginMinW, bool& beginWS,
                                    int& endMinW, bool& endWS,
                                    bool& hasBreakableChar, bool& hasBreak,
                                    int& beginMaxW, int& endMaxW,
                                    int& minW, int& maxW, bool& stripFrontSpaces);

    bool containsOnlyWhitespace(unsigned from, unsigned len) const;

    // returns the minimum x position of all runs relative to the parent.
    // defaults to 0.
    int minXPos() const;

    virtual int xPos() const;
    virtual int yPos() const;

    virtual const Font& font();
    virtual short verticalPositionHint(bool firstLine) const;

    void setText(PassRefPtr<StringImpl>, bool force = false);
    void setTextWithOffset(PassRefPtr<StringImpl>, unsigned offset, unsigned len, bool force = false);

    virtual bool canBeSelectionLeaf() const { return true; }
    virtual SelectionState selectionState() const { return static_cast<SelectionState>(m_selectionState); }
    virtual void setSelectionState(SelectionState s);
    virtual IntRect selectionRect();
    virtual IntRect caretRect(int offset, EAffinity, int* extraWidthToEndOfLine = 0);

    virtual int marginLeft() const { return style()->marginLeft().calcMinValue(0); }
    virtual int marginRight() const { return style()->marginRight().calcMinValue(0); }

    virtual IntRect getAbsoluteRepaintRect();

    const Font* font(bool firstLine) const;

    Text* element() const { return static_cast<Text*>(RenderObject::element()); }

    InlineTextBox* firstTextBox() const { return m_firstTextBox; }
    InlineTextBox* lastTextBox() const { return m_lastTextBox; }

    virtual InlineBox* inlineBox(int offset, EAffinity = UPSTREAM);

    virtual int caretMinOffset() const;
    virtual int caretMaxOffset() const;
    virtual unsigned caretMaxRenderedOffset() const;

    virtual int previousOffset(int current) const;
    virtual int nextOffset(int current) const;

    bool containsReversedText() const { return m_containsReversedText; }

    InlineTextBox* findNextInlineTextBox(int offset, int& pos) const;

protected:
    void setInternalString(PassRefPtr<StringImpl>);

private:
    void cacheWidths();
    int widthFromCache(const Font*, int start, int len, int tabWidth, int xPos) const;
    bool shouldUseMonospaceCache(const Font*) const;
    bool allAscii() const;

    // members
    RefPtr<StringImpl> m_str;

    InlineTextBox* m_firstTextBox;
    InlineTextBox* m_lastTextBox;

    int m_minWidth;
    int m_maxWidth;
    int m_beginMinWidth;
    int m_endMinWidth;

    unsigned m_selectionState : 3; // enums on Windows are signed, so this needs to be unsigned to prevent it turning negative. 
    bool m_hasBreakableChar : 1; // Whether or not we can be broken into multiple lines.
    bool m_hasBreak : 1; // Whether or not we have a hard break (e.g., <pre> with '\n').
    bool m_hasTab : 1; // Whether or not we have a variable width tab character (e.g., <pre> with '\t').
    bool m_hasBeginWS : 1; // Whether or not we begin with WS (only true if we aren't pre)
    bool m_hasEndWS : 1; // Whether or not we end with WS (only true if we aren't pre)

    bool m_linesDirty : 1; // This bit indicates that the text run has already dirtied specific
                           // line boxes, and this hint will enable layoutInlineChildren to avoid
                           // just dirtying everything when character data is modified (e.g., appended/inserted
                           // or removed).
    bool m_containsReversedText : 1;

    // 22 bits left
    mutable bool m_allAsciiChecked:1;
    mutable bool m_allAscii:1;
    int m_monospaceCharacterWidth;
};

} // namespace WebCore

#endif // RenderText_h
