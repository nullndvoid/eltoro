//! Abstractions over the framebuffer.
const std = @import("std");

/// Abstractions over the framebuffer to create a more terminal-like interface.
pub const Terminal = @This();

const frame_buffer = @import("framebuffer.zig");
const font = @import("font.zig");

const Framebuffer = frame_buffer.Framebuffer;
const RgbColour = frame_buffer.RgbColour;

/// The cursor position from char 0 to char w*h - 1.
cursor: usize = 0,
/// The underlying framebuffer to draw to.
framebuffer: Framebuffer = undefined,
/// The screen width in characters.
screen_width: usize,
/// The screen height in characters.
screen_height: usize,

/// This terminal; populated when initialise is called.
var terminal: Terminal = undefined;

var current_fg: RgbColour = 0xFFFFFF;
var current_bg: RgbColour = 0x000000;

/// Creates a terminal on which to print characters. Must be called before
/// other functions in this struct.
pub fn initialise() void {
    var fb = Framebuffer.initialise();
    fb.clear(current_bg);

    const screen_width = fb.width / font.WIDTH;
    const screen_height = fb.height / font.HEIGHT;

    terminal = Terminal{
        .framebuffer = fb,
        .screen_height = screen_height,
        .screen_width = screen_width,
    };
}

/// Writes on screen according to the specified format string, using the given foreground color.
///
/// Parameters:
///   format: Format string in `std.fmt.format` format.
///   args:   Tuple of arguments containing values for each format specifier.
///   fg:     Color of the text.
pub fn colorPrint(fg: RgbColour, comptime format: []const u8, args: anytype) void {
    const saved_fg = current_fg;

    current_fg = fg;
    print(format, args);

    current_fg = saved_fg;
}

pub fn clear(bg: RgbColour) void {
    terminal.cursor = 0;
    terminal.framebuffer.clear(bg);
}

/// Writes on screen according to the specified format string.
///
/// Parameters:
///   format: Format string in `std.fmt.format` format.
///   args:   Tuple of arguments containing values for each format specifier.
pub fn print(comptime format: []const u8, args: anytype) void {
    std.fmt.format(@as(TerminalWriter, undefined), format, args) catch unreachable;
}

fn writeString(self: *Terminal, bytes: []const u8) void {
    for (bytes) |byte| {
        writeChar(self, byte);
    }
}

/// The tab width in spaces.
pub const TAB_WIDTH = 4;

fn writeChar(self: *Terminal, c: u8) void {
    // TODO: Implement scrolling!
    if (self.cursor >= (self.screen_width * self.screen_height - 1)) {}

    switch (c) {
        '\n' => while (true) {
            writeChar(self, ' ');
            if (self.cursor % self.screen_width == 0) {
                break;
            }
        },

        '\t' => while (true) {
            writeChar(self, ' ');
            if (self.cursor % TAB_WIDTH == 0) {
                break;
            }
        },

        else => {
            const x: usize = (self.cursor % self.screen_width) * font.WIDTH;
            const y: usize = (self.cursor / self.screen_width) * font.HEIGHT;

            self.framebuffer.drawGlyph(c, x, y, current_fg, current_bg);
            self.cursor += 1;
        },
    }
}

/// Implements the Zig writer interface for this terminal.
const TerminalWriter = struct {
    const Self = @This();
    pub const Error = error{};

    pub fn write(_: Self, bytes: []const u8) !usize {
        writeString(&terminal, bytes);
        return bytes.len;
    }

    pub fn writeByte(self: Self, byte: u8) !void {
        _ = try self.write(&.{byte});
    }

    pub fn writeBytesNTimes(self: Self, bytes: []const u8, n: usize) !void {
        for (0..n) |_| {
            _ = try self.write(bytes);
        }
    }

    pub fn writeAll(self: Self, bytes: []const u8) !void {
        _ = try self.write(bytes);
    }
};
