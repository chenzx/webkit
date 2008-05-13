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
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

WebInspector.ScriptsPanel = function()
{
    WebInspector.Panel.call(this);

    this.element.addStyleClass("scripts");

    this.topStatusBar = document.createElement("div");
    this.topStatusBar.className = "status-bar";
    this.topStatusBar.id = "scripts-status-bar";
    this.element.appendChild(this.topStatusBar);

    this.backButton = document.createElement("button");
    this.backButton.className = "status-bar-item";
    this.backButton.id = "scripts-back";
    this.backButton.title = WebInspector.UIString("Show the previous script resource.");
    this.backButton.disabled = true;
    this.backButton.appendChild(document.createElement("img"));
    this.topStatusBar.appendChild(this.backButton);

    this.forwardButton = document.createElement("button");
    this.forwardButton.className = "status-bar-item";
    this.forwardButton.id = "scripts-forward";
    this.forwardButton.title = WebInspector.UIString("Show the next script resource.");
    this.forwardButton.disabled = true;
    this.forwardButton.appendChild(document.createElement("img"));
    this.topStatusBar.appendChild(this.forwardButton);

    this.filesSelectElement = document.createElement("select");
    this.filesSelectElement.className = "status-bar-item";
    this.filesSelectElement.id = "scripts-files";
    this.filesSelectElement.addEventListener("change", this._changeVisibleFile.bind(this), false);
    this.topStatusBar.appendChild(this.filesSelectElement);

    this.functionsSelectElement = document.createElement("select");
    this.functionsSelectElement.className = "status-bar-item";
    this.functionsSelectElement.id = "scripts-functions";
    this.topStatusBar.appendChild(this.functionsSelectElement);

    this.sidebarButtonsElement = document.createElement("div");
    this.sidebarButtonsElement.id = "scripts-sidebar-buttons";
    this.topStatusBar.appendChild(this.sidebarButtonsElement);

    this.pauseButton = document.createElement("button");
    this.pauseButton.className = "status-bar-item";
    this.pauseButton.id = "scripts-pause";
    this.pauseButton.title = WebInspector.UIString("Pause script execution.");
    this.pauseButton.disabled = true;
    this.pauseButton.appendChild(document.createElement("img"));
    this.pauseButton.addEventListener("click", this._togglePause.bind(this), false);
    this.sidebarButtonsElement.appendChild(this.pauseButton);

    this.stepOverButton = document.createElement("button");
    this.stepOverButton.className = "status-bar-item";
    this.stepOverButton.id = "scripts-step-over";
    this.stepOverButton.title = WebInspector.UIString("Step over next function call.");
    this.stepOverButton.disabled = true;
    this.stepOverButton.addEventListener("click", this._stepOverClicked.bind(this), false);
    this.stepOverButton.appendChild(document.createElement("img"));
    this.sidebarButtonsElement.appendChild(this.stepOverButton);

    this.stepIntoButton = document.createElement("button");
    this.stepIntoButton.className = "status-bar-item";
    this.stepIntoButton.id = "scripts-step-into";
    this.stepIntoButton.title = WebInspector.UIString("Step into next function call.");
    this.stepIntoButton.disabled = true;
    this.stepIntoButton.addEventListener("click", this._stepIntoClicked.bind(this), false);
    this.stepIntoButton.appendChild(document.createElement("img"));
    this.sidebarButtonsElement.appendChild(this.stepIntoButton);

    this.stepOutButton = document.createElement("button");
    this.stepOutButton.className = "status-bar-item";
    this.stepOutButton.id = "scripts-step-out";
    this.stepOutButton.title = WebInspector.UIString("Step out of current function.");
    this.stepOutButton.disabled = true;
    this.stepOutButton.addEventListener("click", this._stepOutClicked.bind(this), false);
    this.stepOutButton.appendChild(document.createElement("img"));
    this.sidebarButtonsElement.appendChild(this.stepOutButton);

    this.debuggerStatusElement = document.createElement("div");
    this.debuggerStatusElement.id = "scripts-debugger-status";
    this.sidebarButtonsElement.appendChild(this.debuggerStatusElement);

    this.scriptResourceViews = document.createElement("div");
    this.scriptResourceViews.id = "script-resource-views";

    this.sidebarElement = document.createElement("div");
    this.sidebarElement.id = "scripts-sidebar";

    this.sidebarResizeElement = document.createElement("div");
    this.sidebarResizeElement.className = "sidebar-resizer-vertical";
    this.sidebarResizeElement.addEventListener("mousedown", this._startSidebarResizeDrag.bind(this), false);

    this.sidebarResizeWidgetElement = document.createElement("div");
    this.sidebarResizeWidgetElement.id = "scripts-sidebar-resizer-widget";
    this.sidebarResizeWidgetElement.addEventListener("mousedown", this._startSidebarResizeDrag.bind(this), false);
    this.topStatusBar.appendChild(this.sidebarResizeWidgetElement);

    this.sidebarPanes = {};
    this.sidebarPanes.callstack = new WebInspector.CallStackSidebarPane();
    this.sidebarPanes.scopechain = new WebInspector.ScopeChainSidebarPane();
    this.sidebarPanes.breakpoints = new WebInspector.BreakpointsSidebarPane();

    for (var pane in this.sidebarPanes)
        this.sidebarElement.appendChild(this.sidebarPanes[pane].element);

    this.sidebarPanes.callstack.expanded = true;
    this.sidebarPanes.callstack.addEventListener("call frame selected", this._callFrameSelected, this);

    this.sidebarPanes.scopechain.expanded = true;

    this.element.appendChild(this.scriptResourceViews);
    this.element.appendChild(this.sidebarElement);
    this.element.appendChild(this.sidebarResizeElement);

    this.debuggingButton = document.createElement("button");
    this.debuggingButton.id = "scripts-debugging-status-bar-item";
    this.debuggingButton.className = "status-bar-item";
    this.debuggingButton.addEventListener("click", this._toggleDebugging.bind(this), false);

    this._breakpointsURLMap = {};

    this.reset();
}

WebInspector.ScriptsPanel.prototype = {
    toolbarItemClass: "scripts",

    get toolbarItemLabel()
    {
        return WebInspector.UIString("Scripts");
    },

    get statusBarItems()
    {
        return [this.debuggingButton];
    },

    show: function()
    {
        WebInspector.Panel.prototype.show.call(this);
        this.sidebarResizeElement.style.right = (this.sidebarElement.offsetWidth - 3) + "px";

        if (this.visibleView) {
            if (this.visibleView instanceof WebInspector.ResourceView)
                this.visibleView.headersVisible = false;
            this.visibleView.show(this.scriptResourceViews);
        }
    },

    addScript: function(sourceID, sourceURL, source, startingLine, errorLine, errorMessage)
    {
        var script = new WebInspector.Script(sourceID, sourceURL, source, startingLine, errorLine, errorMessage);

        if (sourceURL in WebInspector.resourceURLMap) {
            var resource = WebInspector.resourceURLMap[sourceURL];
            resource.addScript(script);
        }

        if (sourceURL in this._breakpointsURLMap && sourceID) {
            var breakpoints = this._breakpointsURLMap[sourceURL];
            var breakpointsLength = breakpoints.length;
            for (var i = 0; i < breakpointsLength; ++i) {
                var breakpoint = breakpoints[i];
                if (startingLine <= breakpoint.line)
                    breakpoint.sourceID = sourceID;
            }

            InspectorController.addBreakpoint(breakpoint.sourceID, breakpoint.line);
        }

        if (sourceID)
            this._sourceIDMap[sourceID] = (resource || script);

        this._addScriptToFilesMenu(script);
    },

    addBreakpoint: function(breakpoint)
    {
        this.sidebarPanes.breakpoints.addBreakpoint(breakpoint);

        var sourceFrame;
        if (breakpoint.url) {
            if (!(breakpoint.url in this._breakpointsURLMap))
                this._breakpointsURLMap[breakpoint.url] = [];
            this._breakpointsURLMap[breakpoint.url].unshift(breakpoint);

            if (breakpoint.url in WebInspector.resourceURLMap) {
                var resource = WebInspector.resourceURLMap[breakpoint.url];
                sourceFrame = this._sourceFrameForScriptOrResource(resource);
            }
        }

        if (breakpoint.sourceID && !sourceFrame) {
            var object = this._sourceIDMap[breakpoint.sourceID]
            sourceFrame = this._sourceFrameForScriptOrResource(object);
        }

        if (sourceFrame)
            sourceFrame.addBreakpoint(breakpoint);
    },

    removeBreakpoint: function(breakpoint)
    {
        this.sidebarPanes.breakpoints.removeBreakpoint(breakpoint);

        var sourceFrame;
        if (breakpoint.url && breakpoint.url in this._breakpointsURLMap) {
            var breakpoints = this._breakpointsURLMap[breakpoint.url];
            breakpoints.remove(breakpoint);
            if (!breakpoints.length)
                delete this._breakpointsURLMap[breakpoint.url];

            if (breakpoint.url in WebInspector.resourceURLMap) {
                var resource = WebInspector.resourceURLMap[breakpoint.url];
                sourceFrame = this._sourceFrameForScriptOrResource(resource);
            }
        }

        if (breakpoint.sourceID && !sourceFrame) {
            var object = this._sourceIDMap[breakpoint.sourceID]
            sourceFrame = this._sourceFrameForScriptOrResource(object);
        }

        if (sourceFrame)
            sourceFrame.removeBreakpoint(breakpoint);
    },

    debuggerPaused: function()
    {
        this._paused = true;
        this._waitingToPause = false;
        this._stepping = false;

        this._updateDebuggerButtons();

        var callStackPane = this.sidebarPanes.callstack;
        var currentFrame = InspectorController.currentCallFrame();
        callStackPane.update(currentFrame);
        callStackPane.selectedCallFrame = currentFrame;
    },

    reset: function()
    {
        this.visibleView = null;

        this._clearCurrentExecutionLine();

        if (!InspectorController.debuggerAttached()) {
            this._paused = false;
            this._waitingToPause = false;
            this._stepping = false;
        }

        this.sidebarPanes.callstack.update(null);
        this.sidebarPanes.scopechain.update(null);

        this._updateDebuggerButtons();

        this.filesSelectElement.removeChildren();
        this.functionsSelectElement.removeChildren();
        this.scriptResourceViews.removeChildren();

        if (this._sourceIDMap) {
            for (var sourceID in this._sourceIDMap) {
                var object = this._sourceIDMap[sourceID];
                if (object instanceof WebInspector.Resource)
                    object.removeAllScripts();
            }
        }

        this._sourceIDMap = {};
    },

    get visibleView()
    {
        return this._visibleView;
    },

    set visibleView(x)
    {
        if (this._visibleView === x)
            return;

        if (this._visibleView)
            this._visibleView.hide();

        this._visibleView = x;

        if (x)
            x.show(this.scriptResourceViews);
    },

    showScript: function(script, line)
    {
        this._showScriptOrResource(script, line);
    },

    showResource: function(resource, line)
    {
        this._showScriptOrResource(resource, line);
    },

    scriptViewForScript: function(script)
    {
        if (!script)
            return null;
        if (!script._scriptView)
            script._scriptView = new WebInspector.ScriptView(script);
        return script._scriptView;
    },

    sourceFrameForScript: function(script)
    {
        var view = this.scriptViewForScript(script);
        if (!view)
            return null;

        // Setting up the source frame requires that we be attached.
        if (!this.element.parentNode)
            this.attach();

        view.setupSourceFrameIfNeeded();
        return view.sourceFrame;
    },

    _sourceFrameForScriptOrResource: function(scriptOrResource)
    {
        if (scriptOrResource instanceof WebInspector.Resource)
            return WebInspector.panels.resources.sourceFrameForResource(scriptOrResource);
        if (scriptOrResource instanceof WebInspector.Script)
            return this.sourceFrameForScript(scriptOrResource);
    },

    _showScriptOrResource: function(scriptOrResource, line)
    {
        if (!scriptOrResource)
            return;

        var view;
        if (scriptOrResource instanceof WebInspector.Resource) {
            view = WebInspector.panels.resources.resourceViewForResource(scriptOrResource);
            view.headersVisible = false;

            if (scriptOrResource.url in this._breakpointsURLMap) {
                var sourceFrame = this._sourceFrameForScriptOrResource(scriptOrResource);
                if (sourceFrame && !sourceFrame.breakpoints.length) {
                    var breakpoints = this._breakpointsURLMap[scriptOrResource.url];
                    var breakpointsLength = breakpoints.length;
                    for (var i = 0; i < breakpointsLength; ++i)
                        sourceFrame.addBreakpoint(breakpoints[i]);
                }
            }
        } else if (scriptOrResource instanceof WebInspector.Script)
            view = this.scriptViewForScript(scriptOrResource);

        if (!view)
            return;

        this.visibleView = view;

        if (line && view.revealLine)
            view.revealLine(line);

        var select = this.filesSelectElement;
        var options = select.options;
        for (var i = 0; i < options.length; ++i) {
            if (options[i].representedObject === scriptOrResource)
                break;
        }

        select.selectedIndex = i;
    },

    _addScriptToFilesMenu: function(script)
    {
        var select = this.filesSelectElement;
        var options = select.options;
        for (var i = 0; i < options.length; ++i) {
            var option = options[i];
            if (option.representedObject === (script.resource || script))
                return;
        }

        // FIXME: Append in some meaningful order.
        var option = document.createElement("option");
        option.representedObject = (script.resource || script);
        option.text = (script.sourceURL ? script.sourceURL.trimURL(WebInspector.mainResource ? WebInspector.mainResource.domain : "") : "(eval script)");
        select.appendChild(option);

        // Call _showScriptOrResource if the option we just appended ended up being selected.
        // This will happen for the first item added to the menu.
        if (options[select.selectedIndex] === option)
            this._showScriptOrResource(option.representedObject);
    },

    _removeScriptFromFilesMenu: function(script)
    {
        // This function assumes it is called before removeScript is called on the resource.
        if (script.resource && script.resource.scripts.length > 1)
            return; // The resource has more than one script, so keep the resource in the menu.

        var select = this.filesSelectElement;
        var options = select.options;
        for (var i = 0; i < options.length; ++i) {
            if (option.representedObject !== script.resource && option.representedObject !== script)
                continue;

            if (select.selectedIndex === i) {
                // Pick the next selectedIndex. If we're at the end of the list, loop back to beginning.
                var nextSelectedIndex = ((select.selectedIndex + 1) >= select.options.length ? 0 : select.selectedIndex);
            }

            // Remove the option from the select
            select.options[select.selectedIndex] = null;

            if (nextSelectedIndex)
                select.selectedIndex = nextSelectedIndex;
        }
    },

    _clearCurrentExecutionLine: function()
    {
        if (this._executionSourceFrame)
            this._executionSourceFrame.executionLine = 0;
        delete this._executionSourceFrame;
    },

    _callFrameSelected: function()
    {
        this._clearCurrentExecutionLine();

        var callStackPane = this.sidebarPanes.callstack;
        var currentFrame = callStackPane.selectedCallFrame;
        if (!currentFrame)
            return;

        this.sidebarPanes.scopechain.update(currentFrame);

        var scriptOrResource = this._sourceIDMap[currentFrame.sourceIdentifier];
        this._showScriptOrResource(scriptOrResource, currentFrame.line);

        this._executionSourceFrame = this._sourceFrameForScriptOrResource(scriptOrResource);
        if (this._executionSourceFrame)
            this._executionSourceFrame.executionLine = currentFrame.line;
    },

    _changeVisibleFile: function(event)
    {
        var select = this.filesSelectElement;
        this._showScriptOrResource(select.options[select.selectedIndex].representedObject);
    },

    _startSidebarResizeDrag: function(event)
    {
        WebInspector.elementDragStart(this.sidebarElement, this._sidebarResizeDrag.bind(this), this._endSidebarResizeDrag.bind(this), event, "col-resize");

        if (event.target === this.sidebarResizeWidgetElement)
            this._dragOffset = (event.target.offsetWidth - (event.pageX - event.target.totalOffsetLeft));
        else
            this._dragOffset = 0;
    },

    _endSidebarResizeDrag: function(event)
    {
        WebInspector.elementDragEnd(event);

        delete this._dragOffset;
    },

    _sidebarResizeDrag: function(event)
    {
        var x = event.pageX + this._dragOffset;
        var newWidth = Number.constrain(window.innerWidth - x, Preferences.minScriptsSidebarWidth, window.innerWidth * 0.66);

        this.sidebarElement.style.width = newWidth + "px";
        this.sidebarButtonsElement.style.width = newWidth + "px";
        this.scriptResourceViews.style.right = newWidth + "px";
        this.sidebarResizeWidgetElement.style.right = newWidth + "px";
        this.sidebarResizeElement.style.right = (newWidth - 3) + "px";

        event.preventDefault();
    },

    _updateDebuggerButtons: function()
    {
        if (InspectorController.debuggerAttached()) {
            this.debuggingButton.title = WebInspector.UIString("Stop debugging.");
            this.debuggingButton.addStyleClass("toggled-on");
            this.pauseButton.disabled = false;
        } else {
            this.debuggingButton.title = WebInspector.UIString("Start debugging and reload inspected page.");
            this.debuggingButton.removeStyleClass("toggled-on");
            this.pauseButton.disabled = true;
        }

        if (this._paused) {
            this.pauseButton.addStyleClass("paused");

            this.pauseButton.disabled = false;
            this.stepOverButton.disabled = false;
            this.stepIntoButton.disabled = false;
            this.stepOutButton.disabled = false;

            this.debuggerStatusElement.textContent = WebInspector.UIString("Paused");
        } else {
            this.pauseButton.removeStyleClass("paused");

            this.pauseButton.disabled = this._waitingToPause;
            this.stepOverButton.disabled = true;
            this.stepIntoButton.disabled = true;
            this.stepOutButton.disabled = true;

            if (this._waitingToPause)
                this.debuggerStatusElement.textContent = WebInspector.UIString("Pausing");
            else if (this._stepping)
                this.debuggerStatusElement.textContent = WebInspector.UIString("Stepping");
            else
                this.debuggerStatusElement.textContent = "";
        }
    },

    _toggleDebugging: function()
    {
        this._paused = false;
        this._waitingToPause = false;
        this._stepping = false;

        if (InspectorController.debuggerAttached())
            InspectorController.stopDebugging();
        else
            InspectorController.startDebuggingAndReloadInspectedPage();

        this.sidebarPanes.callstack.update(null);
        this.sidebarPanes.scopechain.update(null);

        this._clearCurrentExecutionLine();
        this._updateDebuggerButtons();
    },

    _togglePause: function()
    {
        if (this._paused) {
            this._paused = false;
            this._waitingToPause = false;
            InspectorController.resumeDebugger();
        } else {
            this._stepping = false;
            this._waitingToPause = true;
            InspectorController.pauseInDebugger();
        }

        this.sidebarPanes.callstack.update(null);
        this.sidebarPanes.scopechain.update(null);

        this._clearCurrentExecutionLine();
        this._updateDebuggerButtons();
    },

    _stepOverClicked: function()
    {
        this._paused = false;
        this._stepping = true;

        InspectorController.stepOverStatementInDebugger();
    },

    _stepIntoClicked: function()
    {
        this._paused = false;
        this._stepping = true;

        InspectorController.stepIntoStatementInDebugger();
    },

    _stepOutClicked: function()
    {
        this._paused = false;
        this._stepping = true;

        InspectorController.stepOutOfFunctionInDebugger();
    }
}

WebInspector.ScriptsPanel.prototype.__proto__ = WebInspector.Panel.prototype;
