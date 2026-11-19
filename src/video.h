// The 320x200 8-bit screen (VGA mode 13h) and how it reaches the window.
#pragma once
#include <SDL.h>

#include <array>
#include <cstdint>
#include <string>

#include "formats/font.h"
#include "formats/pic.h"

namespace raptua {

constexpr int kScreenW = 320, kScreenH = 200;

struct Clip { int x0 = 0, y0 = 0, x1 = kScreenW, y1 = kScreenH; };

class Screen {
public:
    std::array<uint8_t, kScreenW * kScreenH> px{};
    Palette pal{};
    float fade = 1.0f;   // 0 = black, 1 = full palette
    Clip clip;

    void clear(uint8_t c) { px.fill(c); }
    void rect(int x, int y, int w, int h, uint8_t c);
    void pixel(int x, int y, uint8_t c);
    // flip: bit0 = mirror horizontally, bit1 = vertically.
    // remap: if >= 0, every opaque pixel is drawn with that colour (flash/shadow).
    void pic(const Pic& p, int x, int y, int flip = 0, int remap = -1);
    int text(const Font& f, const std::string& s, int x, int y, int color);   // returns width
    static int text_width(const Font& f, const std::string& s);
};

class Window {
public:
    bool open(const char* title, int scale, bool fullscreen, bool headless);
    void close();
    void present(const Screen& s);
    void toggle_fullscreen();
    // Maps a window position to screen pixels (for the mouse).
    void to_screen(int wx, int wy, int& sx, int& sy) const;
    bool headless() const { return headless_; }

private:
    SDL_Window* win_ = nullptr;
    SDL_Renderer* ren_ = nullptr;
    SDL_Texture* tex_ = nullptr;
    SDL_Rect dst_{0, 0, kScreenW, kScreenH};
    bool headless_ = false;
};

} // namespace raptua
