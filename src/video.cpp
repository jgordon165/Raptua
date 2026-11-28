#include "video.h"
#include "builtin_font.h"

#include <algorithm>

namespace raptua {

void Screen::rect(int x, int y, int w, int h, uint8_t c) {
    int x0 = std::max(x, clip.x0), y0 = std::max(y, clip.y0);
    int x1 = std::min(x + w, clip.x1), y1 = std::min(y + h, clip.y1);
    for (int yy = y0; yy < y1; ++yy)
        std::fill(px.begin() + yy * kScreenW + x0, px.begin() + yy * kScreenW + std::max(x0, x1), c);
}

void Screen::pixel(int x, int y, uint8_t c) {
    if (x >= clip.x0 && x < clip.x1 && y >= clip.y0 && y < clip.y1) px[size_t(y * kScreenW + x)] = c;
}

void Screen::pic(const Pic& p, int x, int y, int flip, int remap, const uint8_t* lut) {
    auto put = [&](int sx, int sy, uint8_t v) {
        int dx = (flip & 1) ? x + p.width - 1 - sx : x + sx;
        int dy = (flip & 2) ? y + p.height - 1 - sy : y + sy;
        if (dx < clip.x0 || dx >= clip.x1 || dy < clip.y0 || dy >= clip.y1) return;
        px[size_t(dy * kScreenW + dx)] = remap >= 0 ? uint8_t(remap) : lut ? lut[v] : v;
    };
    if (!p.sprite) {
        // Fast path for unflipped opaque images (tiles, backgrounds).
        if (flip == 0 && remap < 0 && !lut) {
            int sx0 = std::max(0, clip.x0 - x), sx1 = std::min(p.width, clip.x1 - x);
            if (sx1 <= sx0) return;
            for (int sy = std::max(0, clip.y0 - y); sy < std::min(p.height, clip.y1 - y); ++sy)
                std::copy_n(p.pixels.begin() + sy * p.width + sx0, sx1 - sx0,
                            px.begin() + (y + sy) * kScreenW + x + sx0);
            return;
        }
        for (int sy = 0; sy < p.height; ++sy)
            for (int sx = 0; sx < p.width; ++sx) put(sx, sy, p.pixels[size_t(sy * p.width + sx)]);
        return;
    }
    for (const Span& s : p.spans)
        for (int i = 0; i < s.count; ++i) put(s.x + i, s.y, p.pixels[s.offset + size_t(i)]);
}

int Screen::text(const Font& f, const std::string& s, int x, int y, int color, bool base_mode) {
    int x0 = x;
    for (unsigned char c : s) {
        if (!f.has(c)) { x += f.width[' '] ? f.width[' '] : f.height / 2; continue; }
        int w = f.width[c];
        const uint8_t* g = f.pixels.data() + f.offset[c];
        for (int yy = 0; yy < f.height; ++yy)
            for (int xx = 0; xx < w; ++xx) {
                uint8_t v = g[yy * w + xx];
                if (!v) continue;
                uint8_t c = base_mode ? uint8_t(v + color) : color >= 0 ? uint8_t(color) : v;
                pixel(x + xx, y + yy, c);
            }
        x += w + 1;
    }
    return x - x0;
}

void Screen::build_shades() {
    static const float kScale[5] = {0.45f, 0.70f, 1.0f, 1.30f, 1.65f};
    for (int l = 0; l < 5; ++l) {
        for (int i = 0; i < 256; ++i) {
            float r = pal[size_t(i * 3)] * kScale[l], g = pal[size_t(i * 3 + 1)] * kScale[l], b = pal[size_t(i * 3 + 2)] * kScale[l];
            if (l > 2) { r += 12 * (l - 2); g += 12 * (l - 2); b += 12 * (l - 2); }
            int best = i;
            float bd = 1e30f;
            for (int j = 0; j < 256; ++j) {
                float dr = pal[size_t(j * 3)] - r, dg = pal[size_t(j * 3 + 1)] - g, db = pal[size_t(j * 3 + 2)] - b;
                float dist = dr * dr + dg * dg + db * db;
                if (dist < bd) { bd = dist; best = j; }
            }
            shades_[size_t(l)][size_t(i)] = uint8_t(best);
        }
    }
    shade_valid_ = true;
}

void Screen::shade(int x, int y, int w, int h, int level) {
    if (!shade_valid_) build_shades();
    const auto& lut = shades_[size_t(std::clamp(level, -2, 2) + 2)];
    int x0 = std::max(x, clip.x0), y0 = std::max(y, clip.y0);
    int x1 = std::min(x + w, clip.x1), y1 = std::min(y + h, clip.y1);
    for (int yy = y0; yy < y1; ++yy)
        for (int xx = x0; xx < x1; ++xx) {
            uint8_t& p = px[size_t(yy * kScreenW + xx)];
            p = lut[p];
        }
}

int Screen::text_width(const Font& f, const std::string& s) {
    int w = 0;
    for (unsigned char c : s) w += f.has(c) ? f.width[c] + 1 : (f.width[' '] ? f.width[' '] : f.height / 2);
    return w;
}

bool Window::open(const char* title, int scale, bool fullscreen, bool headless) {
    headless_ = headless;
    if (headless) return true;
    // VGA mode 13h was shown on a 4:3 monitor: 320x200 pixels stretched to
    // 320x240 shape.
    Uint32 flags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI;
    if (fullscreen) flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
    win_ = SDL_CreateWindow(title, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                            kScreenW * scale, 240 * scale, flags);
    if (!win_) return false;
    ren_ = SDL_CreateRenderer(win_, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!ren_) ren_ = SDL_CreateRenderer(win_, -1, SDL_RENDERER_SOFTWARE);
    if (!ren_) return false;
    tex_ = SDL_CreateTexture(ren_, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, kScreenW, kScreenH);
    return tex_ != nullptr;
}

void Window::close() {
    if (tex_) SDL_DestroyTexture(tex_);
    if (ren_) SDL_DestroyRenderer(ren_);
    if (win_) SDL_DestroyWindow(win_);
    tex_ = nullptr; ren_ = nullptr; win_ = nullptr;
}

void Window::toggle_fullscreen() {
    if (!win_) return;
    bool fs = SDL_GetWindowFlags(win_) & SDL_WINDOW_FULLSCREEN_DESKTOP;
    SDL_SetWindowFullscreen(win_, fs ? 0 : SDL_WINDOW_FULLSCREEN_DESKTOP);
}

void Window::present(const Screen& s) {
    if (headless_ || !tex_) return;
    std::array<uint32_t, 256> lut;
    int f = int(std::clamp(s.fade, 0.0f, 1.0f) * 256.0f);
    for (int i = 0; i < 256; ++i) {
        uint32_t r = uint32_t(s.pal[size_t(i * 3)] * f >> 8);
        uint32_t g = uint32_t(s.pal[size_t(i * 3 + 1)] * f >> 8);
        uint32_t b = uint32_t(s.pal[size_t(i * 3 + 2)] * f >> 8);
        lut[size_t(i)] = 0xFF000000u | r << 16 | g << 8 | b;
    }
    // Converted into our own buffer, then one SDL_UpdateTexture: the path
    // every renderer handles alike (the Xbox 360's GPU renderer uploads whole
    // rows straight from it; a lock goes through a shadow copy read back
    // from the GPU).
    frame_.resize(size_t(kScreenW) * kScreenH);
    for (size_t i = 0; i < frame_.size(); ++i) frame_[i] = lut[s.px[i]];
    SDL_UpdateTexture(tex_, nullptr, frame_.data(), kScreenW * 4);
    int ow, oh;
    SDL_GetRendererOutputSize(ren_, &ow, &oh);
    // Largest 4:3 rectangle that fits.
    int w = ow, h = ow * 3 / 4;
    if (h > oh) { h = oh; w = oh * 4 / 3; }
    dst_ = {(ow - w) / 2, (oh - h) / 2, w, h};
    SDL_SetRenderDrawColor(ren_, 0, 0, 0, 255);
    SDL_RenderClear(ren_);
    SDL_RenderCopy(ren_, tex_, nullptr, &dst_);
    SDL_RenderPresent(ren_);
}

void Window::to_screen(int wx, int wy, int& sx, int& sy) const {
    int ww = 1, wh = 1, ow = 1, oh = 1;
    if (win_) { SDL_GetWindowSize(win_, &ww, &wh); SDL_GetRendererOutputSize(ren_, &ow, &oh); }
    float px = float(wx) * float(ow) / float(ww), py = float(wy) * float(oh) / float(wh);
    sx = dst_.w ? int((px - float(dst_.x)) * kScreenW / float(dst_.w)) : 0;
    sy = dst_.h ? int((py - float(dst_.y)) * kScreenH / float(dst_.h)) : 0;
    sx = std::clamp(sx, 0, kScreenW - 1);
    sy = std::clamp(sy, 0, kScreenH - 1);
}

} // namespace raptua

namespace raptua {

int Screen::sys_text(const std::string& s, int x, int y, uint8_t color) {
    int cx = x;
    for (unsigned char ch : s) {
        if (ch < 32 || ch > 126) ch = '?';
        const uint8_t* g = kSysFont[ch - 32];
        for (int r = 0; r < kSysFontH; ++r)
            for (int b = 0; b < kSysFontW; ++b)
                if (g[r] & (0x80 >> b)) pixel(cx + b, y + r, color);
        cx += kSysFontW;
    }
    return cx - x;
}

} // namespace raptua
