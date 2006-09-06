/*
 * This file is part of the DOM implementation for KDE.
 *
 * Copyright (C) 1999 Lars Knoll (knoll@kde.org)
 *           (C) 1999 Antti Koivisto (koivisto@kde.org)
 *           (C) 2001 Dirk Mueller (mueller@kde.org)
 * Copyright (C) 2004, 2005, 2006 Apple Computer, Inc.
 *           (C) 2006 Alexey Proskuryakov (ap@nypop.com)
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

#ifndef HTML_FormDataList_h
#define HTML_FormDataList_h

#include "CString.h"
#include "DeprecatedValueList.h"
#include "PlatformString.h"
#include "TextEncoding.h"

namespace WebCore {

struct FormDataListItem {
    FormDataListItem(const CString& data) : m_data(data) { }
    FormDataListItem(const String& path) : m_path(path) { }

    String m_path;
    CString m_data;
};

class FormDataList {
public:
    FormDataList(const TextEncoding&);

    void appendData(const String& key, const String& value)
        { appendString(key); appendString(value); }
    void appendData(const String& key, const CString& value)
        { appendString(key); appendString(value); }
    void appendData(const String& key, int value)
        { appendString(key); appendString(String::number(value)); }
    void appendFile(const String& key, const String& filename);

    DeprecatedValueListConstIterator<FormDataListItem> begin() const
        { return m_list.begin(); }
    DeprecatedValueListConstIterator<FormDataListItem> end() const
        { return m_list.end(); }

private:
    void appendString(const CString&);
    void appendString(const String&);

    TextEncoding m_encoding;
    DeprecatedValueList<FormDataListItem> m_list;
};

} // namespace WebCore

#endif // HTML_FormDataList_h
