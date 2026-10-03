#include "host_renderer.h"
#include "host_state.h"

#include <SDL.h>

#include <cassert>
#include <cstring>
#include <stdexcept>

// The emulator computes its aspect-correct draw rectangle inside this canvas;
// we only use the rectangle's proportions; the host does the real scaling.
static constexpr int CanvasWidth  = 1600;
static constexpr int CanvasHeight = 1200;

HostRenderer::HostRenderer()
{
	// With SDL's dummy video driver this window is never shown; parts of
	// the core still expect a window handle to exist.
	window = SDL_CreateWindow("DOS Boxer",
	                          SDL_WINDOWPOS_UNDEFINED,
	                          SDL_WINDOWPOS_UNDEFINED,
	                          CanvasWidth,
	                          CanvasHeight,
	                          SDL_WINDOW_HIDDEN);
	if (!window) {
		throw std::runtime_error(SDL_GetError());
	}
}

HostRenderer::~HostRenderer()
{
	if (window) {
		SDL_DestroyWindow(window);
	}
}

SDL_Window* HostRenderer::GetWindow()
{
	return window;
}

DosBox::Rect HostRenderer::GetCanvasSizeInPixels()
{
	return {CanvasWidth, CanvasHeight};
}

void HostRenderer::NotifyViewportSizeChanged(const DosBox::Rect draw_rect_px)
{
	if (draw_rect_px.h > 0) {
		display_aspect = draw_rect_px.w / draw_rect_px.h;
	}
}

void HostRenderer::NotifyRenderSizeChanged(const int width_px, const int height_px)
{
	width  = width_px;
	height = height_px;
	pitch  = width_px * static_cast<int>(sizeof(uint32_t));

	const auto pixel_count = static_cast<size_t>(width_px) * height_px;
	curr_framebuf.assign(pixel_count, 0);
	last_framebuf.assign(pixel_count, 0);
}

void HostRenderer::NotifyVideoModeChanged(const VideoMode&) {}

RenderBackend::SetShaderResult HostRenderer::SetShader(const std::string&)
{
	return SetShaderResult::Ok;
}

void HostRenderer::StartFrame(uint32_t*& pixels_out, int& pitch_out)
{
	pixels_out = curr_framebuf.data();
	pitch_out  = pitch;
}

void HostRenderer::EndFrame()
{
	// Copy so the VGA emulation can't tear the frame while it's presented
	last_framebuf = curr_framebuf;
}

void HostRenderer::PresentFrame()
{
	if (last_framebuf.empty()) {
		return;
	}
	const DBXFrame frame = {reinterpret_cast<const uint8_t*>(last_framebuf.data()),
	                        width,
	                        height,
	                        pitch,
	                        display_aspect};
	dosboxer::deliver_frame(frame);
}

RenderedImage HostRenderer::ReadPixelsPostShader(const DosBox::Rect)
{
	// Screenshots of the post-shader image aren't supported yet; the core
	// falls back to its raw image capture.
	return {};
}

uint32_t HostRenderer::MakePixel(const uint8_t red, const uint8_t green,
                                 const uint8_t blue)
{
	// ARGB8888 as a 32-bit value = BGRA bytes in memory on little-endian
	return (blue << 0) | (green << 8) | (red << 16) | (255u << 24);
}
