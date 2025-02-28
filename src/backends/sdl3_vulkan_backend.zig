const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

pub const sdl_backend = @import("sdl_backend.zig");
pub const vulkan = @import("vulkan");
pub const c = sdl_backend.c;
const sdl3 = true;

const SDL3VkBackend = @This();
pub const Context = *SDL3VkBackend;

window: *c.SDL_Window,
touch_mouse_events: bool = false,
log_events: bool = false,
initial_scale: f32 = 1.0,
cursor_last: dvui.enums.Cursor = .arrow,
cursor_backing: [@typeInfo(dvui.enums.Cursor).Enum.fields.len]?*c.SDL_Cursor = [_]?*c.SDL_Cursor{null} ** @typeInfo(dvui.enums.Cursor).Enum.fields.len,
cursor_backing_tried: [@typeInfo(dvui.enums.Cursor).Enum.fields.len]bool = [_]bool{false} ** @typeInfo(dvui.enums.Cursor).Enum.fields.len,
arena: std.mem.Allocator = undefined,

pub const VkRenderer = struct {};

pub fn init(window: *c.SDL_Window) !SDL3VkBackend {
    return SDL3VkBackend{ .window = window, .initial_scale = c.SDL_GetDisplayContentScale(c.SDL_GetDisplayForWindow(window)) };
}

pub fn waitEventTimeout(_: *SDL3VkBackend, timeout_micros: u32) void {
    if (timeout_micros == std.math.maxInt(u32)) {
        // wait no timeout
        _ = c.SDL_WaitEvent(null);
    } else if (timeout_micros > 0) {
        // wait with a timeout
        const timeout = @min((timeout_micros + 999) / 1000, std.math.maxInt(c_int));
        _ = c.SDL_WaitEventTimeout(null, @as(c_int, @intCast(timeout)));

        // TODO: this call to SDL_PollEvent can be removed after resolution of
        // https://github.com/libsdl-org/SDL/issues/6539
        // maintaining this a little longer for people with older SDL versions
        _ = c.SDL_PollEvent(null);
    } else {
        // don't wait
    }
}

pub fn refresh(self: *SDL3VkBackend) void {
    _ = self;
    var ue = std.mem.zeroes(c.SDL_Event);
    ue.type = if (sdl3) c.SDL_EVENT_USER else c.SDL_USEREVENT;
    _ = c.SDL_PushEvent(&ue);
}

pub fn addAllEvents(self: *SDL3VkBackend, win: *dvui.Window) !bool {
    //const flags = c.SDL_GetWindowFlags(self.window);
    //if (flags & c.SDL_WINDOW_MOUSE_FOCUS == 0 and flags & c.SDL_WINDOW_INPUT_FOCUS == 0) {
    //std.debug.print("bailing\n", .{});
    //}
    var event: c.SDL_Event = undefined;
    const poll_got_event = if (sdl3) true else 1;
    while (c.SDL_PollEvent(&event) == poll_got_event) {
        _ = try self.addEvent(win, event);
        switch (event.type) {
            if (sdl3) c.SDL_EVENT_QUIT else c.SDL_QUIT => {
                return true;
            },
            // TODO: revisit with sdl3
            //c.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED => {
            //std.debug.print("sdl window scale changed event\n", .{});
            //},
            //c.SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED => {
            //std.debug.print("sdl display scale changed event\n", .{});
            //},
            else => {},
        }
    }

    return false;
}

pub fn setCursor(self: *SDL3VkBackend, cursor: dvui.enums.Cursor) void {
    if (cursor != self.cursor_last) {
        self.cursor_last = cursor;

        const enum_int = @intFromEnum(cursor);
        const tried = self.cursor_backing_tried[enum_int];
        if (!tried) {
            self.cursor_backing_tried[enum_int] = true;
            self.cursor_backing[enum_int] = switch (cursor) {
                .arrow => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_DEFAULT else c.SDL_SYSTEM_CURSOR_ARROW),
                .ibeam => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_TEXT else c.SDL_SYSTEM_CURSOR_IBEAM),
                .wait => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_WAIT),
                .wait_arrow => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_PROGRESS else c.SDL_SYSTEM_CURSOR_WAITARROW),
                .crosshair => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_CROSSHAIR),
                .arrow_nw_se => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_NWSE_RESIZE else c.SDL_SYSTEM_CURSOR_SIZENWSE),
                .arrow_ne_sw => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_NESW_RESIZE else c.SDL_SYSTEM_CURSOR_SIZENESW),
                .arrow_w_e => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_EW_RESIZE else c.SDL_SYSTEM_CURSOR_SIZEWE),
                .arrow_n_s => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_NS_RESIZE else c.SDL_SYSTEM_CURSOR_SIZENS),
                .arrow_all => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_MOVE else c.SDL_SYSTEM_CURSOR_SIZEALL),
                .bad => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_NOT_ALLOWED else c.SDL_SYSTEM_CURSOR_NO),
                .hand => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_POINTER else c.SDL_SYSTEM_CURSOR_HAND),
            };
        }

        if (self.cursor_backing[enum_int]) |cur| {
            if (sdl3) {
                _ = c.SDL_SetCursor(cur);
            } else {
                c.SDL_SetCursor(cur);
            }
        } else {
            dvui.log.err("SDL_CreateSystemCursor \"{s}\" failed", .{@tagName(cursor)});
        }
    }
}

pub fn textInputRect(self: *SDL3VkBackend, rect: ?dvui.Rect) void {
    if (rect) |r| {
        if (sdl3) {
            const cursor = 0; // TODO: review what it does
            _ = c.SDL_SetTextInputArea(self.window, &c.SDL_Rect{ .x = @intFromFloat(r.x), .y = @intFromFloat(r.y), .w = @intFromFloat(r.w), .h = @intFromFloat(r.h) }, cursor);
        } else c.SDL_SetTextInputRect(&c.SDL_Rect{ .x = @intFromFloat(r.x), .y = @intFromFloat(r.y), .w = @intFromFloat(r.w), .h = @intFromFloat(r.h) });
        _ = if (sdl3) c.SDL_StartTextInput(self.window) else c.SDL_StartTextInput();
    } else {
        _ = if (sdl3) c.SDL_StopTextInput(self.window) else c.SDL_StopTextInput();
    }
}

pub fn deinit(self: *SDL3VkBackend) void {
    for (self.cursor_backing) |cursor| {
        if (cursor) |cur| {
            if (sdl3) {
                c.SDL_DestroyCursor(cur);
            } else {
                c.SDL_FreeCursor(cur);
            }
        }
    }
    // if (self.we_own_window) {
    //     c.SDL_DestroyRenderer(self.renderer);
    //     c.SDL_DestroyWindow(self.window);
    //     c.SDL_Quit();
    // }
}

pub fn hasEvent(_: *SDL3VkBackend) bool {
    return c.SDL_PollEvent(null) == if (sdl3) true else 1;
}

pub fn backend(self: *SDL3VkBackend) dvui.Backend {
    return dvui.Backend.init(self, @This());
}

pub fn nanoTime(self: *SDL3VkBackend) i128 {
    _ = self;
    return std.time.nanoTimestamp();
}

pub fn sleep(self: *SDL3VkBackend, ns: u64) void {
    _ = self;
    std.time.sleep(ns);
}

pub fn clipboardText(self: *SDL3VkBackend) ![]const u8 {
    const p = c.SDL_GetClipboardText();
    defer c.SDL_free(p);
    return try self.arena.dupe(u8, std.mem.sliceTo(p, 0));
}

pub fn clipboardTextSet(self: *SDL3VkBackend, text: []const u8) !void {
    if (text.len == 0) return;

    var cstr = try self.arena.alloc(u8, text.len + 1);
    @memcpy(cstr[0..text.len], text);
    cstr[cstr.len - 1] = 0;
    _ = c.SDL_SetClipboardText(cstr.ptr);
}

pub fn openURL(self: *SDL3VkBackend, url: []const u8) !void {
    var cstr = try self.arena.alloc(u8, url.len + 1);
    @memcpy(cstr[0..url.len], url);
    cstr[cstr.len - 1] = 0;
    _ = c.SDL_OpenURL(cstr.ptr);
}

pub fn begin(self: *SDL3VkBackend, arena: std.mem.Allocator) void {
    self.arena = arena;
    const size = self.pixelSize();
    setClipRect(self.renderer, &c.SDL_Rect{ .x = 0, .y = 0, .w = @intFromFloat(size.w), .h = @intFromFloat(size.h) });
}

pub fn end(_: *SDL3VkBackend) void {}

pub fn pixelSize(self: *SDL3VkBackend) dvui.Size {
    var w: i32 = undefined;
    var h: i32 = undefined;
    if (sdl3) {
        _ = c.SDL_GetCurrentRenderOutputSize(self.renderer, &w, &h);
    } else {
        _ = c.SDL_GetRendererOutputSize(self.renderer, &w, &h);
    }
    return dvui.Size{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) };
}

pub fn windowSize(self: *SDL3VkBackend) dvui.Size {
    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = c.SDL_GetWindowSize(self.window, &w, &h);
    return dvui.Size{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) };
}

pub fn contentScale(self: *SDL3VkBackend) f32 {
    return self.initial_scale;
}

pub fn drawClippedTriangles(self: *SDL3VkBackend, texture: ?*anyopaque, vtx: []const dvui.Vertex, idx: []const u16, maybe_clipr: ?dvui.Rect) void {
    //std.debug.print("drawClippedTriangles:\n", .{});
    //for (vtx) |v, i| {
    //  std.debug.print("  {d} vertex {}\n", .{i, v});
    //}
    //for (idx) |id, i| {
    //  std.debug.print("  {d} index {d}\n", .{i, id});
    //}

    var oldclip: c.SDL_Rect = undefined;

    if (maybe_clipr) |clipr| {
        if (sdl3) {
            _ = c.SDL_GetRenderClipRect(self.renderer, &oldclip);
        } else {
            _ = c.SDL_RenderGetClipRect(self.renderer, &oldclip);
        }

        // figure out how much we are losing by truncating x and y, need to add that back to w and h
        const clip = c.SDL_Rect{ .x = @as(c_int, @intFromFloat(clipr.x)), .y = @as(c_int, @intFromFloat(clipr.y)), .w = @max(0, @as(c_int, @intFromFloat(@ceil(clipr.w + clipr.x - @floor(clipr.x))))), .h = @max(0, @as(c_int, @intFromFloat(@ceil(clipr.h + clipr.y - @floor(clipr.y))))) };
        //std.debug.print("sdl clip {}\n", .{clipr});

        //std.debug.print("SDL clip {} -> SDL_Rect{{ .x = {d}, .y = {d}, .w = {d}, .h = {d} }}\n", .{ clipr, clip.x, clip.y, clip.w, clip.h });
        setClipRect(self.renderer, &clip);
    }

    const tex = @as(?*c.SDL_Texture, @ptrCast(@alignCast(texture)));

    if (sdl3) {
        // not great, but seems sdl3 strictly accepts color only in floats
        // TODO: review if better solution is possible
        const vcols = self.arena.alloc(c.SDL_FColor, vtx.len) catch return;
        defer self.arena.free(vcols);
        for (vcols, 0..) |*col, i| {
            col.r = @as(f32, @floatFromInt(vtx[i].col.r)) / 255.0;
            col.g = @as(f32, @floatFromInt(vtx[i].col.g)) / 255.0;
            col.b = @as(f32, @floatFromInt(vtx[i].col.b)) / 255.0;
            col.a = @as(f32, @floatFromInt(vtx[i].col.a)) / 255.0;
        }

        _ = c.SDL_RenderGeometryRaw(
            self.renderer,
            tex,
            @as(*const f32, @ptrCast(&vtx[0].pos)),
            @sizeOf(dvui.Vertex),
            vcols.ptr,
            @sizeOf(c.SDL_FColor),
            @as(*const f32, @ptrCast(&vtx[0].uv)),
            @sizeOf(dvui.Vertex),
            @as(c_int, @intCast(vtx.len)),
            idx.ptr,
            @as(c_int, @intCast(idx.len)),
            @sizeOf(u16),
        );
    }

    if (maybe_clipr) |_| {
        setClipRect(self.renderer, &oldclip);
    }
}

pub fn textureCreate(self: *SDL3VkBackend, pixels: [*]u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) *anyopaque {
    _ = interpolation; // autofix
    var surface: *c.SDL_Surface = undefined;
    if (sdl3) {
        surface = c.SDL_CreateSurfaceFrom(@as(c_int, @intCast(width)), @as(c_int, @intCast(height)), c.SDL_PIXELFORMAT_ABGR8888, pixels, @as(c_int, @intCast(4 * width)));
    } else {
        surface = c.SDL_CreateRGBSurfaceWithFormatFrom(pixels, @as(c_int, @intCast(width)), @as(c_int, @intCast(height)), 32, @as(c_int, @intCast(4 * width)), c.SDL_PIXELFORMAT_ABGR8888);
    }
    defer {
        if (sdl3) {
            c.SDL_DestroySurface(surface);
        } else {
            c.SDL_FreeSurface(surface);
        }
    }

    const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse unreachable;
    const pma_blend = c.SDL_ComposeCustomBlendMode(c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD, c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD);
    _ = c.SDL_SetTextureBlendMode(texture, pma_blend);
    return texture;
}

pub fn textureCreateTarget(self: *SDL3VkBackend, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !*anyopaque {
    if (!sdl3) switch (interpolation) {
        .nearest => _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "nearest"),
        .linear => _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear"),
    };

    const texture = c.SDL_CreateTexture(self.renderer, c.SDL_PIXELFORMAT_ABGR8888, c.SDL_TEXTUREACCESS_TARGET, @intCast(width), @intCast(height)) orelse unreachable;
    const pma_blend = c.SDL_ComposeCustomBlendMode(c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD, c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD);
    _ = c.SDL_SetTextureBlendMode(texture, pma_blend);
    //_ = c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND);

    // make sure texture starts out transparent
    const old = c.SDL_GetRenderTarget(self.renderer);
    defer _ = c.SDL_SetRenderTarget(self.renderer, old);

    var oldBlend: [1]c_uint = undefined;
    _ = c.SDL_GetRenderDrawBlendMode(self.renderer, &oldBlend);
    defer _ = c.SDL_SetRenderDrawBlendMode(self.renderer, oldBlend[0]);

    _ = c.SDL_SetRenderTarget(self.renderer, texture);
    _ = c.SDL_SetRenderDrawBlendMode(self.renderer, c.SDL_BLENDMODE_NONE);
    _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 0);
    _ = c.SDL_RenderFillRect(self.renderer, null);

    return texture;
}

pub fn textureRead(self: *SDL3VkBackend, texture: *anyopaque, pixels_out: [*]u8, width: u32, height: u32) error{TextureRead}!void {
    if (SDL3VkBackend.sdl3) {
        const orig_target = c.SDL_GetRenderTarget(self.renderer);
        _ = c.SDL_SetRenderTarget(self.renderer, @ptrCast(@alignCast(texture)));
        defer _ = c.SDL_SetRenderTarget(self.renderer, orig_target);

        var surface: *c.SDL_Surface = c.SDL_RenderReadPixels(self.renderer, null) orelse return error.TextureRead;
        defer c.SDL_DestroySurface(surface);
        if (width * height != surface.*.w * surface.*.h) return error.TextureRead;
        // TODO: most common format is RGBA8888, doing conversion during copy to pixels_out should be faster
        if (surface.*.format != c.SDL_PIXELFORMAT_ABGR8888) {
            const s = surface;
            defer c.SDL_DestroySurface(s);
            surface = c.SDL_ConvertSurface(surface, c.SDL_PIXELFORMAT_ABGR8888) orelse return error.TextureRead;
        }
        @memcpy(pixels_out[0 .. width * height * 4], @as(?[*]u8, @ptrCast(surface.*.pixels)).?[0 .. width * height * 4]);
        return;
    }
    // If SDL picks directX11 as a rendering backend, it could not support
    // SDL_PIXELFORMAT_ABGR8888 so this works around that.  For some reason sdl
    // crashes if we ask it to do the conversion for us.
    var swap_rb = true;
    var info: c.SDL_RendererInfo = undefined;
    _ = c.SDL_GetRendererInfo(self.renderer, &info);
    //std.debug.print("renderer name {s} formats:\n", .{info.name});
    for (0..info.num_texture_formats) |i| {
        //std.debug.print("  {s}\n", .{c.SDL_GetPixelFormatName(info.texture_formats[i])});
        if (info.texture_formats[i] == c.SDL_PIXELFORMAT_ABGR8888) {
            swap_rb = false;
        }
    }

    //var format: u32 = undefined;
    //var access: c_int = undefined;
    //var w: c_int = undefined;
    //var h: c_int = undefined;
    //_ = c.SDL_QueryTexture(@ptrCast(texture), &format, &access, &w, &h);
    //std.debug.print("query texture: {s} {d} {d} {d} width {d}\n", .{c.SDL_GetPixelFormatName(format), access, w, h, width});

    const orig_target = c.SDL_GetRenderTarget(self.renderer);
    _ = c.SDL_SetRenderTarget(self.renderer, @ptrCast(texture));
    defer _ = c.SDL_SetRenderTarget(self.renderer, orig_target);

    _ = c.SDL_RenderReadPixels(self.renderer, null, if (swap_rb) c.SDL_PIXELFORMAT_ARGB8888 else c.SDL_PIXELFORMAT_ABGR8888, pixels_out, @intCast(width * 4));

    if (swap_rb) {
        for (0..width * height) |i| {
            const r = pixels_out[i * 4 + 0];
            const b = pixels_out[i * 4 + 2];
            pixels_out[i * 4 + 0] = b;
            pixels_out[i * 4 + 2] = r;
        }
    }
}

pub fn textureDestroy(_: *SDL3VkBackend, texture: *anyopaque) void {
    c.SDL_DestroyTexture(@as(*c.SDL_Texture, @ptrCast(@alignCast(texture))));
}

pub fn renderTarget(self: *SDL3VkBackend, texture: ?*anyopaque) void {
    _ = c.SDL_SetRenderTarget(self.renderer, @ptrCast(@alignCast(texture)));

    // by default sdl2 sets an empty clip, let's ensure it is the full texture/screen
    if (!sdl3) setClipRect(self.renderer, &c.SDL_Rect{ .x = 0, .y = 0, .w = std.math.maxInt(c_int), .h = std.math.maxInt(c_int) });
}

pub fn setClipRect(renderer: *c.SDL_Renderer, rect: *const c.SDL_Rect) void {
    std.debug.assert(rect.x >= 0);
    std.debug.assert(rect.y >= 0);
    _ = if (sdl3) c.SDL_SetRenderClipRect(renderer, rect) else c.SDL_RenderSetClipRect(renderer, rect);
}

pub fn addEvent(self: *SDL3VkBackend, win: *dvui.Window, event: c.SDL_Event) !bool {
    switch (event.type) {
        if (sdl3) c.SDL_EVENT_KEY_DOWN else c.SDL_KEYDOWN => {
            const sdl_key: i32 = if (sdl3) @intCast(event.key.key) else event.key.keysym.sym;
            const code = SDL_keysym_to_dvui(@intCast(sdl_key));
            const mod = SDL_keymod_to_dvui(if (sdl3) @intCast(event.key.mod) else event.key.keysym.mod);
            if (self.log_events) {
                std.debug.print("sdl event KEYDOWN {} {s} {} {}\n", .{ sdl_key, @tagName(code), mod, event.key.repeat });
            }

            return try win.addEventKey(.{
                .code = code,
                .action = if (if (sdl3) event.key.repeat else event.key.repeat != 0) .repeat else .down,
                .mod = mod,
            });
        },
        if (sdl3) c.SDL_EVENT_KEY_UP else c.SDL_KEYUP => {
            const sdl_key: i32 = if (sdl3) @intCast(event.key.key) else event.key.keysym.sym;
            const code = SDL_keysym_to_dvui(@intCast(sdl_key));
            const mod = SDL_keymod_to_dvui(if (sdl3) @intCast(event.key.mod) else event.key.keysym.mod);
            if (self.log_events) {
                std.debug.print("sdl event KEYUP {} {s} {}\n", .{ sdl_key, @tagName(code), mod });
            }

            return try win.addEventKey(.{
                .code = code,
                .action = .up,
                .mod = mod,
            });
        },
        if (sdl3) c.SDL_EVENT_TEXT_INPUT else c.SDL_TEXTINPUT => {
            const txt = std.mem.sliceTo(if (sdl3) event.text.text else &event.text.text, 0);
            if (self.log_events) {
                std.debug.print("sdl event TEXTINPUT {s}\n", .{txt});
            }

            return try win.addEventText(txt);
        },
        if (sdl3) c.SDL_EVENT_TEXT_EDITING else c.SDL_TEXTEDITING => {
            if (self.log_events) {
                std.debug.print("sdl event TEXTEDITING {s} start {d} len {d}\n", .{ event.edit.text, event.edit.start, event.edit.length });
            }
            return try win.addEventTextEx(event.text.text[0..@intCast(event.edit.length)], true);
        },
        if (sdl3) c.SDL_EVENT_MOUSE_MOTION else c.SDL_MOUSEMOTION => {
            const touch = event.motion.which == c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                std.debug.print("sdl event{s}MOUSEMOTION {d} {d}\n", .{ touch_str, event.motion.x, event.motion.y });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            if (sdl3) {
                return try win.addEventMouseMotion(event.motion.x, event.motion.y);
            } else {
                return try win.addEventMouseMotion(@as(f32, @floatFromInt(event.motion.x)), @as(f32, @floatFromInt(event.motion.y)));
            }
        },
        if (sdl3) c.SDL_EVENT_MOUSE_BUTTON_DOWN else c.SDL_MOUSEBUTTONDOWN => {
            const touch = event.motion.which == c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                std.debug.print("sdl event{s}MOUSEBUTTONDOWN {d}\n", .{ touch_str, event.button.button });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            return try win.addEventMouseButton(SDL_mouse_button_to_dvui(event.button.button), .press);
        },
        if (sdl3) c.SDL_EVENT_MOUSE_BUTTON_UP else c.SDL_MOUSEBUTTONUP => {
            const touch = event.motion.which == c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                std.debug.print("sdl event{s}MOUSEBUTTONUP {d}\n", .{ touch_str, event.button.button });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            return try win.addEventMouseButton(SDL_mouse_button_to_dvui(event.button.button), .release);
        },
        if (sdl3) c.SDL_EVENT_MOUSE_WHEEL else c.SDL_MOUSEWHEEL => {
            if (self.log_events) {
                std.debug.print("sdl event MOUSEWHEEL {d} {d}\n", .{ event.wheel.y, event.wheel.which });
            }

            const ticks = if (sdl3) event.wheel.y else @as(f32, @floatFromInt(event.wheel.y));

            // TODO: some real solution to interpreting the mouse wheel across OSes
            const ticks_adj = switch (builtin.target.os.tag) {
                .linux => ticks * 20,
                .windows => ticks * 20,
                .macos => ticks * 10,
                else => ticks,
            };

            return try win.addEventMouseWheel(ticks_adj);
        },
        if (sdl3) c.SDL_EVENT_FINGER_DOWN else c.SDL_FINGERDOWN => {
            if (self.log_events) {
                std.debug.print("sdl event FINGERDOWN {d} {d} {d}\n", .{ if (sdl3) event.tfinger.fingerID else event.tfinger.fingerId, event.tfinger.x, event.tfinger.y });
            }

            return try win.addEventPointer(.touch0, .press, .{ .x = event.tfinger.x, .y = event.tfinger.y });
        },
        if (sdl3) c.SDL_EVENT_FINGER_UP else c.SDL_FINGERUP => {
            if (self.log_events) {
                std.debug.print("sdl event FINGERUP {d} {d} {d}\n", .{ if (sdl3) event.tfinger.fingerID else event.tfinger.fingerId, event.tfinger.x, event.tfinger.y });
            }

            return try win.addEventPointer(.touch0, .release, .{ .x = event.tfinger.x, .y = event.tfinger.y });
        },
        if (sdl3) c.SDL_EVENT_FINGER_MOTION else c.SDL_FINGERMOTION => {
            if (self.log_events) {
                std.debug.print("sdl event FINGERMOTION {d} {d} {d} {d} {d}\n", .{ if (sdl3) event.tfinger.fingerID else event.tfinger.fingerId, event.tfinger.x, event.tfinger.y, event.tfinger.dx, event.tfinger.dy });
            }

            return try win.addEventTouchMotion(.touch0, event.tfinger.x, event.tfinger.y, event.tfinger.dx, event.tfinger.dy);
        },
        else => {
            if (self.log_events) {
                std.debug.print("unhandled SDL event type {}\n", .{event.type});
            }
            return false;
        },
    }
}

pub const SDL_mouse_button_to_dvui = sdl_backend.SDL_mouse_button_to_dvui;
pub const SDL_keymod_to_dvui = sdl_backend.SDL_keymod_to_dvui;
pub const SDL_keysym_to_dvui = sdl_backend.SDL_keysym_to_dvui;
pub const getSDLVersion = sdl_backend.getSDLVersion;
