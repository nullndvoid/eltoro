const limine = @import("limine");
const std = @import("std");

const assert = std.debug.assert;

/// Used to get the framebuffer using the Limine boot protocol.
pub export var framebuffer_request: limine.FramebufferRequest linksection(".limine_requests") = .{};

/// Bits per pixel.
const BPP = 32;

/// An alias for u24. Colours in RGB format are just 3 bytes large. Note: at 32 bits per pixel we need to handle this extra space.
pub const RgbColour = u24;

/// Width of the framebuffer in pixels.
width: usize = undefined,
/// Height of the framebuffer in pixels.
height: usize = undefined,
/// A slice of the framebuffers memory.
framebuffer: []volatile RgbColour = undefined,

pub const Framebuffer = @This();

/// Sets up the framebuffer. This function must be called before all others in this module.
pub fn initialise() Framebuffer {
    const framebuffer_response = framebuffer_request.response.?;
    const limine_framebuffer = framebuffer_response.framebuffers()[0];
    // We only support 32bpp at present.
    assert(limine_framebuffer.bpp == 32);

    const width = limine_framebuffer.width;
    const height = limine_framebuffer.height;

    // Create a slice to access framebuffer memory. [*] is a many item pointer.
    const raw_framebuffer: [*]volatile RgbColour = @ptrCast(@alignCast(limine_framebuffer.address));

    return .{
        .framebuffer = raw_framebuffer[0 .. width * height],
        .height = height,
        .width = width,
    };
}

/// Clears the framebuffer, setting the given background colour.
pub fn clear(
    /// A pointer to this framebuffer.
    self: *Framebuffer,
    /// The background colour to set (0xRRGGBB format).
    bg: RgbColour,
) void {
    @memset(self.framebuffer, bg);
}

/// Draws a pixel of `colour` at `(x, y)` on the screen.
inline fn drawPixel(
    /// A pointer to this framebuffer.
    self: *Framebuffer,
    /// Horizontal position in px.
    x: usize,
    /// Vertical position in px.
    y: usize,
    /// The colour to use for the pixel (0xRRGGBB format).
    colour: RgbColour,
) void {
    self.framebuffer[y * self.width + x] = colour;
}

const font = @import("font.zig");

/// Draws a bitmap font glyph at the specified coordinates.
pub fn drawGlyph(
    /// A pointer to this framebuffer.
    self: *Framebuffer,
    /// ASCII codepoint for the glyph.
    c: u8,
    /// Horizontal position in px.
    x: usize,
    /// Vertical position in px.
    y: usize,
    /// The foreground colour to use for the pixel (0xRRGGBB format).
    fg: RgbColour,
    /// The background colour to use for the pixel (0xRRGGBB format).
    bg: RgbColour,
) void {
    const glyph = font.BITMAP[c];

    for (0..font.HEIGHT) |dy| {
        for (0..font.WIDTH) |dx| {
            const mask: u8 = @as(u8, 1) << @intCast(font.WIDTH - dx - 1);
            const colour = if (glyph[dy] & mask != 0) fg else bg;

            drawPixel(self, x + dx, y + dy, colour);
        }
    }
}
