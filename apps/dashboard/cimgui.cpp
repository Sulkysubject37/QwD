#include <stdio.h>
#include <string.h>

#ifndef __EMSCRIPTEN__
extern "C" const char* qwd_open_file_picker() {
    static char path[1024];
    FILE* pipe = popen("osascript -e 'POSIX path of (choose file with prompt \"Select Genomic Data\")' 2>/dev/null", "r");
    if (!pipe) return "";
    
    if (fgets(path, sizeof(path), pipe) != NULL) {
        char* newline = strchr(path, '\n');
        if (newline) *newline = '\0';
        pclose(pipe);
        return path;
    }
    
    pclose(pipe);
    return "";
}
#else
extern "C" const char* qwd_open_file_picker() { return ""; }
#endif
