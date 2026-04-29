#include "qwd.h"
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>

#define SOKOL_IMPL
#define SOKOL_APP_IMPL
#define SOKOL_GFX_IMPL
#define SOKOL_GLUE_IMPL
#define SOKOL_LOG_IMPL
#define SOKOL_TIME_IMPL
#include "sokol_app.h"
#include "sokol_gfx.h"
#include "sokol_glue.h"
#include "sokol_log.h"
#include "sokol_time.h"
#include "imgui.h"
#define SIMGUI_IMPL
#include "sokol_imgui.h"

static struct {
    qwd_context_t* qwd;
    qwd_telemetry_t telemetry;
    sg_pass_action pass_action;
    char file_path[1024];
    int threads;
    bool exact_mode;
    int trim_front;
    int trim_tail;
    float min_quality;
    float elapsed_s;
} state;

static void init(void) {
    sg_desc sg_d = { .environment = sglue_environment() };
    sg_setup(&sg_d);
    stm_setup();
    simgui_desc_t simgui_d = {0};
    simgui_setup(&simgui_d);
    
    state.pass_action.colors[0].load_action = SG_LOADACTION_CLEAR;
    state.pass_action.colors[0].clear_value = { 0.01f, 0.01f, 0.01f, 1.0f };
    strcpy(state.file_path, "test_1M.fastq");
    state.qwd = qwd_create();
    
    // Register Telemetry Hook and Initialize Bridge
    qwd_init_state(state.qwd);

    state.threads = 8;
    state.exact_mode = true;
    state.min_quality = 20.0f;
}

static void draw_glass_tile(const char* label, const char* value, ImVec4 color) {
    ImGui::BeginChild(label, {160, 80}, true, ImGuiWindowFlags_NoScrollbar);
    ImGui::TextColored(ImVec4(0.7f, 0.7f, 0.7f, 1.0f), "%s", label);
    ImGui::Separator();
    ImGui::PushStyleColor(ImGuiCol_Text, color);
    ImGui::Text("%s", value);
    ImGui::PopStyleColor();
    ImGui::EndChild();
}

static void draw_distribution_plot(const char* label, uint64_t* data, int count, ImVec4 color, float height) {
    ImGui::TextColored(ImVec4(0.8f, 0.8f, 0.8f, 1.0f), "%s", label);
    ImDrawList* dl = ImGui::GetWindowDrawList();
    ImVec2 cp = ImGui::GetCursorScreenPos();
    ImVec2 sz = ImGui::GetContentRegionAvail();
    sz.y = height;
    uint64_t max_val = 1;
    for (int i = 0; i < count; i++) if (data[i] > max_val) max_val = data[i];
    dl->AddRectFilled(cp, {cp.x + sz.x, cp.y + sz.y}, ImGui::GetColorU32({0.06f, 0.06f, 0.06f, 0.5f}), 8.0f);
    float dx = sz.x / (float)count;
    for (int i = 0; i < count - 1; i++) {
        float y1 = ((float)data[i] / (float)max_val) * (sz.y - 10);
        float y2 = ((float)data[i+1] / (float)max_val) * (sz.y - 10);
        ImVec2 p1 = {cp.x + i * dx, cp.y + sz.y - y1};
        ImVec2 p2 = {cp.x + (i + 1) * dx, cp.y + sz.y - y2};
        dl->AddLine(p1, p2, ImGui::GetColorU32(color), 2.5f);
        dl->AddRectFilled(p1, {p2.x, cp.y + sz.y}, ImGui::GetColorU32({color.x, color.y, color.z, 0.08f}));
    }
    ImGui::Dummy(sz);
}

static void frame(void) {
    float dt = (float)sapp_frame_duration();
    simgui_new_frame({ (int)sapp_width(), (int)sapp_height(), dt });
    
    // FETCH TELEMETRY VIA BRIDGE
    qwd_get_telemetry(state.qwd, &state.telemetry);

    ImGui::SetNextWindowPos({0, 0}, ImGuiCond_Always);
    ImGui::SetNextWindowSize({340, (float)sapp_height()}, ImGuiCond_Always);
    if (ImGui::Begin("MATRIX", NULL, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize)) {
        ImGui::TextColored(ImVec4(0.00f, 1.00f, 0.53f, 1.0f), "QwD GENOMIC WORKSTATION");
        ImGui::Separator();
        ImGui::Text("Source:");
        ImGui::InputText("##path", state.file_path, sizeof(state.file_path));
        if (ImGui::Button("BROWSE DATA", {-1, 30})) {
            const char* picked = qwd_platform_open_file_picker();
            if (picked && picked[0]) strcpy(state.file_path, picked);
        }
        ImGui::Separator();
        ImGui::Text("Laboratory Controls:");
        ImGui::SliderInt("Threads", &state.threads, 1, 32);
        ImGui::Checkbox("Exact Mode", &state.exact_mode);
        ImGui::SliderInt("Trim Front", &state.trim_front, 0, 50);
        ImGui::SliderInt("Trim Tail", &state.trim_tail, 0, 50);
        ImGui::SliderFloat("Min Qual", &state.min_quality, 0.0f, 40.0f, "%.1f");
        
        ImGui::Separator();
        if (state.telemetry.status == 1) {
            state.elapsed_s += dt;
            ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.2f, 0.2f, 0.2f, 1.0f));
            ImGui::Button("ENGINE ACTIVE...", {-1, 60});
            ImGui::PopStyleColor();
        } else {
            if (ImGui::Button("EXECUTE ANALYSIS", {-1, 60})) {
                qwd_set_params(state.qwd, (uint32_t)state.threads, state.exact_mode ? 1 : 0, (uint32_t)state.trim_front, (uint32_t)state.trim_tail, state.min_quality);
                qwd_execute_analysis(state.qwd, state.file_path);
                state.elapsed_s = 0.0f;
            }
        }
        if (ImGui::Button("RESET WORKSTATION", {-1, 40})) {
            qwd_reset_state(state.qwd);
            qwd_init_state(state.qwd);
            state.elapsed_s = 0.0f;
        }
        ImGui::Separator();
        ImGui::Text("Delta: %.2fs", state.elapsed_s);
    }
    ImGui::End();

    ImGui::SetNextWindowPos({350, 10}, ImGuiCond_Always);
    ImGui::SetNextWindowSize({(float)sapp_width() - 360, (float)sapp_height() - 20}, ImGuiCond_Always);
    if (ImGui::Begin("LABORATORY", NULL, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize)) {
        if (ImGui::BeginTabBar("LabTabs")) {
            if (ImGui::BeginTabItem("REAL-TIME METRICS")) {
                char buf[64];
                snprintf(buf, sizeof(buf), "%llu", state.telemetry.read_count);
                draw_glass_tile("READ COUNT", buf, {0.0f, 1.0f, 0.5f, 1.0f});
                ImGui::SameLine();
                snprintf(buf, sizeof(buf), "%.1f GB", (float)state.telemetry.memory_bytes / (1024*1024*1024));
                draw_glass_tile("MEMORY USE", buf, {0.0f, 0.7f, 1.0f, 1.0f});
                ImGui::SameLine();
                snprintf(buf, sizeof(buf), "%llu", state.telemetry.violations);
                draw_glass_tile("INTEGRITY", buf, (state.telemetry.violations > 0) ? ImVec4(1, 0.2, 0.2, 1) : ImVec4(0.5, 1, 0.5, 1));
                
                ImGui::Dummy({0, 20});
                draw_distribution_plot("GC CONTENT PROFILE", state.telemetry.gc_distribution, 101, {0.0f, 0.60f, 1.00f, 1.0f}, 180.0f);
                ImGui::Dummy({0, 10});
                draw_distribution_plot("READ LENGTH MANIFOLD", state.telemetry.length_distribution, 1000, {1.00f, 0.85f, 0.00f, 1.0f}, 180.0f);
                ImGui::EndTabItem();
            }
            if (ImGui::BeginTabItem("QUALITY HEATMAP")) {
                ImDrawList* dl = ImGui::GetWindowDrawList();
                ImVec2 cp = ImGui::GetCursorScreenPos();
                ImVec2 sz = ImGui::GetContentRegionAvail();
                float cw = sz.x / 150.0f;
                float ch = sz.y / 42.0f;
                for (int x = 0; x < 150; x++) {
                    for (int y = 0; y < 42; y++) {
                        uint64_t val = state.telemetry.quality_heatmap[x * 42 + y];
                        if (val > 0) {
                            float alpha = fminf((float)val / 200.0f, 1.0f);
                            ImVec4 col = (y < 20) ? ImVec4(1, 0.2, 0.2, alpha) : (y < 30) ? ImVec4(1, 0.8, 0.0, alpha) : ImVec4(0, 1, 0.5, alpha);
                            dl->AddRectFilled({cp.x + x * cw, cp.y + sz.y - (y+1) * ch}, {cp.x + (x+1) * cw, cp.y + sz.y - y * ch}, ImGui::GetColorU32(col));
                        }
                    }
                }
                ImGui::EndTabItem();
            }
            ImGui::EndTabBar();
        }
    }
    ImGui::End();

    sg_begin_pass({ .action = state.pass_action, .swapchain = sglue_swapchain() });
    simgui_render();
    sg_end_pass();
    sg_commit();
}

static void cleanup(void) {
    qwd_destroy(state.qwd);
    simgui_shutdown();
    sg_shutdown();
}

static void event_wrapper(const sapp_event* ev) {
    simgui_handle_event(ev);
}

sapp_desc sokol_main(int argc, char* argv[]) {
    (void)argc; (void)argv;
    sapp_desc d = {0};
    d.init_cb = init;
    d.frame_cb = frame;
    d.cleanup_cb = cleanup;
    d.event_cb = event_wrapper;
    d.width = 1400;
    d.height = 900;
    d.window_title = "QwD Workstation v3.8.2-restored";
    d.logger.func = slog_func;
    return d;
}
