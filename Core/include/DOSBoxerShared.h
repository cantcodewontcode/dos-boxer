// DOSBoxerShared — the frame buffer shared between the DOS Boxer app and its
// emulator helper process.
//
// The helper writes finished frames into a memory-mapped file; the app reads
// the newest one on each display refresh. Three slots let the writer fill one
// while the reader uses another. Each slot is guarded by a sequence number
// (odd while being written), so a reader can detect and skip a torn frame.
// No locks; safe across processes.

#ifndef DOSBOXER_SHARED_H
#define DOSBOXER_SHARED_H

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#define DBX_SHARED_MAGIC 0x44425853u /* "DBXS" */
#define DBX_SHARED_SLOTS 3
/// Largest frame we carry: 2048 × 1536 × 4 bytes (beyond any DOS video mode).
#define DBX_SHARED_MAX_FRAME_BYTES (2048u * 1536u * 4u)

typedef struct {
	uint64_t sequence; // odd while the writer is filling the slot
	int32_t width;
	int32_t height;
	int32_t bytes_per_row;
	float display_aspect;
} DBXSharedSlot;

typedef struct {
	uint32_t magic;
	uint32_t latest_slot; // slot holding the newest complete frame
	uint64_t frame_count; // increments with every published frame
	DBXSharedSlot slots[DBX_SHARED_SLOTS];
} DBXSharedHeader;

/// Bytes to allocate for the whole shared region.
static inline uint64_t dbx_shared_size(void)
{
	return sizeof(DBXSharedHeader) +
	       (uint64_t)DBX_SHARED_SLOTS * DBX_SHARED_MAX_FRAME_BYTES;
}

static inline uint8_t* dbx_shared_pixels(void* base, uint32_t slot)
{
	return (uint8_t*)base + sizeof(DBXSharedHeader) +
	       (uint64_t)slot * DBX_SHARED_MAX_FRAME_BYTES;
}

static inline void dbx_shared_init(void* base)
{
	memset(base, 0, sizeof(DBXSharedHeader));
	((DBXSharedHeader*)base)->magic = DBX_SHARED_MAGIC;
}

/// Writer: copies a frame into the next slot and makes it the latest.
static inline void dbx_shared_publish(void* base, const uint8_t* pixels,
                                      int32_t width, int32_t height,
                                      int32_t bytes_per_row, float display_aspect)
{
	DBXSharedHeader* header = (DBXSharedHeader*)base;
	const uint64_t byte_count = (uint64_t)bytes_per_row * (uint64_t)height;
	if (width <= 0 || height <= 0 || byte_count > DBX_SHARED_MAX_FRAME_BYTES) {
		return;
	}
	const uint32_t latest = __atomic_load_n(&header->latest_slot, __ATOMIC_ACQUIRE);
	const uint32_t slot   = (latest + 1) % DBX_SHARED_SLOTS;
	DBXSharedSlot* info   = &header->slots[slot];

	__atomic_fetch_add(&info->sequence, 1, __ATOMIC_ACQ_REL); // now odd
	memcpy(dbx_shared_pixels(base, slot), pixels, byte_count);
	info->width          = width;
	info->height         = height;
	info->bytes_per_row  = bytes_per_row;
	info->display_aspect = display_aspect;
	__atomic_fetch_add(&info->sequence, 1, __ATOMIC_ACQ_REL); // even again

	__atomic_store_n(&header->latest_slot, slot, __ATOMIC_RELEASE);
	__atomic_fetch_add(&header->frame_count, 1, __ATOMIC_RELEASE);
}

/// Reader: total frames published so far (to skip unchanged refreshes).
static inline uint64_t dbx_shared_frame_count(const void* base)
{
	return __atomic_load_n(&((const DBXSharedHeader*)base)->frame_count, __ATOMIC_ACQUIRE);
}

/// Reader: describes the newest frame. Returns false if none is ready.
/// Pass `sequence_out` to `dbx_shared_is_unchanged` after copying the pixels.
static inline bool dbx_shared_latest(void* base, DBXSharedSlot* info_out,
                                     const uint8_t** pixels_out,
                                     uint32_t* slot_out, uint64_t* sequence_out)
{
	DBXSharedHeader* header = (DBXSharedHeader*)base;
	if (header->magic != DBX_SHARED_MAGIC || dbx_shared_frame_count(base) == 0) {
		return false;
	}
	const uint32_t slot   = __atomic_load_n(&header->latest_slot, __ATOMIC_ACQUIRE);
	const uint64_t before = __atomic_load_n(&header->slots[slot].sequence, __ATOMIC_ACQUIRE);
	if (before & 1) {
		return false; // being rewritten right now; try next refresh
	}
	*info_out     = header->slots[slot];
	*pixels_out   = dbx_shared_pixels(base, slot);
	*slot_out     = slot;
	*sequence_out = before;
	return info_out->width > 0;
}

/// Reader: true if the slot wasn't touched while we were copying it.
static inline bool dbx_shared_is_unchanged(const void* base, uint32_t slot, uint64_t sequence)
{
	const DBXSharedHeader* header = (const DBXSharedHeader*)base;
	return __atomic_load_n(&header->slots[slot].sequence, __ATOMIC_ACQUIRE) == sequence;
}

// --- Commands from the app to the helper (over the helper's stdin) ----------

typedef enum : int32_t {
	DBXCommandKey         = 1, // a = scancode, b = 1 down / 0 up
	DBXCommandMouseMotion = 2, // a, b = dx, dy in 1/100 points
	DBXCommandMouseButton = 3, // a = button (1 left, 2 middle, 3 right), b = down
	DBXCommandQuit        = 4,
	DBXCommandMountFolder = 5, // a = drive letter, b = byte count of the
	                           // security-scoped bookmark that follows
} DBXCommandType;

/// Largest payload a command may carry (a folder bookmark).
#define DBX_COMMAND_MAX_PAYLOAD 65536

typedef struct {
	int32_t type;
	int32_t a;
	int32_t b;
} DBXCommand;

#endif
