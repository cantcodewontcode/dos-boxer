// Headless smoke test for the host API: boots DOS, saves a frame as a PPM
// image, pulls some audio and shuts down cleanly.
//
// Usage: headless_test <output dir> [--restart | dosbox args...]
// Set DBX_TEST_MOUNT=<folder> to mount that folder as C: while DOS runs, or
// DBX_TEST_TRIGGER=<action> to run a built-in action like "cycleup".
//
// Pass --restart to also try a second run in the same process. That's known
// to fail (dosbox-staging keeps process-wide state, so the second run never
// draws), which is why the app runs each session in its own engine process.
//
// Build & run: Scripts/test-core.sh

#include "DOSBoxerHost.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <unistd.h>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

std::mutex frame_mutex;
std::vector<uint8_t> last_frame;
int frame_w = 0, frame_h = 0, frame_pitch = 0;
float frame_aspect = 0;
std::atomic<int> frame_count = 0;
std::atomic<bool> exited = false;
std::atomic<int> exit_code = -1;

void on_frame(void*, const DBXFrame* f)
{
	std::lock_guard lock(frame_mutex);
	last_frame.assign(f->pixels, f->pixels + f->bytes_per_row * f->height);
	frame_w = f->width; frame_h = f->height; frame_pitch = f->bytes_per_row;
	frame_aspect = f->display_aspect;
	++frame_count;
}

void on_exit(void*, int32_t code)
{
	exit_code = code;
	exited    = true;
}

bool save_ppm(const char* path)
{
	std::lock_guard lock(frame_mutex);
	if (last_frame.empty()) return false;
	FILE* file = fopen(path, "wb");
	if (!file) return false;
	fprintf(file, "P6\n%d %d\n255\n", frame_w, frame_h);
	for (int y = 0; y < frame_h; ++y) {
		const uint8_t* row = last_frame.data() + y * frame_pitch;
		for (int x = 0; x < frame_w; ++x) {
			const uint8_t rgb[3] = {row[x * 4 + 2], row[x * 4 + 1], row[x * 4 + 0]};
			fwrite(rgb, 1, 3, file);
		}
	}
	fclose(file);
	return true;
}

// Extra dosbox arguments (e.g. to mount and run a game); empty for the default
std::vector<const char*> custom_args;

bool run_once(int run, const char* image_path)
{
	frame_count = 0;
	exited      = false;
	std::vector<const char*> args = {"-c", "VER", "-c", "ECHO DOS Boxer headless test"};
	if (!custom_args.empty()) {
		args = custom_args;
	}
	if (!dbx_start(args.data(), static_cast<int32_t>(args.size()), on_frame, on_exit, nullptr)) {
		printf("run %d: dbx_start failed\n", run);
		return false;
	}
	if (const char* action = getenv("DBX_TEST_TRIGGER")) {
		// Action test: run a built-in action (e.g. cycleup) once DOS is up
		std::this_thread::sleep_for(std::chrono::seconds(2));
		dbx_trigger(action);
		std::this_thread::sleep_for(std::chrono::seconds(2));
	} else if (const char* folder = getenv("DBX_TEST_MOUNT")) {
		// Live-mount test: mount a folder as C: once DOS is up
		std::this_thread::sleep_for(std::chrono::seconds(2));
		dbx_mount_folder('C', folder);
		std::this_thread::sleep_for(std::chrono::seconds(2));
	} else {
		std::this_thread::sleep_for(std::chrono::seconds(custom_args.empty() ? 4 : 10));
	}

	std::vector<float> audio(2 * 1024);
	dbx_pull_audio(audio.data(), 1024);

	const bool still_running = dbx_is_running();
	const bool saved = save_ppm(image_path);
	printf("run %d: %s, %d frames, last %dx%d (aspect %.3f), image %s\n",
	       run, still_running ? "running" : "ALREADY STOPPED", frame_count.load(), frame_w, frame_h, frame_aspect,
	       saved ? image_path : "NOT saved");

	dbx_request_quit();
	for (int i = 0; i < 100 && !exited; ++i) {
		std::this_thread::sleep_for(std::chrono::milliseconds(50));
	}
	printf("run %d: %s (exit code %d)\n", run,
	       exited ? "stopped" : "DID NOT STOP", exit_code.load());
	return saved && exited && frame_count > 0;
}

} // namespace

int main(int argc, char* argv[])
{
	const std::string out_dir = argc > 1 ? argv[1] : ".";
	const bool try_restart = argc > 2 && std::string(argv[2]) == "--restart";
	if (argc > 2 && !try_restart) {
		custom_args.assign(argv + 2, argv + argc);
	}
	bool ok = run_once(1, (out_dir + "/run1.ppm").c_str());
	if (ok && try_restart) {
		ok = run_once(2, (out_dir + "/run2.ppm").c_str());
	}
	printf("%s\n", ok ? "PASS" : "FAIL");
	fflush(stdout);
	// Skip static destructors: the core's atexit handlers aren't safe after
	// it has shut down on another thread.
	_exit(ok ? 0 : 1);
}
