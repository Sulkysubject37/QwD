#include "imgui.h"
#include "imgui_internal.h"
#include <stdio.h>
#include <string.h>

extern "C" {

bool igBegin(const char* name, bool* p_open, int flags) {
    return ImGui::Begin(name, p_open, flags);
}

void igEnd() {
    ImGui::End();
}

void igText(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    ImGui::TextV(fmt, args);
    va_end(args);
}

void igTextColored(ImVec4 col, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    ImGui::TextColoredV(col, fmt, args);
    va_end(args);
}

bool igButton(const char* label, ImVec2 size) {
    return ImGui::Button(label, size);
}

bool igInputText(const char* label, char* buf, size_t buf_size, int flags, void* callback, void* user_data) {
    return ImGui::InputText(label, buf, buf_size, flags, (ImGuiInputTextCallback)callback, user_data);
}

bool igSliderFloat(const char* label, float* v, float v_min, float v_max, const char* format, int flags) {
    return ImGui::SliderFloat(label, v, v_min, v_max, format, flags);
}

bool igSliderInt(const char* label, int* v, int v_min, int v_max, const char* format, int flags) {
    return ImGui::SliderInt(label, v, v_min, v_max, format, flags);
}

bool igCheckbox(const char* label, bool* v) {
    return ImGui::Checkbox(label, v);
}

void igDummy(ImVec2 size) {
    ImGui::Dummy(size);
}

void igSeparator() {
    ImGui::Separator();
}

void igColumns(int count, const char* id, bool border) {
    ImGui::Columns(count, id, border);
}

void igNextColumn() {
    ImGui::NextColumn();
}

ImGuiIO* igGetIO_Nil() {
    return &ImGui::GetIO();
}

void igSetNextWindowPos(ImVec2 pos, int cond, ImVec2 pivot) {
    ImGui::SetNextWindowPos(pos, cond, pivot);
}

void igSetNextWindowSize(ImVec2 size, int cond) {
    ImGui::SetNextWindowSize(size, cond);
}

#ifndef __EMSCRIPTEN__
const char* qwd_open_file_picker() {
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
const char* qwd_open_file_picker() { return ""; }
#endif

} // extern "C"
