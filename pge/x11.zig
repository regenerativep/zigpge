const std = @import("std");
//const assert = std.debug.assert;

// Any X function that returns 0 means there is an error.
// Free/destroy/etc functions here, instead of returning an error, will panic instead

pub const c = @cImport({
    @cInclude("X.h");
    @cInclude("Xlib.h");
    @cInclude("Xproto.h");
    @cInclude("keysymdef.h");
    @cInclude("gl.h");
    @cInclude("glx.h");
});

const g = @import("gl.zig");

/// returns if multithreading allowed
pub fn initThreads() bool {
    return c.XInitThreads() != 0;
}

pub const errors = struct {
    pub const ErrorCode = enum {
        xBadRequest,
        xBadValue,
        xBadWindow,
        xBadPixmap,
        xBadAtom,
        xBadCursor,
        xBadFont,
        xBadMatch,
        xBadDrawable,
        xBadAccess,
        xBadAlloc,
        xBadColor,
        xBadGC,
        xBadIDChoice,
        xBadName,
        xBadLength,
        xBadImplementation,

        glxBadContext,
        glxBadContextState,
        glxBadDrawable,
        glxBadPixmap,
        glxBadContextTag,
        glxBadCurrentWindow,
        glxBadRenderRequest,
        glxBadLargeRequest,
        glxUnsupportedPrivateRequest,
        glxBadFBConfig,
        glxBadPbuffer,
        glxBadCurrentDrawable,
        glxBadWindow,

        pub fn from(error_code: u8) ?ErrorCode {
            const code = if (error_code > 0) error_code - 1 else return null;
            const xerrors = [_]ErrorCode{
                .xBadRequest,
                .xBadValue,
                .xBadWindow,
                .xBadPixmap,
                .xBadAtom,
                .xBadCursor,
                .xBadFont,
                .xBadMatch,
                .xBadDrawable,
                .xBadAccess,
                .xBadAlloc,
                .xBadColor,
                .xBadGC,
                .xBadIDChoice,
                .xBadName,
                .xBadLength,
                .xBadImplementation,
            };
            if (code < xerrors.len) {
                return xerrors[code];
            }
            if (glx_base_error) |base_error| {
                if (code >= base_error) {
                    const glx_errors = [_]ErrorCode{
                        .glxBadContext,
                        .glxBadContextState,
                        .glxBadDrawable,
                        .glxBadPixmap,
                        .glxBadContextTag,
                        .glxBadCurrentWindow,
                        .glxBadRenderRequest,
                        .glxBadLargeRequest,
                        .glxUnsupportedPrivateRequest,
                        .glxBadFBConfig,
                        .glxBadPbuffer,
                        .glxBadCurrentDrawable,
                        .glxBadWindow,
                    };
                    const be = @intCast(usize, base_error);
                    if (code < be + glx_errors.len) {
                        return glx_errors[code - be];
                    }
                }
            }
            return null;
        }
    };

    pub const RequestCode = enum(u8) {
        none = 0,
        createWindow = c.X_CreateWindow,
        changeWindowAttributes = c.X_ChangeWindowAttributes,
        getWindowAttributes = c.X_GetWindowAttributes,
        destroyWindow = c.X_DestroyWindow,
        destroySubwindows = c.X_DestroySubwindows,
        changeSaveSet = c.X_ChangeSaveSet,
        reparentWindow = c.X_ReparentWindow,
        mapWindow = c.X_MapWindow,
        mapSubwindows = c.X_MapSubwindows,
        unmapWindow = c.X_UnmapWindow,
        unmapSubwindows = c.X_UnmapSubwindows,
        configureWindow = c.X_ConfigureWindow,
        circulateWindow = c.X_CirculateWindow,
        getGeometry = c.X_GetGeometry,
        queryTree = c.X_QueryTree,
        internAtom = c.X_InternAtom,
        getAtomName = c.X_GetAtomName,
        changeProperty = c.X_ChangeProperty,
        deleteProperty = c.X_DeleteProperty,
        getProperty = c.X_GetProperty,
        listProperties = c.X_ListProperties,
        setSelectionOwner = c.X_SetSelectionOwner,
        getSelectionOwner = c.X_GetSelectionOwner,
        convertSelection = c.X_ConvertSelection,
        sendEvent = c.X_SendEvent,
        grabPointer = c.X_GrabPointer,
        ungrabPointer = c.X_UngrabPointer,
        grabButton = c.X_GrabButton,
        ungrabButton = c.X_UngrabButton,
        changeActivePointerGrab = c.X_ChangeActivePointerGrab,
        grabKeyboard = c.X_GrabKeyboard,
        ungrabKeyboard = c.X_UngrabKeyboard,
        grabKey = c.X_GrabKey,
        ungrabKey = c.X_UngrabKey,
        allowEvents = c.X_AllowEvents,
        grabServer = c.X_GrabServer,
        ungrabServer = c.X_UngrabServer,
        queryPointer = c.X_QueryPointer,
        getMotionEvents = c.X_GetMotionEvents,
        translateCoords = c.X_TranslateCoords,
        warpPointer = c.X_WarpPointer,
        setInputFocus = c.X_SetInputFocus,
        getInputFocus = c.X_GetInputFocus,
        queryKeymap = c.X_QueryKeymap,
        openFont = c.X_OpenFont,
        closeFont = c.X_CloseFont,
        queryFont = c.X_QueryFont,
        queryTextExtents = c.X_QueryTextExtents,
        listFonts = c.X_ListFonts,
        listFontsWithInfo = c.X_ListFontsWithInfo,
        setFontPath = c.X_SetFontPath,
        getFontPath = c.X_GetFontPath,
        createPixmap = c.X_CreatePixmap,
        freePixmap = c.X_FreePixmap,
        createGC = c.X_CreateGC,
        changeGC = c.X_ChangeGC,
        copyGC = c.X_CopyGC,
        setDashes = c.X_SetDashes,
        setClipRectangles = c.X_SetClipRectangles,
        freeGC = c.X_FreeGC,
        clearArea = c.X_ClearArea,
        copyArea = c.X_CopyArea,
        copyPlane = c.X_CopyPlane,
        polyPoint = c.X_PolyPoint,
        polyLine = c.X_PolyLine,
        polySegment = c.X_PolySegment,
        polyRectangle = c.X_PolyRectangle,
        polyArc = c.X_PolyArc,
        fillPoly = c.X_FillPoly,
        polyFillRectangle = c.X_PolyFillRectangle,
        polyFillArc = c.X_PolyFillArc,
        putImage = c.X_PutImage,
        getImage = c.X_GetImage,
        polyText8 = c.X_PolyText8,
        polyText16 = c.X_PolyText16,
        imageText8 = c.X_ImageText8,
        imageText16 = c.X_ImageText16,
        createColormap = c.X_CreateColormap,
        freeColormap = c.X_FreeColormap,
        copyColormapAndFree = c.X_CopyColormapAndFree,
        installColormap = c.X_InstallColormap,
        uninstallColormap = c.X_UninstallColormap,
        listInstalledColormaps = c.X_ListInstalledColormaps,
        allocColor = c.X_AllocColor,
        allocNamedColor = c.X_AllocNamedColor,
        allocColorCells = c.X_AllocColorCells,
        allocColorPlanes = c.X_AllocColorPlanes,
        freeColors = c.X_FreeColors,
        storeColors = c.X_StoreColors,
        storeNamedColor = c.X_StoreNamedColor,
        queryColors = c.X_QueryColors,
        lookupColor = c.X_LookupColor,
        createCursor = c.X_CreateCursor,
        createGlyphCursor = c.X_CreateGlyphCursor,
        freeCursor = c.X_FreeCursor,
        recolorCursor = c.X_RecolorCursor,
        queryBestSize = c.X_QueryBestSize,
        queryExtension = c.X_QueryExtension,
        listExtensions = c.X_ListExtensions,
        changeKeyboardMapping = c.X_ChangeKeyboardMapping,
        getKeyboardMapping = c.X_GetKeyboardMapping,
        changeKeyboardControl = c.X_ChangeKeyboardControl,
        getKeyboardControl = c.X_GetKeyboardControl,
        bell = c.X_Bell,
        changePointerControl = c.X_ChangePointerControl,
        getPointerControl = c.X_GetPointerControl,
        setScreenSaver = c.X_SetScreenSaver,
        getScreenSaver = c.X_GetScreenSaver,
        changeHosts = c.X_ChangeHosts,
        listHosts = c.X_ListHosts,
        setAccessControl = c.X_SetAccessControl,
        setCloseDownMode = c.X_SetCloseDownMode,
        killClient = c.X_KillClient,
        rotateProperties = c.X_RotateProperties,
        forceScreenSaver = c.X_ForceScreenSaver,
        setPointerMapping = c.X_SetPointerMapping,
        getPointerMapping = c.X_GetPointerMapping,
        setModifierMapping = c.X_SetModifierMapping,
        getModifierMapping = c.X_GetModifierMapping,
        noOperation = c.X_NoOperation,
        _,
    };

    pub const ErrorInstance = struct {
        code: ErrorCode,
        request: RequestCode,

        pub fn from(event: *c.XErrorEvent) ?ErrorInstance {
            return ErrorInstance{
                .code = ErrorCode.from(event.error_code) orelse return null,
                .request = @intToEnum(
                    RequestCode,
                    event.request_code,
                ),
            };
        }
    };
    pub const ErrorList = std.BoundedArray(ErrorInstance, 50); // some number
    // TODO: should this be made thread safe?
    pub var list = ErrorList{};

    pub fn has() !void {
        if (list.len != 0) return error.X11Error;
    }

    var previous_error_handler: c.XErrorHandler = null;
    var our_display: ?*c.Display = null;

    fn xErrorHandler(display: ?*c.Display, event: ?*c.XErrorEvent) callconv(.C) c_int {
        if (display) |d| if (our_display) |our| if (event) |e| if (our == d) {
            if (ErrorInstance.from(e)) |inst| {
                if (list.len < list.buffer.len) {
                    list.appendAssumeCapacity(inst);
                } else {
                    std.log.warn("unlogged Xlib error: {any}", .{inst});
                }
            }
            return 0;
        };
        if (previous_error_handler) |prev| {
            return prev(display, event);
        } else {
            return 0;
        }
    }

    /// only call once
    pub fn initHandler() void {
        previous_error_handler = c.XSetErrorHandler(xErrorHandler);
    }

    var glx_base_error: ?c_int = null;
    var glx_base_event: ?c_int = null;

    /// finds glx error offset, and sets display for error filtering
    pub fn initErrors(display: Display) bool {
        our_display = display.inner;
        var ber: c_int = undefined;
        var bev: c_int = undefined;
        const result = c.glXQueryExtension(display.inner, &ber, &bev) == c.True;
        if (result) {
            glx_base_error = ber;
            glx_base_event = bev;
        }
        return result;
    }
};

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

pub fn boolToCBool(val: bool) c.Bool {
    return if (val) c.True else c.False;
}
pub const Display = struct {
    inner: *c.Display,

    pub fn open(name: ?[:0]const u8) ?Display {
        if (c.XOpenDisplay((name orelse "").ptr)) |display| {
            return Display{ .inner = display };
        }
        return null;
    }
    pub fn close(self: Display) void {
        _ = c.XCloseDisplay(self.inner);
    }
    pub fn setWMProtocols(self: Display, window: Window, protocols: []Atom) !void {
        if (c.XSetWMProtocols(
            self.inner,
            window.inner,
            protocols.ptr,
            @intCast(c_int, protocols.len),
        ) == 0)
            try errors.has();
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
            boolToCBool(propagate),
            @bitCast(c_long, event_mask),
            event,
        ) == 0)
            try errors.has();
    }
    pub fn flush(self: Display) void {
        _ = c.XFlush(self.inner);
    }
    pub fn makeCurrent(self: Display, window: Window, context: Context) !void {
        if (c.glXMakeCurrent(self.inner, window.inner, context.inner) == 0)
            try errors.has();
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

    pub fn swapBuffers(display: Display, window: Window) void {
        c.glXSwapBuffers(display.inner, window.inner);
    }

    pub fn storeName(display: Display, window: Window, s: [:0]const u8) void {
        _ = c.XStoreName(display.inner, window.inner, s.ptr);
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
        try errors.has();
        return Window{ .inner = window };
    }
    pub fn unmap(self: Window, display: Display) void {
        _ = c.XUnmapWindow(display.inner, self.inner);
    }
    pub fn map(self: Window, display: Display) void {
        _ = c.XMapWindow(display.inner, self.inner);
    }
    pub fn destroy(self: Window, display: Display) void {
        _ = c.XDestroyWindow(display.inner, self.inner);
    }
    pub fn getAttributes(self: Window, display: Display) !c.XWindowAttributes {
        var attr: c.XWindowAttributes = undefined;
        if (c.XGetWindowAttributes(display.inner, self.inner, &attr) == 0)
            try errors.has();
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
        try errors.has();
        return Colormap{ .inner = colormap };
    }

    pub fn free(self: Colormap, display: Display) void {
        _ = c.XFreeColormap(display.inner, self.inner);
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
        _ = c.XFree(self.inner);
        self.* = undefined;
    }
};

pub const Visual = struct {
    inner: *c.Visual,
};

pub const Atom = c.Atom;

pub fn internAtom(display: Display, name: [:0]const u8, only_if_exists: bool) !Atom {
    const atom = c.XInternAtom(display.inner, name.ptr, boolToCBool((only_if_exists)));
    try errors.has();
    return atom;
}

pub const Context = struct {
    inner: c.GLXContext,

    pub const None = Context{ .inner = null };

    pub fn create(
        display: Display,
        visual_info: VisualInfo,
        share_list: Context,
        direct: bool,
    ) !Context {
        const ctx = c.glXCreateContext(
            display.inner,
            visual_info.inner,
            share_list.inner,
            boolToCBool(direct),
        );
        try errors.has();
        return Context{ .inner = ctx };
    }
    pub fn destroy(self: Context, display: Display) void {
        c.glXDestroyContext(display.inner, self.inner);
    }
};
