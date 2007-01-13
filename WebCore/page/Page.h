// -*- mode: c++; c-basic-offset: 4 -*-
/*
 * Copyright (C) 2006 Apple Computer, Inc.
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
 */

#ifndef Page_h
#define Page_h

#include "BackForwardList.h"
#include "Chrome.h"
#include "ContextMenuController.h"
#include "FrameLoaderTypes.h"
#include "PlatformString.h"
#include <wtf/HashSet.h>
#include <wtf/OwnPtr.h>

#if PLATFORM(WIN)
typedef struct HINSTANCE__* HINSTANCE;
#endif

namespace WebCore {

    class Chrome;
    class ChromeClient;
    class ContextMenuClient;
    class ContextMenuController;
    class EditorClient;
    class FocusController;
    class Frame;
    class Node;
    class SelectionController;
    class Settings;

    class Page : Noncopyable {
    public:
        Page(ChromeClient*, ContextMenuClient*, EditorClient*);
        ~Page();
        
        EditorClient* editorClient() const { return m_editorClient; }

        void setMainFrame(PassRefPtr<Frame>);
        Frame* mainFrame() const { return m_mainFrame.get(); }

        BackForwardList* backForwardList();

        // FIXME: The following three methods don't fall under the responsibilities of the Page object
        // They seem to fit a hypothetical Page-controller object that would be akin to the 
        // Frame-FrameLoader relationship.  They have to live here now, but should move somewhere that
        // makes more sense when that class exists.
        bool goBack();
        bool goForward();
        void goToItem(HistoryItem*, FrameLoadType);
        
        void setGroupName(const String&);
        String groupName() const { return m_groupName; }

        const HashSet<Page*>* frameNamespace() const;
        static const HashSet<Page*>* frameNamespace(const String&);

        void incrementFrameCount() { ++m_frameCount; }
        void decrementFrameCount() { --m_frameCount; }
        int frameCount() const { return m_frameCount; }

        static void setNeedsReapplyStyles();
        static void setNeedsReapplyStylesForSettingsChange(Settings*);

        Chrome* chrome() { return m_chrome.get(); }
        SelectionController* dragCaretController() { return m_dragCaretController.get(); }
        FocusController* focusController() { return m_focusController.get(); }
        ContextMenuController* contextMenuController() { return m_contextMenuController.get(); }
        Settings* settings() { return m_settings.get(); }

        void setDefersLoading(bool);
        bool defersLoading() const { return m_defersLoading; }

        unsigned long createUniqueIdentifier();
        
#if PLATFORM(WIN)
        // The global DLL or application instance used for all windows.
        static void setInstanceHandle(HINSTANCE instanceHandle) { s_instanceHandle = instanceHandle; }
        static HINSTANCE instanceHandle() { return s_instanceHandle; }
#endif

    private:
        OwnPtr<Chrome> m_chrome;
        OwnPtr<SelectionController> m_dragCaretController;
        OwnPtr<FocusController> m_focusController;
        OwnPtr<ContextMenuController> m_contextMenuController;
        RefPtr<BackForwardList> m_backForwardList;
        OwnPtr<Settings> m_settings;

        EditorClient* m_editorClient;
        RefPtr<Frame> m_mainFrame;
        RefPtr<Node> m_focusedNode;
        int m_frameCount;
        String m_groupName;

        bool m_defersLoading;

        unsigned long m_uniqueIdentifier;
        
#if PLATFORM(WIN)
        static HINSTANCE s_instanceHandle;
#endif
    };

} // namespace WebCore
    
#endif // Page_h
