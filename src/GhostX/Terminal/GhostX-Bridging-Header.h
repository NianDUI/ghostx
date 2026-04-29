#ifndef GHOSTX_BRIDGE_H
#define GHOSTX_BRIDGE_H

#import <ghostty/vt.h>

// This bridging header exposes libghostty-vt C API to Swift.
// The libghostty-vt.dylib must be linked to the application target.
//
// Key types used by Swift:
// - GhosttyTerminal:   ghostty_terminal_new / _free
// - GhosttyKeyEncoder:   ghostty_key_encoder_new / _free
// - GhosttyMouseEncoder: ghostty_mouse_encoder_new / _free
// - GhosttyRenderState:  ghostty_render_state_new / _free
//
// For the full (non-vt) libghostty, use ghostty.h instead.

#endif
