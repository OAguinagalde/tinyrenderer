// cl /D_USRDLL /D_WINDLL src\client.cpp /Fo".\obj\" /Fd".\obj\" /nologo /Od /EHsc /link /DLL /OUT:.\bin\client.dll
#include "../../cr/cr.h"
#include <stdio.h>
#include <assert.h>

int on_load() {
    printf("on_load\n");
    return 1;
}
int on_unload() {
    printf("on_unload\n");
    return 1;
}
int on_update() {
    // printf("on_update\n");
    return 1;
}
int on_close() {
    printf("on_close\n");
    return 1;
}

CR_EXPORT int cr_main(cr_plugin* ctx, cr_op operation) {

    printf("%d\n", operation);
    assert(ctx);

    switch (operation) {

        case CR_LOAD: { // loading back from a reload
            return on_load();

        } break;

        case CR_UNLOAD: { // preparing to a new reload
            return on_unload();

        } break;

        case CR_CLOSE: { // the plugin will close and not reload anymore
            return on_close();

        } break;

    };

    // CR_STEP
    return on_update();
}
