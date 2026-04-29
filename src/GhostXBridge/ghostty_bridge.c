#include <ghostty/vt/terminal.h>
#include <ghostty/vt/render.h>
#include <ghostty/vt/key.h>
#include <ghostty/vt/mouse.h>
#include <ghostty/vt/focus.h>
#include <ghostty/vt/color.h>
#include <ghostty/vt/sys.h>
#include <stdlib.h>
#include <string.h>

// --- Terminal lifecycle ---

void* ghostx_terminal_new(uint16_t cols, uint16_t rows, uint32_t max_scrollback) {
    GhosttyTerminalOptions opts = {
        .cols = cols,
        .rows = rows,
        .max_scrollback = max_scrollback,
    };
    GhosttyTerminal terminal = NULL;
    GhosttyResult err = ghostty_terminal_new(NULL, &terminal, opts);
    if (err != GHOSTTY_SUCCESS) return NULL;
    return (void*)terminal;
}

void ghostx_terminal_free(void* terminal) {
    if (terminal) ghostty_terminal_free((GhosttyTerminal)terminal);
}

void ghostx_terminal_vt_write(void* terminal, const uint8_t* data, size_t len) {
    ghostty_terminal_vt_write((GhosttyTerminal)terminal, data, len);
}

void ghostx_terminal_resize(void* terminal, uint16_t cols, uint16_t rows, uint32_t cell_w, uint32_t cell_h) {
    ghostty_terminal_resize((GhosttyTerminal)terminal, cols, rows, cell_w, cell_h);
}

// --- Effects: write-to-pty callback ---

static void (*ghostx_pty_write_cb)(void* userdata, const uint8_t* data, size_t len) = NULL;
static void* ghostx_pty_userdata = NULL;

static void write_pty_effect(GhosttyTerminal terminal, void* userdata, const uint8_t* data, size_t len) {
    (void)terminal;
    if (ghostx_pty_write_cb) ghostx_pty_write_cb(ghostx_pty_userdata, data, len);
}

void ghostx_terminal_set_write_pty_callback(void* terminal, void* userdata,
    void (*callback)(void*, const uint8_t*, size_t)) {
    ghostx_pty_write_cb = callback;
    ghostx_pty_userdata = userdata;
    ghostty_terminal_set((GhosttyTerminal)terminal, GHOSTTY_TERMINAL_OPT_USERDATA, userdata);
    ghostty_terminal_set((GhosttyTerminal)terminal, GHOSTTY_TERMINAL_OPT_WRITE_PTY, write_pty_effect);
}

// --- Title changed callback ---

static void (*ghostx_title_cb)(void*, const char*, size_t) = NULL;

static void title_changed_effect(GhosttyTerminal terminal, void* userdata) {
    (void)terminal;
    GhosttyString title = {0};
    if (ghostty_terminal_get((GhosttyTerminal)terminal, GHOSTTY_TERMINAL_DATA_TITLE, &title) == GHOSTTY_SUCCESS
        && title.ptr && ghostx_title_cb) {
        ghostx_title_cb(userdata, (const char*)title.ptr, title.len);
    }
}

void ghostx_terminal_set_title_callback(void* terminal,
    void (*callback)(void*, const char*, size_t)) {
    ghostx_title_cb = callback;
    ghostty_terminal_set((GhosttyTerminal)terminal, GHOSTTY_TERMINAL_OPT_TITLE_CHANGED, title_changed_effect);
}

// --- Render state ---

void* ghostx_render_state_new(void) {
    GhosttyRenderState state = NULL;
    GhosttyResult err = ghostty_render_state_new(NULL, &state);
    if (err != GHOSTTY_SUCCESS) return NULL;
    return (void*)state;
}

void ghostx_render_state_free(void* state) {
    if (state) ghostty_render_state_free((GhosttyRenderState)state);
}

void ghostx_render_state_update(void* state, void* terminal) {
    ghostty_render_state_update((GhosttyRenderState)state, (GhosttyTerminal)terminal);
}

// --- Row iterator ---

void* ghostx_row_iterator_new(void) {
    GhosttyRenderStateRowIterator iter = NULL;
    ghostty_render_state_row_iterator_new(NULL, &iter);
    return (void*)iter;
}

void ghostx_row_iterator_free(void* iter) {
    if (iter) ghostty_render_state_row_iterator_free((GhosttyRenderStateRowIterator)iter);
}

void* ghostx_row_cells_new(void) {
    GhosttyRenderStateRowCells cells = NULL;
    ghostty_render_state_row_cells_new(NULL, &cells);
    return (void*)cells;
}

void ghostx_row_cells_free(void* cells) {
    if (cells) ghostty_render_state_row_cells_free((GhosttyRenderStateRowCells)cells);
}

bool ghostx_render_state_get_rows(void* state, void* row_iter, void* row_cells,
    void (*row_callback)(void* ctx, uint32_t row, void* cells), void* ctx) {
    if (ghostty_render_state_get((GhosttyRenderState)state,
            GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, row_iter) != GHOSTTY_SUCCESS)
        return false;

    uint32_t row_num = 0;
    while (ghostty_render_state_row_iterator_next((GhosttyRenderStateRowIterator)row_iter)) {
        if (ghostty_render_state_row_get((GhosttyRenderStateRowIterator)row_iter,
                GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, row_cells) == GHOSTTY_SUCCESS) {
            row_callback(ctx, row_num, row_cells);
        }
        row_num++;
    }
    return true;
}

// --- Cell data reading ---

bool ghostx_cells_next(void* cells) {
    return ghostty_render_state_row_cells_next((GhosttyRenderStateRowCells)cells);
}

uint32_t ghostx_cell_grapheme_len(void* cells) {
    uint32_t len = 0;
    ghostty_render_state_row_cells_get((GhosttyRenderStateRowCells)cells,
        GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &len);
    return len;
}

uint32_t ghostx_cell_graphemes(void* cells, uint32_t* out, uint32_t max_len) {
    uint32_t len = ghostx_cell_grapheme_len(cells);
    if (len > max_len) len = max_len;
    if (len == 0) return 0;
    ghostty_render_state_row_cells_get((GhosttyRenderStateRowCells)cells,
        GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF, out);
    return len;
}

void ghostx_cell_fg_color(void* cells, uint8_t* r, uint8_t* g, uint8_t* b) {
    GhosttyColorRgb rgb = {0};
    ghostty_render_state_row_cells_get((GhosttyRenderStateRowCells)cells,
        GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR, &rgb);
    *r = rgb.r; *g = rgb.g; *b = rgb.b;
}

void ghostx_cell_bg_color(void* cells, uint8_t* r, uint8_t* g, uint8_t* b) {
    GhosttyColorRgb rgb = {0};
    if (ghostty_render_state_row_cells_get((GhosttyRenderStateRowCells)cells,
            GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR, &rgb) == GHOSTTY_SUCCESS) {
        *r = rgb.r; *g = rgb.g; *b = rgb.b;
    } else {
        *r = *g = *b = 0;
    }
}

uint32_t ghostx_cell_flags(void* cells) {
    GhosttyStyle style;
    ghostty_render_state_row_cells_get((GhosttyRenderStateRowCells)cells,
        GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style);
    return (style.bold ? 1 : 0) | (style.italic ? 2 : 0) | (style.underline ? 4 : 0);
}

// --- Key encoder ---

void* ghostx_key_encoder_new(void) {
    GhosttyKeyEncoder encoder = NULL;
    ghostty_key_encoder_new(NULL, &encoder);
    return (void*)encoder;
}

void ghostx_key_encoder_free(void* encoder) {
    if (encoder) ghostty_key_encoder_free((GhosttyKeyEncoder)encoder);
}

void ghostx_key_encoder_sync(void* encoder, void* terminal) {
    ghostty_key_encoder_setopt_from_terminal((GhosttyKeyEncoder)encoder, (GhosttyTerminal)terminal);
}
