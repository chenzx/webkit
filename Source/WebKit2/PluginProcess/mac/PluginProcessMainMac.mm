/*
 * Copyright (C) 2010, 2011 Apple Inc. All rights reserved.
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
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "config.h"
#import "PluginProcessMain.h"

#if ENABLE(PLUGIN_PROCESS)

#import "CommandLine.h"
#import "EnvironmentUtilities.h"
#import "NetscapePluginModule.h"
#import "PluginProcess.h"
#import "WebKit2Initialize.h"
#import <Foundation/NSUserDefaults.h>
#import <WebCore/RunLoop.h>
#import <WebKitSystemInterface.h>
#import <mach/mach_error.h>
#import <servers/bootstrap.h>
#import <stdio.h>
#import <wtf/RetainPtr.h>
#import <wtf/text/CString.h>
#import <wtf/text/WTFString.h>

#define SHOW_CRASH_REPORTER 1

using namespace WebCore;

namespace WebKit {

// FIXME: There is much code here that is duplicated in WebProcessMainMac.mm, we should add a shared base class where
// we can put everything.

int PluginProcessMain(const CommandLine& commandLine)
{
    // Remove the PluginProcess shim from the DYLD_INSERT_LIBRARIES environment variable so any processes 
    // spawned by the PluginProcess don't try to insert the shim and crash.
    EnvironmentUtilities::stripValuesEndingWithString("DYLD_INSERT_LIBRARIES", "/PluginProcessShim.dylib");

    // Check if we're being spawned to write a MIME type preferences file.
    String pluginPath = commandLine["createPluginMIMETypesPreferences"];
    if (!pluginPath.isEmpty()) {
        InitializeWebKit2();

        if (!NetscapePluginModule::createPluginMIMETypesPreferences(pluginPath))
            return EXIT_FAILURE;

        return EXIT_SUCCESS;
    }

    String serviceName = commandLine["servicename"];
    if (serviceName.isEmpty())
        return EXIT_FAILURE;
    
    // Get the server port.
    mach_port_t serverPort;
    kern_return_t kr = bootstrap_look_up(bootstrap_port, serviceName.utf8().data(), &serverPort);
    if (kr) {
        WTFLogAlways("bootstrap_look_up result: %s (%x)\n", mach_error_string(kr), kr);
        return EXIT_FAILURE;
    }

    String localization = commandLine["localization"];
    if (!localization.isEmpty()) {
        RetainPtr<CFStringRef> cfLocalization(AdoptCF, CFStringCreateWithCharacters(0, reinterpret_cast<const UniChar*>(localization.characters()), localization.length()));
        WKSetDefaultLocalization(cfLocalization.get());
    }

#if defined(__i386__)
    {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

        NSDictionary *defaults = [[NSDictionary alloc] initWithObjectsAndKeys:[NSNumber numberWithBool:YES], @"AppleMagnifiedMode", nil];
        [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
        [defaults release];

        [pool drain];
    }
#endif

#if !SHOW_CRASH_REPORTER
    // Installs signal handlers that exit on a crash so that CrashReporter does not show up.
    signal(SIGILL, _exit);
    signal(SIGFPE, _exit);
    signal(SIGBUS, _exit);
    signal(SIGSEGV, _exit);
#endif

    @autoreleasepool {
        InitializeWebKit2();

        ChildProcessInitializationParameters parameters;
        parameters.uiProcessName = commandLine["ui-process-name"];
        parameters.clientIdentifier = commandLine["client-identifier"];
        parameters.connectionIdentifier = CoreIPC::Connection::Identifier(serverPort);

        PluginProcess::shared().initialize(parameters);

        [NSApplication sharedApplication];
    }

    RunLoop::run();
    
#if __MAC_OS_X_VERSION_MIN_REQUIRED >= 1080
    // If we have private temporary and cache directories, clean them up.
    if (getenv("DIRHELPER_USER_DIR_SUFFIX")) {
        char darwinDirectory[PATH_MAX];
        if (confstr(_CS_DARWIN_USER_TEMP_DIR, darwinDirectory, sizeof(darwinDirectory)))
            [[NSFileManager defaultManager] removeItemAtPath:[[NSFileManager defaultManager] stringWithFileSystemRepresentation:darwinDirectory length:strlen(darwinDirectory)] error:nil];
        if (confstr(_CS_DARWIN_USER_CACHE_DIR, darwinDirectory, sizeof(darwinDirectory)))
            [[NSFileManager defaultManager] removeItemAtPath:[[NSFileManager defaultManager] stringWithFileSystemRepresentation:darwinDirectory length:strlen(darwinDirectory)] error:nil];
    }
#endif

    return 0;
}

}

#endif // ENABLE(PLUGIN_PROCESS)
