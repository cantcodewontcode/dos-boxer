// A RenderBackend that hands finished frames to the embedding host instead of
// drawing them. The host (Swift/Metal) does the scaling and presentation.

#ifndef DOSBOXER_HOST_RENDERER_H
#define DOSBOXER_HOST_RENDERER_H

#include "gui/render/render_backend.h"

#include <vector>

class HostRenderer final : public RenderBackend {
public:
	HostRenderer();
	~HostRenderer() override;

	SDL_Window* GetWindow() override;
	DosBox::Rect GetCanvasSizeInPixels() override;

	void NotifyViewportSizeChanged(const DosBox::Rect draw_rect_px) override;
	void NotifyRenderSizeChanged(const int width_px, const int height_px) override;
	void NotifyVideoModeChanged(const VideoMode& video_mode) override;

	SetShaderResult SetShader(const std::string& symbolic_shader_descriptor) override;
	void ForceReloadCurrentShader() override {}
	ShaderInfo GetCurrentShaderInfo() override { return {}; }
	ShaderPreset GetCurrentShaderPreset() override { return {}; }
	std::string GetCurrentSymbolicShaderDescriptor() override { return {}; }
	ShaderDescriptor GetCurrentShaderDescriptor() override { return {}; }

	void StartFrame(uint32_t*& pixels_out, int& pitch_out) override;
	void EndFrame() override;
	void PrepareFrame() override {}
	void PresentFrame() override;

	void SetVsync(const bool) override {}
	void SetColorSpace(const ColorSpace) override {}
	void EnableImageAdjustments(const bool) override {}
	void SetImageAdjustmentSettings(const ImageAdjustmentSettings&) override {}
	void SetDeditheringStrength(const float) override {}

	RenderedImage ReadPixelsPostShader(const DosBox::Rect output_rect_px) override;

	uint32_t MakePixel(const uint8_t red, const uint8_t green,
	                   const uint8_t blue) override;

	HostRenderer(const HostRenderer&)            = delete;
	HostRenderer& operator=(const HostRenderer&) = delete;

private:
	SDL_Window* window = nullptr;

	int width  = 0;
	int height = 0;
	int pitch  = 0;

	float display_aspect = 4.0f / 3.0f;

	std::vector<uint32_t> curr_framebuf = {};
	std::vector<uint32_t> last_framebuf = {};
};

#endif
