#ifndef GHOSTX_BRIDGE_H
#define GHOSTX_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

// Terminal lifecycle
void* ghostx_terminal_new(uint16_t cols, uint16_t rows, uint32_t max_scrollback);
void  ghostx_terminal_free(void* terminal);
void  ghostx_terminal_vt_write(void* terminal, const uint8_t* data, size_t len);
void  ghostx_terminal_resize(void* terminal, uint16_t cols, uint16_t rows, uint32_t cell_w, uint32_t cell_h);
void  ghostx_terminal_set_write_pty_callback(void* terminal, void* userdata, void (*cb)(void*, const uint8_t*, size_t));
void  ghostx_terminal_set_title_callback(void* terminal, void (*cb)(void*, const char*, size_t));

// Render state
void* ghostx_render_state_new(void);
void  ghostx_render_state_free(void* state);
void  ghostx_render_state_update(void* state, void* terminal);

// Row iterator
void* ghostx_row_iterator_new(void);
void  ghostx_row_iterator_free(void* iter);
void* ghostx_row_cells_new(void);
void  ghostx_row_cells_free(void* cells);

bool ghostx_render_state_get_rows(void* state, void* row_iter, void* row_cells,
    void (*row_callback)(void* ctx, uint32_t row, void* cells), void* ctx);

// Cell data
bool     ghostx_cells_next(void* cells);
uint32_t ghostx_cell_grapheme_len(void* cells);
uint32_t ghostx_cell_graphemes(void* cells, uint32_t* out, uint32_t max_len);
void     ghostx_cell_fg_color(void* cells, uint8_t* r, uint8_t* g, uint8_t* b);
void     ghostx_cell_bg_color(void* cells, uint8_t* r, uint8_t* g, uint8_t* b);
uint32_t ghostx_cell_flags(void* cells);

// Key encoder
void* ghostx_key_encoder_new(void);
void  ghostx_key_encoder_free(void* encoder);
void  ghostx_key_encoder_sync(void* encoder, void* terminal);
void  ghostx_terminal_scroll_viewport(void* terminal, int32_t delta);

#endif
