const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const Impl = LinuxImpl;

pub const NormalizedKey = blk: {
    const info = @typeInfo(Impl.Key).Enum;
    comptime var fields: [info.fields.len]std.builtin.Type.EnumField = undefined;
    comptime var i = 0;
    inline for (fields) |*field| {
        field.* = .{
            .name = info.fields[i].name,
            .value = i,
        };
        i += 1;
    }
    break :blk @Type(.{ .Enum = .{
        .tag_type = std.math.IntFittingRange(0, fields.len - 1),
        .fields = &fields,
        .decls = &.{},
        .is_exhaustive = true,
        .layout = .Auto,
    } });
};
pub fn normalizeKey(key: Impl.Key) ?NormalizedKey {
    const info = @typeInfo(Impl.Key).Enum;
    inline for (info.fields) |field| {
        if (@field(Impl.Key, field.name) == key) {
            return @field(NormalizedKey, field.name);
        }
    }
    return null;
    // TODO: inline else?
}

pub const MouseButton = enum {
    Left,
    Middle,
    Right,
};
pub const MouseScrollAmount = 120;

pub const V2D = struct {
    x: i32,
    y: i32,

    pub const Zero = V2D{ .x = 0, .y = 0 };
};
pub const VF2D = extern struct { x: f32, y: f32 };

pub const EngineState = struct {
    app_name: []const u8 = "pge game",
    screen_size: V2D,
    pixel_size: V2D = .{ .x = 1, .y = 1 },
    pixel_cohesion: bool = false,
    full_screen: bool = false,
    vsync: bool = false,

    active: std.atomic.Atomic(bool) = .{ .value = true },
    window_size: V2D = V2D.Zero,
    view_pos: V2D = V2D.Zero,
    view_size: V2D = V2D.Zero,
    layers: std.ArrayListUnmanaged(Layer) = .{},
    draw_target: ?Sprite = null,
    last_time: i64,

    /// SCREEN SPACE
    mouse_pos_cache: V2D = V2D.Zero,
    /// PIXEL SPACE
    mouse_pos: V2D = V2D.Zero,

    mouse_wheel_delta_cache: i32 = 0,
    mouse_wheel_delta: i32 = 0,
    key_state: KeyState = KeyState.initEmpty(),
    old_key_state: KeyState = KeyState.initEmpty(),
    mouse_state: MouseState = MouseState.initEmpty(),
    old_mouse_state: MouseState = MouseState.initEmpty(),
    has_input_focus: bool = false,
    pixel_mode: PixelMode = .Normal,
    blend_factor: f32 = 1.0,

    font_sheet: ?OwnedDecal = null,

    pub const KeyState = std.EnumSet(NormalizedKey);
    pub const MouseState = std.EnumSet(MouseButton);

    const Self = @This();

    pub fn init(name: []const u8, pixel_size: V2D, screen_size: V2D) Self {
        assert(pixel_size.x > 0 and pixel_size.y > 0);
        assert(screen_size.x > 0 and screen_size.y > 0);
        return Self{
            .app_name = name,
            .screen_size = screen_size,
            .pixel_size = pixel_size,
            .window_size = .{
                .x = screen_size.x * pixel_size.x,
                .y = screen_size.y * pixel_size.y,
            },
            .last_time = std.time.milliTimestamp(),
        };
    }

    pub fn draw(self: *Self, pos: V2D, pixel: Pixel) void {
        var target = self.drawTarget();
        if (pos.x < 0 or pos.y < 0 or pos.x >= target.width or pos.y >= target.height) return;
        const x = @intCast(u32, pos.x);
        const y = @intCast(u32, pos.y);
        switch (self.pixel_mode) {
            .Normal => target.setPixel(x, y, pixel),
            .Mask => if (pixel.c.a == 255) target.setPixel(x, y, pixel),
            .Alpha => {
                const d = target.getPixel(x, y);
                const a = (@intToFloat(f32, pixel.c.a) / 255.0) / self.blend_factor;
                const c = 1.0 - a;
                target.setPixel(x, y, Pixel{ .c = .{
                    .r = @floatToInt(u8, a * @intToFloat(f32, pixel.c.r) + c * @intToFloat(f32, d.c.r)),
                    .g = @floatToInt(u8, a * @intToFloat(f32, pixel.c.g) + c * @intToFloat(f32, d.c.g)),
                    .b = @floatToInt(u8, a * @intToFloat(f32, pixel.c.b) + c * @intToFloat(f32, d.c.b)),
                } });
            },
        }
    }
    pub fn updateWindowSize(self: *Self, size: V2D) void {
        self.window_size = size;
        self.updateViewport();
    }
    pub fn updateViewport(self: *Self) void {
        if (self.pixel_cohesion) {
            self.view_size = .{
                .x = @divTrunc(self.window_size.x, self.screen_size.x) * self.screen_size.x,
                .y = @divTrunc(self.window_size.y, self.screen_size.y) * self.screen_size.y,
            };
        } else {
            const prev_size = V2D{
                .x = self.screen_size.x * self.pixel_size.x,
                .y = self.screen_size.y * self.pixel_size.y,
            };
            const aspect = @intToFloat(f32, prev_size.x) / @intToFloat(f32, prev_size.y);
            self.view_size = .{
                .x = self.window_size.x,
                .y = @floatToInt(i32, @intToFloat(f32, self.view_size.x) / aspect),
            };
            if (self.view_size.y > self.window_size.y) {
                self.view_size = .{
                    .x = @floatToInt(i32, @intToFloat(f32, self.window_size.y) * aspect),
                    .y = self.window_size.y,
                };
            }
        }
        self.view_pos = .{
            .x = @divTrunc(self.window_size.x - self.view_size.x, 2),
            .y = @divTrunc(self.window_size.y - self.view_size.y, 2),
        };
    }

    pub fn createLayer(self: *Self, alloc: Allocator) !usize {
        var layer = Layer{
            .draw_target = try OwnedDecal.initSize(
                alloc,
                @intCast(u32, self.screen_size.x),
                @intCast(u32, self.screen_size.y),
            ),
        };
        errdefer layer.draw_target.deinit(alloc);
        const id = self.layers.items.len;
        try self.layers.append(alloc, layer);
        return id;
    }
    pub fn drawTarget(self: *Self) *Sprite {
        return if (self.draw_target) |*t| t else self.layers.items[0].draw_target.inner.sprite;
    }
    // TODO: maybe this should accept already normalized keys?
    pub fn updateKeyState(self: *Self, key: Impl.Key, value: bool) void {
        if (normalizeKey(key)) |n_key| self.key_state.setPresent(n_key, value);
    }

    pub fn keyReleased(self: *Self, key: NormalizedKey) bool {
        return !self.key_state.contains(key) and self.old_key_state.contains(key);
    }
    pub fn keyPressed(self: *Self, key: NormalizedKey) bool {
        return self.key_state.contains(key) and !self.old_key_state.contains(key);
    }
    pub fn deinit(self: *Self, alloc: Allocator) void {
        if (self.font_sheet) |*font_sheet| font_sheet.deinit(alloc);
        for (self.layers.items) |*layer| layer.deinit(alloc);
        self.layers.deinit(alloc);
    }
};
pub fn PixelGameEngine(comptime UserGame: type) type {
    return struct {
        impl: Impl, // TODO: move impl into state?
        game: UserGame,
        state: EngineState,

        second_count: f32 = 0.0,
        frame_i: usize = 0,

        const Self = @This();
        pub fn init(
            alloc: Allocator,
            name: []const u8,
            game: UserGame,
            pixel_size: V2D,
            screen_size: V2D,
        ) !Self {
            var state = EngineState.init(name, pixel_size, screen_size);
            var impl = try Impl.init(alloc, &state);
            errdefer impl.deinit(alloc);

            state.font_sheet = constructFontSheet(alloc) catch |e| blk: {
                std.log.warn("Failed to construct font sheet: {any}", .{e});
                break :blk null;
            };

            return Self{
                .impl = impl,
                .game = game,
                .state = state,
            };
        }

        pub fn start(self: *Self, alloc: Allocator) !void {
            if (self.state.layers.items.len == 0) {
                _ = self.state.createLayer(alloc) catch |e| {
                    std.log.err("Failed to create initial draw layer: {any}", .{e});
                    return e;
                };
                self.state.layers.items[0].show = true;
                self.state.layers.items[0].update = true;
            }

            if (@hasDecl(UserGame, "onUserCreate"))
                if (!self.game.onUserCreate(alloc, &self.state)) self.state.active.store(false, .Monotonic);

            while (self.state.active.load(.Monotonic)) {
                self.update(alloc) catch |e| {
                    std.log.warn("Core update error: {any}", .{e});
                };
            }

            if (@hasDecl(UserGame, "onUserDestroy"))
                self.game.onUserDestroy(alloc, &self.state);

            // TODO: thread cleanup?
        }
        pub fn update(self: *Self, alloc: Allocator) !void {
            const now = std.time.milliTimestamp();
            const elapsed = now - self.state.last_time;
            self.state.last_time = now;
            const fElapsed = @intToFloat(f32, elapsed) / std.time.ms_per_s;

            // TODO: some console suspend time thing

            try self.impl.handleSystemEvent(&self.state);

            self.state.mouse_pos = .{
                .x = std.math.clamp(
                    @floatToInt(i32, @intToFloat(f32, self.state.mouse_pos_cache.x - self.state.view_pos.x) /
                        @intToFloat(f32, self.state.window_size.x - (self.state.view_pos.x * 2)) *
                        @intToFloat(f32, self.state.screen_size.x)),
                    0,
                    self.state.screen_size.x - 1,
                ),
                .y = std.math.clamp(
                    @floatToInt(i32, @intToFloat(f32, self.state.mouse_pos_cache.y - self.state.view_pos.y) /
                        @intToFloat(f32, self.state.window_size.y - (self.state.view_pos.y * 2)) *
                        @intToFloat(f32, self.state.screen_size.y)),
                    0,
                    self.state.screen_size.y - 1,
                ),
            };
            self.state.mouse_wheel_delta = self.state.mouse_wheel_delta_cache;

            // TODO: text entry

            comptime assert(@hasDecl(UserGame, "onUserUpdate"));
            if (!self.game.onUserUpdate(alloc, &self.state, fElapsed))
                self.state.active.store(false, .Monotonic);

            self.state.old_key_state = self.state.key_state;
            self.state.old_mouse_state = self.state.mouse_state;

            // TODO: console show thing

            try Impl.updateViewport(self.state.view_pos, self.state.view_size);
            Impl.clearBuffer(Pixel.Black, true);

            self.state.layers.items[0].show = true;
            self.state.layers.items[0].update = true;

            self.impl.prepareDrawing();

            for (self.state.layers.items) |*layer| if (layer.show) {
                Impl.applyTexture(layer.draw_target.inner.id) catch unreachable;
                if (layer.update) {
                    try layer.draw_target.inner.update();
                    layer.update = false;
                }
                try self.impl.drawLayerQuad(layer.offset, layer.scale, layer.tint);
                for (layer.decal_draws.items) |decal| try self.impl.drawDecal(decal);
                layer.decal_draws.clearRetainingCapacity();
            };

            try self.impl.displayFrame();
            self.second_count += fElapsed;
            const every_n_frames = 60;
            if (self.frame_i > every_n_frames) {
                const fps = every_n_frames / self.second_count;
                const format = "Pixel Game Engine - {s} - FPS: {}";
                var buf = [_]u8{0} ** (format.len + 257);
                var title = std.fmt.bufPrintZ(
                    buf[0 .. buf.len - 1],
                    format,
                    .{ self.state.app_name, if (fps > 9999) 9999 else @floatToInt(u32, fps) },
                ) catch buf[0 .. buf.len - 1 :0];
                try self.impl.setWindowTitle(title);
                self.frame_i = 0;
                self.second_count = 0;
            }
            self.frame_i += 1;
        }
        pub fn constructFontSheet(alloc: Allocator) !OwnedDecal {
            // would be nice not to have a blob in the source code

            const data = "?Q`0001oOch0o01o@F40o0<AGD4090LAGD<090@A7ch0?00O7Q`0600>00000000" ++
                "O000000nOT0063Qo4d8>?7a14Gno94AA4gno94AaOT0>o3`oO400o7QN00000400" ++
                "Of80001oOg<7O7moBGT7O7lABET024@aBEd714AiOdl717a_=TH013Q>00000000" ++
                "720D000V?V5oB3Q_HdUoE7a9@DdDE4A9@DmoE4A;Hg]oM4Aj8S4D84@`00000000" ++
                "OaPT1000Oa`^13P1@AI[?g`1@A=[OdAoHgljA4Ao?WlBA7l1710007l100000000" ++
                "ObM6000oOfMV?3QoBDD`O7a0BDDH@5A0BDD<@5A0BGeVO5ao@CQR?5Po00000000" ++
                "Oc``000?Ogij70PO2D]??0Ph2DUM@7i`2DTg@7lh2GUj?0TO0C1870T?00000000" ++
                "70<4001o?P<7?1QoHg43O;`h@GT0@:@LB@d0>:@hN@L0@?aoN@<0O7ao0000?000" ++
                "OcH0001SOglLA7mg24TnK7ln24US>0PL24U140PnOgl0>7QgOcH0K71S0000A000" ++
                "00H00000@Dm1S007@DUSg00?OdTnH7YhOfTL<7Yh@Cl0700?@Ah0300700000000" ++
                "<008001QL00ZA41a@6HnI<1i@FHLM81M@@0LG81?O`0nC?Y7?`0ZA7Y300080000" ++
                "O`082000Oh0827mo6>Hn?Wmo?6HnMb11MP08@C11H`08@FP0@@0004@000000000" ++
                "00P00001Oab00003OcKP0006@6=PMgl<@440MglH@000000`@000001P00000000" ++
                "Ob@8@@00Ob@8@Ga13R@8Mga172@8?PAo3R@827QoOb@820@0O`0007`0000007P0" ++
                "O`000P08Od400g`<3V=P0G`673IP0`@3>1`00P@6O`P00g`<O`000GP800000000" ++
                "?P9PL020O`<`N3R0@E4HC7b0@ET<ATB0@@l6C4B0O`H3N7b0?P01L3R000000020";

            var sprite = try alloc.create(Sprite);
            errdefer alloc.destroy(sprite);
            sprite.* = try Sprite.initSize(alloc, 128, 48);
            errdefer sprite.deinit(alloc);

            var did_half = false; // 24 + 24 = 48
            var y: u32 = 0;
            var i: usize = 0;
            while (i < data.len) : (i += 4) {
                const P = packed struct(u24) { a: u6, b: u6, c: u6, d: u6 };
                const part = std.StaticBitSet(24){ .mask = @bitCast(u24, P{
                    .a = @intCast(u6, data[i + 0] - 48),
                    .b = @intCast(u6, data[i + 1] - 48),
                    .c = @intCast(u6, data[i + 2] - 48),
                    .d = @intCast(u6, data[i + 3] - 48),
                }) };
                var j: u32 = 0;
                while (j < 24) : (j += 1) {
                    const k: u8 = if (part.isSet(j)) 255 else 0;
                    // yeah i did a fancy thing here
                    const x = j + if (did_half) @as(u32, 24) else 0;
                    sprite.setPixel(x, y, .{ .c = .{ .r = k, .g = k, .b = k, .a = k } });
                }
                if (did_half) y += 1;
                did_half = !did_half;
            }

            // TODO: spacing

            // TODO: keyboard to character mapping

            return OwnedDecal{ .inner = try Decal.init(sprite, false, true) };
        }
        pub fn deinit(self: *Self, alloc: Allocator) void {
            self.impl.deinit(alloc);
            self.state.deinit(alloc);
            self.* = undefined;
        }
    };
}

pub const PixelMode = enum {
    Normal,
    Mask,
    Alpha,
};
pub const Pixel = extern union {
    n: u32,
    c: extern struct { r: u8, g: u8, b: u8, a: u8 = 255 },

    pub const White = Pixel{ .c = .{ .r = 255, .g = 255, .b = 255 } };
    pub const Black = Pixel{ .c = .{ .r = 0, .g = 0, .b = 0 } };

    pub const Default = Pixel{ .c = .{ .r = 0, .g = 0, .b = 0, .a = 255 } };
};

pub const Sprite = struct {
    pub const SampleMode = enum { Normal, Periodic, Clamp };

    width: u32,
    height: u32,
    data: []Pixel,
    sample_mode: SampleMode = .Normal,

    pub fn initSize(alloc: Allocator, width: u32, height: u32) !Sprite {
        var data = try alloc.alloc(Pixel, width * height);
        for (data) |*b| b.* = Pixel.Default;
        return Sprite{
            .width = width,
            .height = height,
            .data = data,
        };
    }
    pub fn deinit(self: *Sprite, alloc: Allocator) void {
        alloc.free(self.data);
        self.* = undefined;
    }

    pub fn setPixel(self: *Sprite, x: u32, y: u32, pixel: Pixel) void {
        if (x >= self.width or y >= self.height) return;
        self.data[y * self.width + x] = pixel;
    }
    pub fn getPixel(self: *Sprite, x: u32, y: u32) Pixel {
        assert(x < self.width and y < self.height);
        return self.data[y * self.width + x];
    }
};

pub const Decal = struct {
    sprite: *Sprite, // not owned by Decal (except when under OwnedDecal)
    id: u32,
    uv_scale: VF2D = .{ .x = 1.0, .y = 1.0 },

    pub fn init(sprite: *Sprite, filter: bool, clamp: bool) !Decal {
        var self = Decal{
            .sprite = sprite,
            .id = try Impl.createTexture(sprite.width, sprite.height, filter, clamp),
        };
        errdefer Impl.deleteTexture(self.id);
        try self.update();
        return self;
    }
    pub fn update(self: *Decal) !void {
        self.uv_scale = .{
            .x = 1.0 / @intToFloat(f32, self.sprite.width),
            .y = 1.0 / @intToFloat(f32, self.sprite.height),
        };
        try Impl.applyTexture(self.id);
        try Impl.updateTexture(self.id, self.sprite);
    }
    pub fn deinit(self: *Decal) void {
        Impl.deleteTexture(self.id);
        self.* = undefined;
    }
};

pub const OwnedDecal = struct {
    inner: Decal,

    pub fn initSize(alloc: Allocator, w: u32, h: u32) !OwnedDecal {
        var sprite = try alloc.create(Sprite);
        errdefer alloc.destroy(sprite);
        sprite.* = try Sprite.initSize(alloc, w, h);
        errdefer sprite.deinit(alloc);
        return OwnedDecal{ .inner = try Decal.init(sprite, false, true) };
    }
    pub fn deinit(self: *OwnedDecal, alloc: Allocator) void {
        self.inner.sprite.deinit(alloc);
        alloc.destroy(self.inner.sprite);
        self.inner.deinit();
    }
};

pub const Layer = struct {
    offset: VF2D = .{ .x = 0.0, .y = 0.0 },
    scale: VF2D = .{ .x = 1.0, .y = 1.0 },
    show: bool = false,
    update: bool = false,
    draw_target: OwnedDecal,
    decal_draws: std.ArrayListUnmanaged(DecalInstance) = .{},
    tint: Pixel = Pixel.White,

    pub fn deinit(self: *Layer, alloc: Allocator) void {
        self.draw_target.deinit(alloc);
        self.decal_draws.deinit(alloc);
        self.* = undefined;
    }
};

pub const LocVertex = extern struct {
    // [0] = x, [1] = y, [2] = w(?)
    pos: [3]f32,
    // uv
    tex: VF2D,
    // tint
    col: Pixel,
};
pub const MaxVerts = 128; // `OLC_MAX_VERTS`

pub const DecalMode = enum {
    Normal,
    Additive,
    Multiplicative,
    Stencil,
    Illuminate,
    Wireframe,
    Model3D,
};
pub const DecalStructure = enum {
    Line,
    Fan,
    Strip,
    List,
};
pub const DecalInstance = struct {
    decal: *Decal,
    mode: DecalMode = .Normal,
    structure: DecalStructure = .Fan,
    vertices: []const LocVertex,
};

pub const LinuxImpl = struct {
    const x = @import("x11.zig");

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
        ) !XState {
            if (!x.initThreads())
                std.log.warn("X says it doesn't support multithreading", .{});
            x.initErrorHandler();

            const display = x.Display.open(null) orelse return error.DisplayOpenFailure;
            errdefer display.close();
            if (!x.initGlxErrors(display))
                std.log.warn("no GLX errors", .{});
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
                x.Window.WindowAttributes{ .colormap = color_map.inner, .event_mask = .{
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

            try window.map(display);
            try window.storeName(display, "zig pge");

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

                try window.map(display);
                try display.sendEvent(
                    window_root,
                    false,
                    .{ .substructure_redirect = true, .substructure_notify = true },
                    &xev,
                );
                try display.flush();

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

    fns: LoadFns.Inner,

    n_fs: x.c.GLuint,
    n_vs: x.c.GLuint,
    n_quad: x.c.GLuint,
    vb_quad: x.c.GLuint,
    va_quad: x.c.GLuint,
    blank_quad: OwnedDecal,

    decal_mode: DecalMode = .Normal,

    const Self = @This();

    pub fn init(alloc: Allocator, state: *EngineState) !Self {
        var x_state = try XState.init(.{ .x = 30, .y = 30 }, &state.window_size, state.full_screen);
        errdefer x_state.deinit();

        state.updateViewport();

        const ctx = try x.Context.create(x_state.display, x_state.visual_info, x.Context{ .inner = null }, true);
        errdefer ctx.destroy(x_state.display);
        try x_state.display.makeCurrent(x_state.window, ctx);
        errdefer x_state.display.makeCurrent(x.Window{ .inner = 0 }, x.Context{ .inner = null }) catch unreachable;

        const gwa = try x_state.window.getAttributes(x_state.display);
        x.c.glViewport(0, 0, gwa.width, gwa.height);

        const fns = LoadFns.load();

        if (fns.glXSwapIntervalEXT) |glXSwapIntervalEXT| {
            if (!state.vsync) glXSwapIntervalEXT(x_state.display.inner, x_state.window.inner, 0);
        } else if (!state.vsync) {
            std.log.warn("cannot disable vsync (no glXSwapIntervalEXT)", .{});
        }

        // required functions
        // TODO make required functions not need optional unwrap syntax to use
        var missing_functions = false;
        inline for (.{
            "glCreateShader",
            "glDeleteShader",
            "glShaderSource",
            "glCompileShader",
            "glCreateProgram",
            "glDeleteProgram",
            "glAttachShader",
            "glLinkProgram",
            "glGetShaderiv",
            "glGenBuffers",
            "glDeleteBuffers",
            "glGenVertexArrays",
            "glBindVertexArray",
            "glBindBuffer",
            "glBufferData",
            "glVertexAttribPointer",
            "glDeleteVertexArrays",
            "glEnableVertexAttribArray",
        }) |field_name| {
            if (@field(fns, field_name) == null) {
                std.log.err("Missing OpenGL function \"{s}\"", .{field_name});
                missing_functions = true;
            }
        }
        if (missing_functions) {
            return error.MissingGlFunction;
        }

        // why did pge hardcode the number here to specify fragment shader?
        const nFS = fns.glCreateShader.?(x.c.GL_FRAGMENT_SHADER);
        if (nFS == 0) return x.getGlError().?;
        errdefer fns.glDeleteShader.?(nFS);
        // note: following shaders not made for arm. see relevant olcPixelGameEngine source
        var strFS =
            \\#version 330 core
            \\out vec4 pixel;
            \\in vec2 oTex;
            \\in vec4 oCol;
            \\uniform sampler2D sprTex;
            \\void main() {
            \\  pixel = texture(sprTex, oTex) * oCol;
            \\}
        ;
        fns.glShaderSource.?(nFS, 1, @ptrCast([*][:0]const u8, &strFS), null);
        if (x.getGlError()) |e| return e;
        fns.glCompileShader.?(nFS);
        if (x.getGlError()) |e| return e;

        const nVS = fns.glCreateShader.?(x.c.GL_VERTEX_SHADER);
        if (nVS == 0) return x.getGlError().?;
        errdefer fns.glDeleteShader.?(nVS);
        var strVS =
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
        fns.glShaderSource.?(nVS, 1, @ptrCast([*][:0]const u8, &strVS), null);
        if (x.getGlError()) |e| return e;
        fns.glCompileShader.?(nVS);
        if (x.getGlError()) |e| return e;

        const quad = fns.glCreateProgram.?();
        if (quad == 0) return x.getGlError().?;
        errdefer fns.glDeleteProgram.?(quad);
        fns.glAttachShader.?(quad, nFS);
        if (x.getGlError()) |e| return e;
        fns.glAttachShader.?(quad, nVS);
        if (x.getGlError()) |e| return e;
        fns.glLinkProgram.?(quad);
        if (x.getGlError()) |e| return e;

        var vb_quad: x.c.GLuint = undefined;
        fns.glGenBuffers.?(1, @as(*[1]x.c.GLuint, &vb_quad));
        if (x.getGlError()) |e| return e;
        errdefer fns.glDeleteBuffers.?(1, @as(*[1]x.c.GLuint, &vb_quad));
        var va_quad: x.c.GLuint = undefined;
        fns.glGenVertexArrays.?(1, @as(*[1]x.c.GLuint, &va_quad));
        if (x.getGlError()) |e| return e;
        errdefer fns.glDeleteVertexArrays.?(1, @as(*[1]x.c.GLuint, &va_quad));
        fns.glBindVertexArray.?(va_quad);
        if (x.getGlError()) |e| return e;
        fns.glBindBuffer.?(x.c.GL_ARRAY_BUFFER, vb_quad);
        if (x.getGlError()) |e| return e;

        // what is purpose of this?
        var verts: [MaxVerts]LocVertex = undefined;
        fns.glBufferData.?(x.c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(verts)), &verts, x.c.GL_STREAM_DRAW);
        if (x.getGlError()) |e| return e;
        fns.glVertexAttribPointer.?(
            0,
            3,
            x.c.GL_FLOAT,
            x.c.GL_FALSE,
            @sizeOf(LocVertex),
            @offsetOf(LocVertex, "pos"),
        );
        if (x.getGlError()) |e| return e;
        fns.glEnableVertexAttribArray.?(0);
        if (x.getGlError()) |e| return e;
        fns.glVertexAttribPointer.?(
            1,
            2,
            x.c.GL_FLOAT,
            x.c.GL_FALSE,
            @sizeOf(LocVertex),
            @offsetOf(LocVertex, "tex"),
        );
        if (x.getGlError()) |e| return e;
        fns.glEnableVertexAttribArray.?(1);
        if (x.getGlError()) |e| return e;
        fns.glVertexAttribPointer.?(
            2,
            4,
            x.c.GL_UNSIGNED_BYTE,
            x.c.GL_TRUE,
            @sizeOf(LocVertex),
            @offsetOf(LocVertex, "col"),
        );
        if (x.getGlError()) |e| return e;
        fns.glEnableVertexAttribArray.?(2);
        if (x.getGlError()) |e| return e;
        fns.glBindBuffer.?(x.c.GL_ARRAY_BUFFER, 0);
        if (x.getGlError()) |e| return e;
        fns.glBindVertexArray.?(0);
        if (x.getGlError()) |e| return e;

        try updateViewport(state.view_pos, state.view_size);

        var blank_sprite: *Sprite = undefined;
        var blank_quad: OwnedDecal = undefined;
        {
            // TODO: could we do OwnedDecal.initSize here?
            blank_sprite = try alloc.create(Sprite);
            errdefer alloc.destroy(blank_sprite);
            blank_sprite.* = try Sprite.initSize(alloc, 1, 1);
            errdefer blank_sprite.deinit(alloc);
            blank_sprite.data[0] = Pixel.White;

            blank_quad = OwnedDecal{
                .inner = try Decal.init(blank_sprite, false, true),
            };
        }
        errdefer blank_quad.deinit(alloc);
        try blank_quad.inner.update(); // may be unnecessary to call this here

        return Self{
            .x_state = x_state,
            .fns = fns,
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
        self.x_state.display.makeCurrent(x.Window{ .inner = 0 }, x.Context{ .inner = null }) catch unreachable;
        self.device_context.destroy(self.x_state.display);
        self.fns.glDeleteVertexArrays.?(1, @ptrCast([*]const c_uint, &self.va_quad));
        self.fns.glDeleteBuffers.?(1, @ptrCast([*]const c_uint, &self.vb_quad));
        self.fns.glDeleteProgram.?(self.n_quad);
        self.fns.glDeleteShader.?(self.n_vs);
        self.fns.glDeleteShader.?(self.n_fs);
        self.blank_quad.deinit(alloc);
        self.x_state.deinit();
        self.* = undefined;
    }

    pub const LoadFns = x.LoadFns(.{
        .{ "glXSwapIntervalEXT", fn (*x.c.Display, x.c.GLXDrawable, c_int) callconv(.C) void },
        .{ "glCreateShader", fn (x.c.GLenum) callconv(.C) x.c.GLuint },
        .{ "glCompileShader", fn (x.c.GLuint) callconv(.C) void },
        .{ "glShaderSource", fn (x.c.GLuint, x.c.GLsizei, [*][:0]const u8, ?*x.c.GLint) callconv(.C) void },
        .{ "glDeleteShader", fn (x.c.GLuint) callconv(.C) void },
        .{ "glCreateProgram", fn () callconv(.C) x.c.GLuint },
        .{ "glDeleteProgram", fn (x.c.GLuint) callconv(.C) void },
        .{ "glLinkProgram", fn (x.c.GLuint) callconv(.C) void },
        .{ "glAttachShader", fn (x.c.GLuint, x.c.GLuint) callconv(.C) void },
        .{ "glBindBuffer", fn (x.c.GLenum, x.c.GLuint) callconv(.C) void },
        .{ "glBufferData", fn (x.c.GLenum, x.c.GLsizeiptr, *const anyopaque, x.c.GLenum) callconv(.C) void },
        .{ "glGenBuffers", fn (x.c.GLsizei, [*]x.c.GLuint) callconv(.C) void },
        .{ "glDeleteBuffers", fn (x.c.GLsizei, [*]const x.c.GLuint) callconv(.C) void },
        .{ "glVertexAttribPointer", fn (x.c.GLuint, x.c.GLint, x.c.GLenum, x.c.GLboolean, x.c.GLsizei, usize) callconv(.C) void },
        .{ "glEnableVertexAttribArray", fn (x.c.GLuint) callconv(.C) void },
        .{ "glUseProgram", fn (x.c.GLuint) callconv(.C) void },
        .{ "glGetShaderInfoLog", fn (x.c.GLuint, [*c]const u8) callconv(.C) void },
        .{ "glBindVertexArray", fn (x.c.GLuint) callconv(.C) void },
        .{ "glGenVertexArrays", fn (x.c.GLsizei, [*]x.c.GLuint) callconv(.C) void },
        .{ "glDeleteVertexArrays", fn (x.c.GLsizei, [*]const x.c.GLuint) callconv(.C) void },
        .{ "glGetShaderiv", fn (x.c.GLuint, x.c.GLenum, *x.c.GLint) callconv(.C) void },
    });

    pub fn updateViewport(pos: V2D, size: V2D) !void {
        x.c.glViewport(pos.x, pos.y, size.x, size.y);
        if (x.getGlError()) |e| return e;
    }

    pub fn createTexture(width: u32, height: u32, filter: bool, clamp: bool) !u32 {
        _ = width;
        _ = height;
        var id: u32 = undefined;
        x.c.glGenTextures(1, &id);
        if (x.getGlError()) |e| return e;
        errdefer x.c.glDeleteTextures(1, &id);
        x.c.glBindTexture(x.c.GL_TEXTURE_2D, id);
        if (x.getGlError()) |e| return e;

        // hopefully order doesnt matter. noted that the pge code isnt in same order
        x.c.glTexParameteri(
            x.c.GL_TEXTURE_2D,
            x.c.GL_TEXTURE_MIN_FILTER,
            if (filter) x.c.GL_LINEAR else x.c.GL_NEAREST,
        );
        if (x.getGlError()) |e| return e;
        x.c.glTexParameteri(
            x.c.GL_TEXTURE_2D,
            x.c.GL_TEXTURE_MAG_FILTER,
            if (filter) x.c.GL_LINEAR else x.c.GL_NEAREST,
        );
        if (x.getGlError()) |e| return e;

        x.c.glTexParameteri(
            x.c.GL_TEXTURE_2D,
            x.c.GL_TEXTURE_WRAP_S,
            if (clamp) x.c.GL_CLAMP else x.c.GL_REPEAT,
        );
        if (x.getGlError()) |e| return e;
        x.c.glTexParameteri(
            x.c.GL_TEXTURE_2D,
            x.c.GL_TEXTURE_WRAP_T,
            if (clamp) x.c.GL_CLAMP else x.c.GL_REPEAT,
        );
        if (x.getGlError()) |e| return e;

        return id;
    }
    pub fn deleteTexture(id: u32) void {
        var _id = id;
        x.c.glDeleteTextures(1, &_id);
    }
    pub fn applyTexture(id: u32) !void {
        x.c.glBindTexture(x.c.GL_TEXTURE_2D, id);
        if (x.getGlError()) |e| return e;
    }
    pub fn updateTexture(id: u32, sprite: *Sprite) !void {
        _ = id;
        x.c.glTexImage2D(
            x.c.GL_TEXTURE_2D,
            0,
            x.c.GL_RGBA,
            @intCast(x.c.GLsizei, sprite.width),
            @intCast(x.c.GLsizei, sprite.height),
            0,
            x.c.GL_RGBA,
            x.c.GL_UNSIGNED_BYTE,
            sprite.data.ptr,
        );
        if (x.getGlError()) |e| return e;
    }
    pub fn readTexture(id: u32, sprite: *Sprite) !void {
        _ = id;
        x.c.glReadPixels(0, 0, sprite.width, sprite.height, x.c.GL_RGBA, x.c.GL_UNSIGNED_BYTE, sprite.data);
        if (x.getGlError()) |e| return e;
    }

    pub fn clearBuffer(p: Pixel, depth: bool) void {
        x.c.glClearColor(
            @intToFloat(f32, p.c.r) / 255.0,
            @intToFloat(f32, p.c.g) / 255.0,
            @intToFloat(f32, p.c.b) / 255.0,
            @intToFloat(f32, p.c.a) / 255.0,
        );
        x.c.glClear(x.c.GL_COLOR_BUFFER_BIT);
        if (depth) x.c.glClear(x.c.GL_DEPTH_BUFFER_BIT);
    }

    pub fn mapKey(key: x.c.KeySym) Key {
        var new_key = switch (key) {
            x.c.XK_Return, x.c.XK_Linefeed => x.c.XK_KP_Enter,
            x.c.XK_Shift_R => x.c.XK_Shift_L,
            x.c.XK_Control_R => x.c.XK_Control_L,
            else => key,
        };
        // `Key` is non-exhaustive, so theoretically this is just an int cast
        return @intToEnum(Key, new_key);
    }
    pub fn handleSystemEvent(self: *Self, pge: *EngineState) !void {
        while (true) {
            const count = self.x_state.display.pending();
            if (count == 0) break;
            var i: usize = 0;
            while (i < count) : (i += 1) {
                var xev = self.x_state.display.nextEvent();
                switch (xev.type) {
                    x.c.Expose => {
                        const attr = try self.x_state.window.getAttributes(self.x_state.display); // should be no error
                        pge.updateWindowSize(.{ .x = attr.width, .y = attr.height });
                    },
                    x.c.ConfigureNotify => {
                        pge.updateWindowSize(.{
                            .x = xev.xconfigure.width,
                            .y = xev.xconfigure.height,
                        });
                    },
                    x.c.KeyPress => {
                        pge.updateKeyState(mapKey(x.c.XLookupKeysym(&xev.xkey, 0)), true);
                    },
                    x.c.KeyRelease => {
                        pge.updateKeyState(mapKey(x.c.XLookupKeysym(&xev.xkey, 0)), false);
                    },
                    x.c.ButtonPress => switch (xev.xbutton.button) {
                        x.c.Button1 => pge.mouse_state.insert(.Left),
                        x.c.Button2 => pge.mouse_state.insert(.Middle),
                        x.c.Button3 => pge.mouse_state.insert(.Right),
                        x.c.Button4 => pge.mouse_wheel_delta_cache += MouseScrollAmount,
                        x.c.Button5 => pge.mouse_wheel_delta_cache -= MouseScrollAmount,
                        else => {},
                    },
                    x.c.ButtonRelease => switch (xev.xbutton.button) {
                        x.c.Button1 => pge.mouse_state.remove(.Left),
                        x.c.Button2 => pge.mouse_state.remove(.Middle),
                        x.c.Button3 => pge.mouse_state.remove(.Right),
                        else => {},
                    },
                    x.c.MotionNotify => {
                        pge.mouse_pos_cache = .{ .x = xev.xmotion.x, .y = xev.xmotion.y };
                    },
                    x.c.FocusIn => pge.has_input_focus = true,
                    x.c.FocusOut => pge.has_input_focus = false,
                    x.c.ClientMessage => pge.active.store(false, .Monotonic),
                    else => {},
                }
            }
        }
    }

    pub fn setDecalMode(self: *Self, mode: DecalMode) void {
        defer self.decal_mode = mode;
        x.c.glBlendFunc(
            switch (mode) {
                .Normal, .Additive, .Wireframe => x.c.GL_SRC_ALPHA,
                .Multiplicative => x.c.GL_DST_COLOR,
                .Stencil => x.c.GL_ZERO,
                .Illuminate => x.c.GL_ONE_MINUS_SRC_ALPHA,
                else => return,
            },
            switch (mode) {
                .Normal, .Multiplicative, .Wireframe => x.c.GL_ONE_MINUS_SRC_ALPHA,
                .Additive => x.c.GL_ONE,
                .Stencil, .Illuminate => x.c.GL_SRC_ALPHA,
                else => return,
            },
        );
    }

    pub fn prepareDrawing(self: *Self) void {
        x.c.glEnable(x.c.GL_BLEND);
        self.setDecalMode(.Normal);
        self.fns.glUseProgram.?(self.n_quad);
        self.fns.glBindVertexArray.?(self.va_quad);
    }

    pub fn drawLayerQuad(self: *Self, offset: VF2D, scale: VF2D, tint: Pixel) !void {
        self.fns.glBindBuffer.?(x.c.GL_ARRAY_BUFFER, self.vb_quad);
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
        self.fns.glBufferData.?(x.c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(verts)), &verts, x.c.GL_STREAM_DRAW);
        if (x.getGlError()) |e| return e;
        x.c.glDrawArrays(x.c.GL_TRIANGLE_STRIP, 0, 4);
        //if (x.getGlError()) |e| return e;
    }
    pub fn drawDecal(self: *Self, decal: DecalInstance) !void {
        self.setDecalMode(decal.mode);
        x.c.glBindTexture(x.c.GL_TEXTURE_2D, decal.decal.id);
        self.fns.glBindBuffer.?(x.c.GL_ARRAY_BUFFER, self.vb_quad);
        self.fns.glBufferData.?(
            x.c.GL_ARRAY_BUFFER,
            @intCast(x.c.GLsizeiptr, decal.vertices.len),
            decal.vertices.ptr,
            x.c.GL_STREAM_DRAW,
        );
        x.c.glDrawArrays(if (self.decal_mode == .Wireframe)
            x.c.GL_LINE_LOOP
        else switch (decal.structure) {
            .Fan => x.c.GL_TRIANGLE_FAN,
            .Strip => x.c.GL_TRIANGLE_STRIP,
            .List => x.c.GL_TRIANGLES,
            .Line => @panic("i guess youre not supposed to use this?"),
        }, 0, @intCast(x.c.GLsizei, decal.vertices.len));
    }

    pub fn displayFrame(self: *Self) !void {
        try self.x_state.display.swapBuffers(self.x_state.window);
    }

    pub fn setWindowTitle(self: *Self, title: [:0]const u8) !void {
        try self.x_state.display.storeName(self.x_state.window, title);
    }

    pub const Key = enum(x.c.KeySym) {
        const c = x.c;

        A = c.XK_a,
        B = c.XK_b,
        C = c.XK_c,
        D = c.XK_d,
        E = c.XK_e,
        F = c.XK_f,
        G = c.XK_g,
        H = c.XK_h,
        I = c.XK_i,
        J = c.XK_j,
        K = c.XK_k,
        L = c.XK_l,
        M = c.XK_m,
        N = c.XK_n,
        O = c.XK_o,
        P = c.XK_p,
        Q = c.XK_q,
        R = c.XK_r,
        S = c.XK_s,
        T = c.XK_t,
        U = c.XK_u,
        V = c.XK_v,
        W = c.XK_w,
        X = c.XK_x,
        Y = c.XK_y,
        Z = c.XK_z,

        F1 = c.XK_F1,
        F2 = c.XK_F2,
        F3 = c.XK_F3,
        F4 = c.XK_F4,
        F5 = c.XK_F5,
        F6 = c.XK_F6,
        F7 = c.XK_F7,
        F8 = c.XK_F8,
        F9 = c.XK_F9,
        F10 = c.XK_F10,
        F11 = c.XK_F11,
        F12 = c.XK_F12,

        Down = c.XK_Down,
        Left = c.XK_Left,
        Right = c.XK_Right,
        Up = c.XK_Up,

        Enter = c.XK_KP_Enter,
        Back = c.XK_BackSpace,
        Escape = c.XK_Escape,
        Pause = c.XK_Pause,
        Scroll = c.XK_Scroll_Lock,
        Tab = c.XK_Tab,
        Del = c.XK_Delete,
        Home = c.XK_Home,
        End = c.XK_End,
        PgUp = c.XK_Page_Up,
        PgDn = c.XK_Page_Down,
        Ins = c.XK_Insert,
        Shift = c.XK_Shift_L,
        Ctrl = c.XK_Control_L,
        Space = c.XK_space,
        Period = c.XK_period,
        CapsLock = c.XK_Caps_Lock,

        K0 = c.XK_0,
        K1 = c.XK_1,
        K2 = c.XK_2,
        K3 = c.XK_3,
        K4 = c.XK_4,
        K5 = c.XK_5,
        K6 = c.XK_6,
        K7 = c.XK_7,
        K8 = c.XK_8,
        K9 = c.XK_9,

        NP0 = c.XK_KP_0,
        NP1 = c.XK_KP_1,
        NP2 = c.XK_KP_2,
        NP3 = c.XK_KP_3,
        NP4 = c.XK_KP_4,
        NP5 = c.XK_KP_5,
        NP6 = c.XK_KP_6,
        NP7 = c.XK_KP_7,
        NP8 = c.XK_KP_8,
        NP9 = c.XK_KP_9,

        NpMul = c.XK_KP_Multiply,
        NpAdd = c.XK_KP_Add,
        NpDiv = c.XK_KP_Divide,
        NpSub = c.XK_KP_Subtract,
        NpDecimal = c.XK_KP_Decimal,

        OEM_1 = c.XK_semicolon,
        OEM_2 = c.XK_slash,
        OEM_3 = c.XK_asciitilde,
        OEM_4 = c.XK_bracketleft,
        OEM_5 = c.XK_backslash,
        OEM_6 = c.XK_bracketright,
        OEM_7 = c.XK_apostrophe,
        OEM_8 = c.XK_numbersign,
        EQUALS = c.XK_equal,
        COMMA = c.XK_comma,
        MINUS = c.XK_minus,
        _,
    };
};
