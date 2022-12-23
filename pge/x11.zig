const std = @import("std");
const assert = std.debug.assert;

// Any X function that returns 0 means there is an error.
// Free/destroy/etc functions here, instead of returning an error, will panic instead

pub const c = @cImport({
    @cInclude("X.h");
    @cInclude("Xlib.h");
    @cInclude("keysymdef.h");
    @cInclude("gl.h");
    @cInclude("glx.h");
});

const g = @import("gl.zig");

pub const XError = error{
    XBadRequest,
    XBadValue,
    XBadWindow,
    XBadPixmap,
    XBadAtom,
    XBadCursor,
    XBadFont,
    XBadMatch,
    XBadDrawable,
    XBadAccess,
    XBadAlloc,
    XBadColor,
    XBadGC,
    XBadIDChoice,
    XBadName,
    XBadLength,
    XBadImplementation,
};
pub const GlxError = error{
    GlxBadContext,
    GlxBadContextState,
    GlxBadDrawable,
    GlxBadPixmap,
    GlxBadContextTag,
    GlxBadCurrentWindow,
    GlxBadRenderRequest,
    GlxBadLargeRequest,
    GlxUnsupportedPrivateRequest,
    GlxBadFBConfig,
    GlxBadPbuffer,
    GlxBadCurrentDrawable,
    GlxBadWindow,
};

fn getErrorFromCode(error_code: u8) ?(XError || GlxError) {
    const code = if (error_code > 0) error_code - 1 else return null;
    const errors = [_]XError{
        error.XBadRequest,
        error.XBadValue,
        error.XBadWindow,
        error.XBadPixmap,
        error.XBadAtom,
        error.XBadCursor,
        error.XBadFont,
        error.XBadMatch,
        error.XBadDrawable,
        error.XBadAccess,
        error.XBadAlloc,
        error.XBadColor,
        error.XBadGC,
        error.XBadIDChoice,
        error.XBadName,
        error.XBadLength,
        error.XBadImplementation,
    };
    if (code < errors.len) {
        return errors[code];
    }
    if (glx_base_error) |base_error| {
        if (code >= base_error) {
            const glx_errors = [_]GlxError{
                error.GlxBadContext,
                error.GlxBadContextState,
                error.GlxBadDrawable,
                error.GlxBadPixmap,
                error.GlxBadContextTag,
                error.GlxBadCurrentWindow,
                error.GlxBadRenderRequest,
                error.GlxBadLargeRequest,
                error.GlxUnsupportedPrivateRequest,
                error.GlxBadFBConfig,
                error.GlxBadPbuffer,
                error.GlxBadCurrentDrawable,
                error.GlxBadWindow,
            };
            const be = @intCast(usize, base_error);
            if (code < be + glx_errors.len) {
                return glx_errors[code - be];
            }
        }
    }
    return null;
}

/// returns if multithreading allowed
pub fn initThreads() bool {
    return c.XInitThreads() != 0;
}

var x11_error_event: ?*c.XErrorEvent = null;
var x11_error: ?(GlxError || XError) = null;
pub fn getError() ?(GlxError || XError) {
    const e = x11_error;
    x11_error = null;
    return e;
}

fn xErrorHandler(display: ?*c.Display, event: ?*c.XErrorEvent) callconv(.C) c_int {
    _ = display;
    x11_error_event = event orelse return 0;
    x11_error = getErrorFromCode(event.?.error_code) orelse return 0;
    std.log.err("X11 error: {any}", .{x11_error.?});
    return 0;
}

/// mandatory to call this in the beginning for zig-like error handling
/// (otherwise functions should just panic on error)
pub fn initErrorHandler() void {
    _ = c.XSetErrorHandler(xErrorHandler);
}

// please i just want to receive glx errors
var glx_base_error: ?c_int = null;
var glx_base_event: ?c_int = null;

pub fn initGlxErrors(display: Display) bool {
    var ber: c_int = undefined;
    var bev: c_int = undefined;
    const result = c.glXQueryExtension(display.inner, &ber, &bev) == c.True;
    if (result) {
        glx_base_error = ber;
        glx_base_event = bev;
    }
    return result;
}

pub const EventMask = packed struct(c_long) {
    key_press: bool = false,
    key_release: bool = false,
    button_press: bool = false,
    button_release: bool = false,
    enter_window: bool = false,
    leave_window: bool = false,
    pointer_motion: bool = false,
    pointer_motion_hint: bool = false,
    button1_motion: bool = false,
    button2_motion: bool = false,
    button3_motion: bool = false,
    button4_motion: bool = false,
    button5_motion: bool = false,
    button_motion: bool = false,
    keymap_state: bool = false,
    exposure: bool = false,
    visibility_change: bool = false,
    structure_notify: bool = false,
    resize_redirect: bool = false,
    substructure_notify: bool = false,
    substructure_redirect: bool = false,
    focus_change: bool = false,
    property_change: bool = false,
    colormap_change: bool = false,
    owner_grab_butter: bool = false,
    _p: u39 = 0,
};

pub const Display = struct {
    inner: *c.Display,

    pub fn open(name: ?[:0]const u8) ?Display {
        if (c.XOpenDisplay((name orelse "").ptr)) |display| {
            return Display{ .inner = display };
        }
        return null;
    }
    pub fn close(self: Display) void {
        assert(c.XCloseDisplay(self.inner) != 0);
    }
    pub fn setWMProtocols(self: Display, window: Window, protocols: []Atom) !void {
        if (c.XSetWMProtocols(self.inner, window.inner, protocols.ptr, @intCast(c_int, protocols.len)) == 0)
            return getError().?;
    }
    pub fn sendEvent(
        self: Display,
        window: Window,
        propagate: bool,
        event_mask: EventMask,
        event: *c.XEvent,
    ) !void {
        if (c.XSendEvent(
            self.inner,
            window.inner,
            @boolToInt(propagate),
            @bitCast(c_long, event_mask),
            event,
        ) == 0) {
            return getError().?;
        }
    }
    pub fn flush(self: Display) !void {
        if (c.XFlush(self.inner) == 0) return getError().?;
    }
    pub fn makeCurrent(self: Display, window: Window, context: Context) !void {
        if (c.glXMakeCurrent(self.inner, window.inner, context.inner) == 0) {
            return getError().?;
        }
    }
    // assume that XPending will not return a negative value
    pub fn pending(display: Display) u32 {
        return @intCast(u32, c.XPending(display.inner));
    }

    /// this will block if no available events
    pub fn nextEvent(display: Display) c.XEvent {
        var event: c.XEvent = undefined;
        _ = c.XNextEvent(display.inner, &event);
        return event;
    }

    pub fn nextEventOpt(display: Display) ?c.XEvent {
        return if (display.pending() > 0) display.nextEvent() else null;
    }

    pub fn swapBuffers(display: Display, window: Window) !void {
        c.glXSwapBuffers(display.inner, window.inner);
        if (getError()) |e| return e;
    }

    pub fn storeName(display: Display, window: Window, s: [:0]const u8) !void {
        if (c.XStoreName(display.inner, window.inner, s.ptr) == 0)
            return getError().?;
    }

    pub fn defaultRootWindow(self: Display) Window {
        return Window{ .inner = c.DefaultRootWindow(self.inner) };
    }
};
pub const Pixmap = c.Pixmap;
pub const Cursor = c.Cursor;

pub const Window = struct {
    inner: c.Window,

    pub const None = Window{ .inner = 0 };

    pub const BitGravity = enum(c_int) {
        Forget = c.ForgetGravity,
        NorthWest = c.NorthWestGravity,
        North = c.NorthGravity,
        NorthEast = c.NorthEastGravity,
        West = c.WestGravity,
        Center = c.CenterGravity,
        East = c.EastGravity,
        SouthWest = c.SouthWestGravity,
        South = c.SouthGravity,
        SouthEast = c.SouthEastGravity,
        Static = c.StaticGravity,
    };
    pub const WinGravity = enum(c_int) {
        Unmap = c.UnmapGravity,
        NorthWest = c.NorthWestGravity,
        North = c.NorthGravity,
        NorthEast = c.NorthEastGravity,
        West = c.WestGravity,
        Center = c.CenterGravity,
        East = c.EastGravity,
        SouthWest = c.SouthWestGravity,
        South = c.SouthGravity,
        SouthEast = c.SouthEastGravity,
        Static = c.StaticGravity,
    };
    pub const WindowAttributes = extern struct {
        bg_pixmap: Pixmap = c.None,
        bg_pixel: c_ulong = undefined,
        border_pixmap: Pixmap = c.CopyFromParent,
        border_pixel: c_ulong = undefined,
        bit_gravity: BitGravity = .Forget,
        win_gravity: WinGravity = .NorthWest,
        backing_store: enum(c_int) {
            NotUseful = c.NotUseful,
            WhenMapped = c.WhenMapped,
            Always = c.Always,
        } = .NotUseful,
        backing_planes: c_ulong = ~@as(c_ulong, 0),
        backing_pixel: c_ulong = 0,
        save_under: c.Bool = c.False,
        event_mask: EventMask = .{},
        do_not_propagate_mask: EventMask = .{},
        override_redirect: c.Bool = c.False,
        colormap: c.Colormap = c.CopyFromParent,
        cursor: Cursor = c.None,
    };
    pub const WindowAttributeSet = packed struct(c_ulong) {
        bg_pixmap: bool = false,
        bg_pixel: bool = false,
        border_pixmap: bool = false,
        border_pixel: bool = false,
        bit_gravity: bool = false,
        win_gravity: bool = false,
        backing_store: bool = false,
        backing_planes: bool = false,
        backing_pixel: bool = false,
        override_redirect: bool = false,
        save_under: bool = false,
        event_mask: bool = false,
        do_not_propagate_mask: bool = false,
        colormap: bool = false,
        cursor: bool = false,
        _p: u49 = 0,
    };

    pub fn create(
        display: Display,
        parent: Window,
        x: i32,
        y: i32,
        width: u32,
        height: u32,
        border_width: u32,
        depth: i32,
        class: enum(c_uint) {
            CopyFromParent = c.CopyFromParent,
            InputOutput = c.InputOutput,
            InputOnly = c.InputOnly,
        },
        visual: Visual,
        value_mask: WindowAttributeSet,
        attributes: WindowAttributes,
    ) !Window {
        var _attributes = @bitCast(c.XSetWindowAttributes, attributes);
        const window = c.XCreateWindow(
            display.inner,
            parent.inner,
            x,
            y,
            width,
            height,
            border_width,
            depth,
            @enumToInt(class),
            visual.inner,
            @bitCast(c_ulong, value_mask),
            &_attributes,
        );
        if (getError()) |e| return e;
        return Window{ .inner = window };
    }
    pub fn unmap(self: Window, display: Display) void {
        assert(c.XUnmapWindow(display.inner, self.inner) != 0);
    }
    pub fn map(self: Window, display: Display) !void {
        if (c.XMapWindow(display.inner, self.inner) == 0) return getError().?;
    }
    pub fn storeName(self: Window, display: Display, name: [:0]const u8) !void {
        if (c.XStoreName(display.inner, self.inner, name.ptr) == 0) return getError().?;
    }
    pub fn destroy(self: Window, display: Display) void {
        assert(c.XDestroyWindow(display.inner, self.inner) != 0);
    }
    pub fn getAttributes(self: Window, display: Display) !c.XWindowAttributes {
        var attr: c.XWindowAttributes = undefined;
        if (c.XGetWindowAttributes(display.inner, self.inner, &attr) == 0) return getError().?;
        return attr;
    }
};

pub const Colormap = struct {
    inner: c.Colormap,

    pub fn create(display: Display, window: Window, visual: Visual, alloc: enum(c_int) {
        none = c.AllocNone,
        all = c.AllocAll,
    }) !Colormap {
        const colormap = c.XCreateColormap(display.inner, window.inner, visual.inner, @enumToInt(alloc));
        if (getError()) |e| return e;
        return Colormap{ .inner = colormap };
    }

    pub fn free(self: Colormap, display: Display) void {
        assert(c.XFreeColormap(display.inner, self.inner) != 0);
    }
};

pub const Attributes = struct {
    use_gl: bool = false, // shouldnt matter what value this is
    buffer_size: ?u31 = null,
    level: ?i32 = null,
    rgba: bool = false,
    doublebuffer: bool = false,
    stereo: bool = false,
    aux_buffers: ?u31 = null,
    red_size: ?u31 = null,
    green_size: ?u31 = null,
    blue_size: ?u31 = null,
    alpha_size: ?u31 = null,
    depth_size: ?u31 = null,
    stencil_size: ?u31 = null,
    accum_red_size: ?u31 = null,
    accum_green_size: ?u31 = null,
    accum_blue_size: ?u31 = null,
    accum_alpha_size: ?u31 = null,
    transparent_type: ?Transparency = null,
    transparent_red_value: ?i32 = null,
    transparent_blue_value: ?i32 = null,
    transparent_green_value: ?i32 = null,
    transparent_alpha_value: ?i32 = null,
    transparent_index_value: ?i32 = null,
    visual_type: ?VisualType = null,
    visual_caveat: ?VisualCaveat = null,

    pub const Transparency = enum(i32) {
        None = c.GLX_NONE_EXT,
        TransparentIndex = c.GLX_TRANSPARENT_INDEX_EXT,
        TransparentRgb = c.GLX_TRANSPARENT_RGB_EXT,
    };
    pub const VisualType = enum(i32) {
        TrueColor = c.GLX_TRUE_COLOR_EXT,
        DirectColor = c.GLX_DIRECT_COLOR_EXT,
        PseudoColor = c.GLX_PSEUDO_COLOR_EXT,
        StaticColor = c.GLX_STATIC_COLOR_EXT,
        Grayscale = c.GLX_GRAY_SCALE_EXT,
        StaticGray = c.GLX_STATIC_GRAY_EXT,
    };
    pub const VisualCaveat = enum(i32) {
        None = c.GLX_NONE_EXT,
        SlowVisual = c.GLX_SLOW_VISUAL_EXT,
    };

    pub const VisualAttribute = enum(i32) {
        use_gl = c.GLX_USE_GL,
        buffer_size = c.GLX_BUFFER_SIZE,
        level = c.GLX_LEVEL,
        rgba = c.GLX_RGBA,
        doublebuffer = c.GLX_DOUBLEBUFFER,
        stereo = c.GLX_STEREO,
        aux_buffers = c.GLX_AUX_BUFFERS,
        red_size = c.GLX_RED_SIZE,
        green_size = c.GLX_GREEN_SIZE,
        blue_size = c.GLX_BLUE_SIZE,
        alpha_size = c.GLX_ALPHA_SIZE,
        depth_size = c.GLX_DEPTH_SIZE,
        stencil_size = c.GLX_STENCIL_SIZE,
        accum_red_size = c.GLX_ACCUM_RED_SIZE,
        accum_green_size = c.GLX_ACCUM_GREEN_SIZE,
        accum_blue_size = c.GLX_ACCUM_BLUE_SIZE,
        accum_alpha_size = c.GLX_ACCUM_ALPHA_SIZE,
        transparent_type = c.GLX_TRANSPARENT_TYPE_EXT,
        transparent_red_value = c.GLX_TRANSPARENT_RED_VALUE_EXT,
        transparent_blue_value = c.GLX_TRANSPARENT_BLUE_VALUE_EXT,
        transparent_green_value = c.GLX_TRANSPARENT_GREEN_VALUE_EXT,
        transparent_alpha_value = c.GLX_TRANSPARENT_ALPHA_VALUE_EXT,
        transparent_index_value = c.GLX_TRANSPARENT_INDEX_VALUE_EXT,
        visual_type = c.GLX_X_VISUAL_TYPE_EXT,
        visual_caveat = c.GLX_VISUAL_CAVEAT_EXT,
    };

    const fields = @typeInfo(Attributes).Struct.fields;

    /// number of i32s necessary to hold
    pub fn size(self: Attributes) usize {
        var count: usize = 0;
        inline for (fields) |field| {
            const val = @field(self, field.name);
            switch (field.type) {
                bool => count += @boolToInt(val),
                else => count += if (val != null) 2 else 0,
            }
        }
        return count;
    }
    pub fn write(self: Attributes, buffer: []i32) !void {
        var i: usize = 0;
        inline for (fields) |field| {
            const val = @field(self, field.name);
            const present = switch (field.type) {
                bool => val,
                else => val != null,
            };
            if (present) {
                if (i >= buffer.len) return error.Overflow;
                buffer[i] = @enumToInt(@field(VisualAttribute, field.name));
                i += 1;
                switch (field.type) {
                    bool => {},
                    ?i32 => {
                        if (i >= buffer.len) return error.Overflow;
                        buffer[i] = val.?;
                        i += 1;
                    },
                    ?u31 => {
                        if (i >= buffer.len) return error.Overflow;
                        buffer[i] = @intCast(i32, val.?);
                        i += 1;
                    },
                    else => {
                        if (i >= buffer.len) return error.Overflow;
                        buffer[i] = @enumToInt(val.?);
                        i += 1;
                    },
                }
            }
        }
        if (i >= buffer.len) return error.Overflow;
        buffer[i] = c.None;
    }
};

/// this function should not fail
pub fn chooseVisual(display: Display, screen: c_int, attributes: Attributes) VisualInfo {
    var buf: [47]i32 = undefined;
    attributes.write(&buf) catch unreachable;
    // this is only supposed to return null if there is something wrong with
    // the `gl_attributes` list
    return VisualInfo{ .inner = c.glXChooseVisual(display.inner, screen, &buf).? };
}
pub const VisualInfo = struct {
    inner: *c.XVisualInfo,

    pub fn visual(self: VisualInfo) Visual {
        return Visual{ .inner = self.inner.visual };
    }
    pub fn depth(self: VisualInfo) c_int {
        return self.inner.depth;
    }

    pub fn deinit(self: *VisualInfo) void {
        assert(c.XFree(self.inner) != 0);
        self.* = undefined;
    }
};

pub const Visual = struct {
    inner: *c.Visual,
};

pub const Atom = c.Atom;

pub fn internAtom(display: Display, name: [:0]const u8, only_if_exists: bool) !Atom {
    const atom = c.XInternAtom(display.inner, name.ptr, @boolToInt(only_if_exists));
    if (getError()) |e| return e;
    return atom;
}

pub const Context = struct {
    inner: c.GLXContext,

    pub const None = Context{ .inner = null };

    pub fn create(display: Display, visual_info: VisualInfo, share_list: Context, direct: bool) !Context {
        const ctx = c.glXCreateContext(display.inner, visual_info.inner, share_list.inner, @boolToInt(direct));
        if (getError()) |e| return e;
        return Context{ .inner = ctx };
    }
    pub fn destroy(self: Context, display: Display) void {
        c.glXDestroyContext(display.inner, self.inner);
        assert(getError() == null); // will error if `self` is bad
    }
};
