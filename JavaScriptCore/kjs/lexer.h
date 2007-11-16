// -*- c-basic-offset: 2 -*-
/*
 *  This file is part of the KDE libraries
 *  Copyright (C) 1999-2000 Harri Porten (porten@kde.org)
 *  Copyright (C) 2007 Apple Inc.
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Library General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Library General Public License for more details.
 *
 *  You should have received a copy of the GNU Library General Public License
 *  along with this library; see the file COPYING.LIB.  If not, write to
 *  the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 *  Boston, MA 02110-1301, USA.
 *
 */

#ifndef Lexer_h
#define Lexer_h

#include "ustring.h"

namespace KJS {

  class Identifier;
  class RegExp;

  class Lexer : Noncopyable {
  public:
    void setCode(const UString &sourceURL, int startingLineNumber, const UChar *c, unsigned int len);
    int lex();

    int lineNo() const { return yylineno; }
    UString sourceURL() const { return m_sourceURL; }

    bool prevTerminator() const { return terminator; }

    enum State { Start,
                 IdentifierOrKeyword,
                 Identifier,
                 InIdentifierOrKeyword,
                 InIdentifier,
                 InIdentifierUnicodeEscapeStart,
                 InIdentifierUnicodeEscape,
                 InSingleLineComment,
                 InMultiLineComment,
                 InNum,
                 InNum0,
                 InHex,
                 InOctal,
                 InDecimal,
                 InExponentIndicator,
                 InExponent,
                 Hex,
                 Octal,
                 Number,
                 String,
                 Eof,
                 InString,
                 InEscapeSequence,
                 InHexEscape,
                 InUnicodeEscape,
                 Other,
                 Bad };

    bool scanRegExp();
    const UString& pattern() const { return m_pattern; }
    const UString& flags() const { return m_flags; }

    static unsigned char convertHex(int);
    static unsigned char convertHex(int c1, int c2);
    static UChar convertUnicode(int c1, int c2, int c3, int c4);
    static bool isIdentStart(int);
    static bool isIdentPart(int);
    static bool isHexDigit(int);

    bool sawError() const { return error; }

    void clear();

  private:
    friend Lexer& lexer();
    Lexer();
    ~Lexer();
    
    int yylineno;
    UString m_sourceURL;
    bool done;
    char *buffer8; // FIXME: This buffer is never deallocated.
    UChar *buffer16; // FIXME: This buffer is never deallocated.
    unsigned int size8, size16;
    unsigned int pos8, pos16;
    bool terminator;
    bool restrKeyword;
    // encountered delimiter like "'" and "}" on last run
    bool delimited;
    bool skipLF;
    bool skipCR;
    bool eatNextIdentifier;
    int stackToken;
    int lastToken;

    State state;
    void setDone(State);
    unsigned int pos;
    void shift(unsigned int p);
    void nextLine();
    int lookupKeyword(const char *);

    bool isWhiteSpace() const;
    bool isLineTerminator();
    static bool isOctalDigit(int);

    int matchPunctuator(int c1, int c2, int c3, int c4);
    static unsigned short singleEscape(unsigned short);
    static unsigned short convertOctal(int c1, int c2, int c3);

    void record8(int);
    void record16(int);
    void record16(UChar);

    KJS::Identifier *makeIdentifier(UChar *buffer, unsigned int pos);
    UString *makeUString(UChar *buffer, unsigned int pos);

    const UChar *code;
    unsigned int length;
    int yycolumn;
#ifndef KJS_PURE_ECMA
    int bol;     // begin of line
#endif
    bool error;

    // current and following unicode characters (int to allow for -1 for end-of-file marker)
    int current, next1, next2, next3;

    UString **strings;
    unsigned int numStrings;
    unsigned int stringsCapacity;

    KJS::Identifier **identifiers;
    unsigned int numIdentifiers;
    unsigned int identifiersCapacity;
    
    UString m_pattern;
    UString m_flags;
  };
  
  Lexer& lexer(); // Returns the singletone JavaScript lexer.

} // namespace KJS

#endif // Lexer_h
