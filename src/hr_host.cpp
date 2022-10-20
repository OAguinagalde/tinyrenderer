#define CR_HOST // required in the host only and before including cr.h
#include "../../cr/cr.h"

#define WIN32_EXTERNALDLL
#include "win32.h"

#include "util.h"

// the host application should initalize a plugin with a context, a plugin
static cr_plugin ctx;

bool window_callback(HWND window, UINT messageType, WPARAM param1, LPARAM param2) {
    return false;
}

bool onUpdate(double dt_ms, unsigned long long fps) {
    // call the update function at any frequency matters to you, this will give
    // the real application a chance to run
    return cr_plugin_update(ctx);
}

int main(int argc, char** argv) {
    srand(time(NULL));

    // the full path to the live-reloadable application
    cr_plugin_open(ctx, "c:/users/oscara/git_projects/tinyrenderer/bin/hr_app.dll");

    // at the end do not forget to cleanup the plugin context
    defer _1([]{ cr_plugin_close(ctx); });

    /* window scope */ {
        auto window = win32::NewWindow("myWindow", "tinyrenderer", 100, 100, 10, 10, &window_callback);
        defer _2([window]() { win32::CleanWindow("myWindow", window); });

        bool haveConsole = true;
        if (win32::ConsoleAttach() != win32::ConsoleAttachResult::SUCCESS) {
            haveConsole = false;
            if (win32::ConsoleCreate() == win32::ConsoleCreateResult::SUCCESS) {
                auto consoleWindow = win32::ConsoleGetWindow();
                //win32::SetWindowPosition(consoleWindow, x+w, y);
                haveConsole = true;
            }
        }
        defer _3([haveConsole]() { if (haveConsole) win32::ConsoleFree(); });

        win32::NewWindowLoopStart(window, onUpdate);
        
        win32::CleanWindowRenderTarget();
    }
}
