const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const pge = @import("pge.zig");
const V2D = pge.V2D;
const VF2D = pge.VF2D;
const EngineState = pge.EngineState;
const MaxVerts = pge.MaxVerts;
const Sprite = pge.Sprite;
const LocVertex = pge.LocVertex;
const Pixel = pge.Pixel;

const x = @import("x11.zig");
const g = @import("gl.zig");

// TODO: name "Window" or something like that?
pub const XState = struct {
    display: x.Display,
    window_root: x.Window,
    window: x.Window,
    visual_info: x.VisualInfo,
    color_map: x.Colormap,

    pub fn init(
        window_pos: V2D,
        window_size: *V2D,
        full_screen: bool,
        name: [:0]const u8,
    ) !XState {
        if (!x.initThreads())
            std.log.warn("X says it doesn't support multithreading", .{});
        x.errors.initHandler();

        const display = x.Display.open(null) orelse return error.DisplayOpenFailure;
        errdefer display.close();
        if (!x.errors.initErrors(display)) return error.XErrorInitializationFailure;
        const window_root = display.defaultRootWindow();

        var visual_info = x.chooseVisual(display, 0, .{
            .rgba = true,
            .depth_size = 24,
            .doublebuffer = true,
        });
        errdefer visual_info.deinit();

        const color_map = try x.Colormap.create(display, window_root, visual_info.visual(), .none);
        errdefer color_map.free(display);

        const window = try x.Window.create(
            display,
            window_root,
            window_pos.x,
            window_pos.y,
            @intCast(u32, window_size.x),
            @intCast(u32, window_size.y),
            0,
            visual_info.depth(),
            .InputOutput,
            visual_info.visual(),
            .{ .colormap = true, .event_mask = true },
            .{ .colormap = color_map.inner, .event_mask = .{
                .key_press = true,
                .key_release = true,
                .button_press = true,
                .button_release = true,
                .pointer_motion = true,
                .focus_change = true,
                .structure_notify = true,
            } },
        );
        errdefer window.destroy(display);

        var wm_delete = try x.internAtom(display, "WM_DELETE_WINDOW", true);
        try display.setWMProtocols(window, @as(*[1]x.Atom, &wm_delete));

        window.map(display);
        display.storeName(window, name);

        if (full_screen) {
            const wm_state = try x.internAtom(display, "_NET_WM_STATE", false);
            const wm_state_fullscreen = try x.internAtom(display, "_NET_WM_STATE_FULLSCREEN", false);

            // i didnt write a nice abstracted way to interface with x11 here
            var xev = std.mem.zeroes(x.c.XEvent);
            xev.type = x.c.ClientMessage;
            xev.xclient.window = window.inner;
            xev.xclient.message_type = wm_state;
            xev.xclient.format = 32;
            xev.xclient.data.l = [5]c_long{ @boolToInt(full_screen), @intCast(c_long, wm_state_fullscreen), 0, 0, 0 };

            window.map(display);
            try display.sendEvent(
                window_root,
                false,
                .{ .substructure_redirect = true, .substructure_notify = true },
                &xev,
            );
            display.flush();

            const gwa = try window.getAttributes(display);
            window_size.* = .{ .x = gwa.width, .y = gwa.height };
        }

        return XState{
            .display = display,
            .window_root = window_root,
            .visual_info = visual_info,
            .color_map = color_map,
            .window = window,
        };
    }
    pub fn deinit(self: *XState) void {
        self.visual_info.deinit();
        self.window.destroy(self.display);
        self.color_map.free(self.display);
        self.window.destroy(self.display);
        self.* = undefined;
    }
};

x_state: XState,

device_context: x.Context,

n_fs: ge.Shader,
n_vs: ge.Shader,
n_quad: ge.Program,
vb_quad: ge.Buffer,
va_quad: ge.VertexArray,
blank_quad: pge.OwnedDecal,

decal_mode: pge.DecalMode = .Normal,

pub const ge = g.Extensions(.{
    .{ "glXSwapIntervalEXT", fn (*x.c.Display, x.c.GLXDrawable, c_int) callconv(.C) void },
    .{ "glCreateShader", fn (x.c.GLenum) callconv(.C) x.c.GLuint, true },
    .{ "glCompileShader", fn (x.c.GLuint) callconv(.C) void, true },
    .{ "glShaderSource", fn (x.c.GLuint, x.c.GLsizei, [*]const [:0]const u8, ?[*]x.c.GLint) callconv(.C) void, true },
    .{ "glDeleteShader", fn (x.c.GLuint) callconv(.C) void, true },
    .{ "glCreateProgram", fn () callconv(.C) x.c.GLuint, true },
    .{ "glDeleteProgram", fn (x.c.GLuint) callconv(.C) void, true },
    .{ "glLinkProgram", fn (x.c.GLuint) callconv(.C) void, true },
    .{ "glAttachShader", fn (x.c.GLuint, x.c.GLuint) callconv(.C) void, true },
    .{ "glBindBuffer", fn (x.c.GLenum, x.c.GLuint) callconv(.C) void, true },
    .{ "glBufferData", fn (x.c.GLenum, x.c.GLsizeiptr, *const anyopaque, x.c.GLenum) callconv(.C) void, true },
    .{ "glGenBuffers", fn (x.c.GLsizei, [*]x.c.GLuint) callconv(.C) void, true },
    .{ "glDeleteBuffers", fn (x.c.GLsizei, [*]const x.c.GLuint) callconv(.C) void, true },
    .{ "glVertexAttribPointer", fn (x.c.GLuint, x.c.GLint, x.c.GLenum, x.c.GLboolean, x.c.GLsizei, usize) callconv(.C) void, true },
    .{ "glEnableVertexAttribArray", fn (x.c.GLuint) callconv(.C) void, true },
    .{ "glUseProgram", fn (x.c.GLuint) callconv(.C) void },
    .{ "glGetShaderInfoLog", fn (x.c.GLuint, [*c]const u8) callconv(.C) void },
    .{ "glBindVertexArray", fn (x.c.GLuint) callconv(.C) void, true },
    .{ "glGenVertexArrays", fn (x.c.GLsizei, [*]x.c.GLuint) callconv(.C) void, true },
    .{ "glDeleteVertexArrays", fn (x.c.GLsizei, [*]const x.c.GLuint) callconv(.C) void, true },
    .{ "glGetShaderiv", fn (x.c.GLuint, x.c.GLenum, *x.c.GLint) callconv(.C) void, true },
});
const Self = @This();

pub fn init(alloc: Allocator, state: *EngineState, name: [:0]const u8) !Self {
    var x_state = try XState.init(
        .{ .x = 30, .y = 30 },
        &state.window_size,
        state.full_screen,
        name,
    );
    errdefer x_state.deinit();

    state.updateViewport();

    const ctx = try x.Context.create(x_state.display, x_state.visual_info, x.Context{ .inner = null }, true);
    errdefer ctx.destroy(x_state.display);
    try x_state.display.makeCurrent(x_state.window, ctx);
    errdefer x_state.display.makeCurrent(x.Window{ .inner = 0 }, x.Context{ .inner = null }) catch unreachable;

    const gwa = try x_state.window.getAttributes(x_state.display);
    g.viewport(0, 0, @intCast(u32, gwa.width), @intCast(u32, gwa.height));

    try ge.load();

    if (!state.vsync)
        if (ge.has("glXSwapIntervalEXT"))
            ge.swapInterval(x_state.display, x_state.window.inner, 0)
        else
            std.log.warn("cannot disable vsync (no glXSwapIntervalEXT)", .{});

    // why did pge hardcode the number here to specify fragment shader?
    var nFS = ge.Shader.init(.Fragment);
    errdefer nFS.deinit();
    // note: following shaders not made for arm. see relevant olcPixelGameEngine source
    const strFS =
        \\#version 330 core
        \\out vec4 pixel;
        \\in vec2 oTex;
        \\in vec4 oCol;
        \\uniform sampler2D sprTex;
        \\void main() {
        \\  pixel = texture(sprTex, oTex) * oCol;
        \\}
    ;
    nFS.source(&[1][:0]const u8{strFS}, null);
    nFS.compile();
    if (!nFS.getCompileStatus()) return error.ShaderCompilationFailure;

    var nVS = ge.Shader.init(.Vertex);
    errdefer nVS.deinit();
    const strVS =
        \\#version 330 core
        \\layout(location = 0) in vec3 aPos;
        \\layout(location = 1) in vec2 aTex;
        \\layout(Location = 2) in vec4 aCol;
        \\out vec2 oTex;
        \\out vec4 oCol;
        \\
        \\void main() {
        \\  float p = 1.0 / aPos.z;
        \\  gl_Position = p * vec4(aPos.x, aPos.y, 0.0, 1.0);
        \\  oTex = p * aTex;
        \\  oCol = aCol;
        \\}
    ;
    nVS.source(&[1][:0]const u8{strVS}, null);
    nVS.compile();
    if (!nVS.getCompileStatus()) return error.ShaderCompilationFailure;

    var quad = ge.Program.init();
    errdefer quad.deinit();
    try quad.attachShader(nFS);
    try quad.attachShader(nVS);
    try quad.link();

    var vb_quad = ge.Buffer.init();
    errdefer vb_quad.deinit();
    var va_quad = ge.VertexArray.init();
    errdefer va_quad.deinit();
    va_quad.bind();
    vb_quad.bind(.Array);

    var verts: [MaxVerts]LocVertex = undefined;
    try ge.Buffer.data(.Array, LocVertex, &verts, .StreamDraw);
    try ge.vertexAttribPointer(0, 3, .Float, false, @sizeOf(LocVertex), @offsetOf(LocVertex, "pos"));
    ge.enableVertexAttribArray(0);
    try ge.vertexAttribPointer(1, 2, .Float, false, @sizeOf(LocVertex), @offsetOf(LocVertex, "tex"));
    ge.enableVertexAttribArray(1);
    try ge.vertexAttribPointer(2, 4, .UnsignedByte, true, @sizeOf(LocVertex), @offsetOf(LocVertex, "col"));
    ge.enableVertexAttribArray(2);
    ge.Buffer.None.bind(.Array);
    ge.VertexArray.None.bind();

    updateViewport(state.view_pos, state.view_size);

    var blank_sprite: *Sprite = undefined;
    var blank_quad: pge.OwnedDecal = undefined;
    {
        // TODO: could we do OwnedDecal.initSize here?
        blank_sprite = try alloc.create(Sprite);
        errdefer alloc.destroy(blank_sprite);
        blank_sprite.* = try Sprite.initSize(alloc, 1, 1);
        errdefer blank_sprite.deinit(alloc);
        blank_sprite.data[0] = Pixel.White;

        blank_quad = pge.OwnedDecal{
            .inner = try pge.Decal.init(blank_sprite, false, true),
        };
    }
    errdefer blank_quad.deinit(alloc);
    try blank_quad.inner.update(); // may be unnecessary to call this here

    return Self{
        .x_state = x_state,
        .n_quad = quad,
        .vb_quad = vb_quad,
        .va_quad = va_quad,
        .device_context = ctx,
        .n_fs = nFS,
        .n_vs = nVS,
        .blank_quad = blank_quad,
    };
}
pub fn deinit(self: *Self, alloc: Allocator) void {
    self.x_state.display.makeCurrent(x.Window.None, x.Context.None) catch unreachable;
    self.device_context.destroy(self.x_state.display);
    self.va_quad.deinit();
    self.vb_quad.deinit();
    self.n_quad.deinit();
    self.n_vs.deinit();
    self.n_fs.deinit();
    self.blank_quad.deinit(alloc);
    self.x_state.deinit();
    self.* = undefined;
}

pub fn updateViewport(pos: V2D, size: V2D) void {
    g.viewport(pos.x, pos.y, @intCast(u32, size.x), @intCast(u32, size.y));
}

pub const Texture = struct {
    inner: g.Texture,

    pub fn init(width: u32, height: u32, filter: bool, clamp: bool) !Texture {
        _ = width;
        _ = height;
        var tex = g.Texture.init();
        errdefer tex.deinit();
        tex.bind(.TwoD);

        // hopefully order doesnt matter. noted that the pge code isnt in same order
        comptime var P = g.TextureParameterValue(.MinFilter); // i guess zig type inference isnt good enough?
        g.texParameter(.TwoD, .MinFilter, if (filter) P.Linear else P.Nearest);
        P = g.TextureParameterValue(.MagFilter);
        g.texParameter(.TwoD, .MagFilter, if (filter) P.Linear else P.Nearest);
        // note: pge uses GL_CLAMP, not GL_CLAMP_TO_EDGE here. unsure if this is a problem
        P = g.TextureParameterValue(.WrapS);
        g.texParameter(.TwoD, .WrapS, if (clamp) P.ClampToEdge else P.Repeat);
        P = g.TextureParameterValue(.WrapT);
        g.texParameter(.TwoD, .WrapT, if (clamp) P.ClampToEdge else P.Repeat);

        return Texture{ .inner = tex };
    }
    pub fn deinit(tex: *Texture) void {
        tex.inner.deinit();
    }
    // this feels like a backend specific thing to do? TODO: see how non-opengl does something like this
    pub fn apply(tex: Texture) !void {
        tex.inner.bind(.TwoD);
    }
    pub fn update(tex: Texture, sprite: *Sprite) void {
        _ = tex;
        g.texImage2D(
            .TwoD,
            0,
            .RGBA,
            @intCast(u32, sprite.width),
            @intCast(u32, sprite.height),
            0,
            .RGBA,
            .UnsignedByte,
            @ptrCast([*]const u8, sprite.data.ptr),
        );
    }

    pub fn read(tex: Texture, sprite: *Sprite) void {
        _ = tex;
        g.readPixels(0, 0, @intCast(u32, sprite.width), @intCast(u32, sprite.height), .RGBA, .UnsignedByte, sprite.data.ptr);
    }
};

pub fn clearBuffer(p: Pixel, comptime depth: bool) void {
    g.clear(&(.{.Color} ++ if (depth) .{.Depth} else .{}), .{ .color = .{
        .r = @intToFloat(f32, p.c.r) / 255.0,
        .g = @intToFloat(f32, p.c.g) / 255.0,
        .b = @intToFloat(f32, p.c.b) / 255.0,
        .a = @intToFloat(f32, p.c.a) / 255.0,
    } });
}

pub fn handleSystemEvent(self: *Self, p: *EngineState) !void {
    while (true) {
        const count = self.x_state.display.pending();
        if (count == 0) break;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            var xev = self.x_state.display.nextEvent();
            switch (xev.type) {
                x.c.Expose => {
                    const attr = try self.x_state.window.getAttributes(self.x_state.display); // should be no error
                    p.updateWindowSize(.{ .x = attr.width, .y = attr.height });
                },
                x.c.ConfigureNotify => {
                    p.updateWindowSize(.{
                        .x = xev.xconfigure.width,
                        .y = xev.xconfigure.height,
                    });
                },
                x.c.KeyPress => {
                    if (mapKey(x.c.XLookupKeysym(&xev.xkey, 0))) |key| p.updateKeyState(key, true);
                },
                x.c.KeyRelease => {
                    if (mapKey(x.c.XLookupKeysym(&xev.xkey, 0))) |key| p.updateKeyState(key, false);
                },
                x.c.ButtonPress => switch (xev.xbutton.button) {
                    x.c.Button1 => p.mouse_state.insert(.Left),
                    x.c.Button2 => p.mouse_state.insert(.Middle),
                    x.c.Button3 => p.mouse_state.insert(.Right),
                    x.c.Button4 => p.mouse_wheel_delta_cache += pge.MouseScrollAmount,
                    x.c.Button5 => p.mouse_wheel_delta_cache -= pge.MouseScrollAmount,
                    else => {},
                },
                x.c.ButtonRelease => switch (xev.xbutton.button) {
                    x.c.Button1 => p.mouse_state.remove(.Left),
                    x.c.Button2 => p.mouse_state.remove(.Middle),
                    x.c.Button3 => p.mouse_state.remove(.Right),
                    else => {},
                },
                x.c.MotionNotify => {
                    p.mouse_pos_cache = .{ .x = xev.xmotion.x, .y = xev.xmotion.y };
                },
                x.c.FocusIn => p.has_input_focus = true,
                x.c.FocusOut => p.has_input_focus = false,
                x.c.ClientMessage => p.active.store(false, .Monotonic),
                else => {},
            }
        }
    }
    x.errors.has() catch |e| {
        for (x.errors.list.slice()) |inst|
            std.log.err("X error: {any}", .{inst});
        x.errors.list.len = 0;
        return e;
    };
}

pub fn setDecalMode(self: *Self, mode: pge.DecalMode) void {
    self.decal_mode = mode;
    g.blendFunc(
        switch (mode) {
            .Normal, .Additive, .Wireframe => .SrcAlpha,
            .Multiplicative => .DstColor,
            .Stencil => .Zero,
            .Illuminate => .OneMinusSrcAlpha,
            else => return,
        },
        switch (mode) {
            .Normal, .Multiplicative, .Wireframe => .OneMinusSrcAlpha,
            .Additive => .One,
            .Stencil, .Illuminate => .SrcAlpha,
            else => return,
        },
    );
}

pub fn prepareDrawing(self: *Self) void {
    g.enable(.Blend);
    self.setDecalMode(.Normal);
    self.n_quad.use();
    self.va_quad.bind();
}

pub fn drawLayerQuad(self: *Self, offset: VF2D, scale: VF2D, tint: Pixel) !void {
    self.vb_quad.bind(.Array);
    const verts = [4]LocVertex{
        .{
            .pos = .{ -1.0, -1.0, 1.0 },
            .tex = .{ .x = 0.0 * scale.x + offset.x, .y = 1.0 * scale.y + offset.y },
            .col = tint,
        },
        .{
            .pos = .{ 1.0, -1.0, 1.0 },
            .tex = .{ .x = 1.0 * scale.x + offset.x, .y = 1.0 * scale.y + offset.y },
            .col = tint,
        },
        .{
            .pos = .{ -1.0, 1.0, 1.0 },
            .tex = .{ .x = 0.0 * scale.x + offset.x, .y = 0.0 * scale.y + offset.y },
            .col = tint,
        },
        .{
            .pos = .{ 1.0, 1.0, 1.0 },
            .tex = .{ .x = 1.0 * scale.x + offset.x, .y = 0.0 * scale.y + offset.y },
            .col = tint,
        },
    };
    try ge.Buffer.data(.Array, LocVertex, &verts, .StreamDraw);
    g.drawArrays(.TriangleStrip, 0, 4);
}
/// `DecalStructure.Line` will draw nothing
pub fn drawDecal(self: *Self, decal: pge.DecalInstance) !void {
    self.setDecalMode(decal.mode);
    decal.decal.tex.inner.bind(.TwoD);
    self.vb_quad.bind(.Array);
    try ge.Buffer.data(.Array, LocVertex, decal.vertices, .StreamDraw);
    g.drawArrays(if (self.decal_mode == .Wireframe)
        .LineLoop
    else switch (decal.structure) {
        .Fan => .TriangleFan,
        .Strip => .TriangleStrip,
        .List => .Triangles,
        .Line => return,
    }, 0, @intCast(u32, decal.vertices.len));
}

pub fn displayFrame(self: *Self) void {
    self.x_state.display.swapBuffers(self.x_state.window);
}

pub fn setWindowTitle(self: *Self, title: [:0]const u8) void {
    self.x_state.display.storeName(self.x_state.window, title);
}

pub fn mapKey(val: x.c.KeySym) ?pge.Key {
    const c = x.c;
    return switch (val) {
        c.XK_a => .A,
        c.XK_b => .B,
        c.XK_c => .C,
        c.XK_d => .D,
        c.XK_e => .E,
        c.XK_f => .F,
        c.XK_g => .G,
        c.XK_h => .H,
        c.XK_i => .I,
        c.XK_j => .J,
        c.XK_k => .K,
        c.XK_l => .L,
        c.XK_m => .M,
        c.XK_n => .N,
        c.XK_o => .O,
        c.XK_p => .P,
        c.XK_q => .Q,
        c.XK_r => .R,
        c.XK_s => .S,
        c.XK_t => .T,
        c.XK_u => .U,
        c.XK_v => .V,
        c.XK_w => .W,
        c.XK_x => .X,
        c.XK_y => .Y,
        c.XK_z => .Z,

        c.XK_F1 => .F1,
        c.XK_F2 => .F2,
        c.XK_F3 => .F3,
        c.XK_F4 => .F4,
        c.XK_F5 => .F5,
        c.XK_F6 => .F6,
        c.XK_F7 => .F7,
        c.XK_F8 => .F8,
        c.XK_F9 => .F9,
        c.XK_F10 => .F10,
        c.XK_F11 => .F11,
        c.XK_F12 => .F12,

        c.XK_Down => .Down,
        c.XK_Left => .Left,
        c.XK_Right => .Right,
        c.XK_Up => .Up,

        c.XK_Return, c.XK_Linefeed, c.XK_KP_Enter => .Enter,
        c.XK_BackSpace => .Back,
        c.XK_Escape => .Escape,
        c.XK_Pause => .Pause,
        c.XK_Scroll_Lock => .Scroll,
        c.XK_Tab => .Tab,
        c.XK_Delete => .Del,
        c.XK_Home => .Home,
        c.XK_End => .End,
        c.XK_Page_Up => .PgUp,
        c.XK_Page_Down => .PgDn,
        c.XK_Insert => .Ins,
        c.XK_Shift_L, c.XK_Shift_R => .Shift,
        c.XK_Control_L, c.XK_Control_R => .Ctrl,
        c.XK_space => .Space,
        c.XK_period => .Period,
        c.XK_Caps_Lock => .CapsLock,

        c.XK_0 => .K0,
        c.XK_1 => .K1,
        c.XK_2 => .K2,
        c.XK_3 => .K3,
        c.XK_4 => .K4,
        c.XK_5 => .K5,
        c.XK_6 => .K6,
        c.XK_7 => .K7,
        c.XK_8 => .K8,
        c.XK_9 => .K9,

        c.XK_KP_0 => .NP0,
        c.XK_KP_1 => .NP1,
        c.XK_KP_2 => .NP2,
        c.XK_KP_3 => .NP3,
        c.XK_KP_4 => .NP4,
        c.XK_KP_5 => .NP5,
        c.XK_KP_6 => .NP6,
        c.XK_KP_7 => .NP7,
        c.XK_KP_8 => .NP8,
        c.XK_KP_9 => .NP9,

        c.XK_KP_Multiply => .NpMul,
        c.XK_KP_Add => .NpAdd,
        c.XK_KP_Divide => .NpDiv,
        c.XK_KP_Subtract => .NpSub,
        c.XK_KP_Decimal => .NpDecimal,

        c.XK_semicolon => .OEM_1,
        c.XK_slash => .OEM_2,
        c.XK_asciitilde => .OEM_3,
        c.XK_bracketleft => .OEM_4,
        c.XK_backslash => .OEM_5,
        c.XK_bracketright => .OEM_6,
        c.XK_apostrophe => .OEM_7,
        c.XK_numbersign => .OEM_8,
        c.XK_equal => .EQUALS,
        c.XK_comma => .COMMA,
        c.XK_minus => .MINUS,

        else => null,
    };
}
