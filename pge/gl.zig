const std = @import("std");
const assert = std.debug.assert;

const x11 = @import("x11.zig");
const c = x11.c;

pub const GlError = error{
    GlInvalidEnum,
    GlInvalidValue,
    GlInvalidOperation,
    GlStackOverflow,
    GlStackUnderflow,
    GlOutOfMemory,
    GlInvalidFramebufferOperation,
};
pub fn getGlError() ?GlError {
    const code = c.glGetError();
    return switch (code) {
        c.GL_NO_ERROR => null,
        c.GL_INVALID_ENUM => error.GlInvalidEnum,
        c.GL_INVALID_VALUE => error.GlInvalidValue,
        c.GL_INVALID_OPERATION => error.GlInvalidOperation,
        c.GL_STACK_OVERFLOW => error.GlStackOverflow,
        c.GL_STACK_UNDERFLOW => error.GlStackUnderflow,
        c.GL_OUT_OF_MEMORY => error.GlOutOfMemory,
        c.GL_INVALID_FRAMEBUFFER_OPERATION => error.GlInvalidFramebufferOperation,
        else => std.debug.panic("unknown GL error received {}", .{code}),
    };
}

pub fn viewport(x: i32, y: i32, width: u32, height: u32) void {
    c.glViewport(
        @intCast(c.GLint, x),
        @intCast(c.GLint, y),
        @intCast(c.GLsizei, width),
        @intCast(c.GLsizei, height),
    );
    assert(getGlError() == null);
}

pub const DataKind = enum(c.GLenum) {
    Byte = c.GL_BYTE,
    UnsignedByte = c.GL_UNSIGNED_BYTE,
    Short = c.GL_SHORT,
    UnsignedShort = c.GL_UNSIGNED_SHORT,
    Int = c.GL_INT,
    UnsignedInt = c.GL_UNSIGNED_INT,
    HalfFloat = c.GL_HALF_FLOAT,
    Float = c.GL_FLOAT,
    Double = c.GL_DOUBLE,
    Fixed = c.GL_FIXED,
    Int2101010Rev = c.GL_INT_2_10_10_10_REV,
    //UnsignedInt2101010Rev = c.GL_UNSIGNED_INT_2_10_10_10_REV,
    UnsignedInt10f11f11fRev = c.GL_UNSIGNED_INT_10F_11F_11F_REV,
    UnsignedByte332 = c.GL_UNSIGNED_BYTE_3_3_2,
    UnsignedByte233Rev = c.GL_UNSIGNED_BYTE_2_3_3_REV,
    UnsignedShort565 = c.GL_UNSIGNED_SHORT_5_6_5,
    UnsignedShort565Rev = c.GL_UNSIGNED_SHORT_5_6_5_REV,
    UnsignedShort4444 = c.GL_UNSIGNED_SHORT_4_4_4_4,
    UnsignedShort4444Rev = c.GL_UNSIGNED_SHORT_4_4_4_4_REV,
    UnsignedShort5551 = c.GL_UNSIGNED_SHORT_5_5_5_1,
    UnsignedShort1555Rev = c.GL_UNSIGNED_SHORT_1_5_5_5_REV,
    UnsignedInt8888 = c.GL_UNSIGNED_INT_8_8_8_8,
    UnsignedInt8888Rev = c.GL_UNSIGNED_INT_8_8_8_8_REV,
    UnsignedInt1010102 = c.GL_UNSIGNED_INT_10_10_10_2,
    UnsignedInt2101010Rev = c.GL_UNSIGNED_INT_2_10_10_10_REV,
    UnsignedInt248 = c.GL_UNSIGNED_INT_24_8,
    UnsignedInt5999Rev = c.GL_UNSIGNED_INT_5_9_9_9_REV,
    Float32UnsignedInt248Rev = c.GL_FLOAT_32_UNSIGNED_INT_24_8_REV,
};

pub fn getProcAddress(comptime T: type, name: [:0]const u8) ?*const T {
    return @ptrCast(?*const T, c.glXGetProcAddress(name.ptr));
}

pub fn Extensions(comptime pairs: anytype) type {
    comptime var fields: [pairs.len]std.builtin.Type.StructField = undefined;
    comptime var i = 0;
    inline for (fields) |*field| {
        const pair = pairs[i];
        const is_optional = pair.len < 3 or !pair[2];
        const T = if (is_optional) ?*const pair[1] else *const pair[1];
        field.* = .{
            .name = pair[0],
            .type = T,
            .default_value = if (is_optional) @ptrCast(?*const anyopaque, &@as(T, null)) else null,
            .is_comptime = false,
            .alignment = @alignOf(T),
        };
        i += 1;
    }
    const InnerType = @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
    return struct {
        pub const Inner = InnerType;
        var fns: Inner = undefined; // make sure you call load...
        pub fn load() !void {
            var missing_functions = false;
            inline for (pairs) |pair| {
                const name = pair[0];
                const T = pair[1];
                const address = getProcAddress(T, name);
                const is_optional = @typeInfo(@TypeOf(@field(fns, name))) == .Optional;
                if (!is_optional) {
                    if (address == null) {
                        std.log.err("Missing GL extension function \"{s}\"", .{name});
                        missing_functions = true;
                    } else {
                        @field(fns, name) = address.?;
                    }
                } else {
                    if (address == null)
                        std.log.warn("Missing optional GL extension function \"{s}\"", .{name});
                    @field(fns, name) = address;
                }
            }
            if (missing_functions) return error.MissingGlFunction;
        }

        pub fn has(comptime name: []const u8) bool {
            if (@hasField(Inner, name)) {
                if (@typeInfo(@TypeOf(@field(fns, name))) == .Optional)
                    return @field(fns, name) != null
                else
                    return true;
            } else {
                return false;
            }
        }

        fn u(v: anytype) if (@typeInfo(@TypeOf(v)) == .Optional) @typeInfo(@TypeOf(v)).Optional.child else @TypeOf(v) {
            const info = @typeInfo(@TypeOf(v));
            return if (info == .Optional) v.? else v;
        }

        pub fn swapInterval(display: x11.Display, drawable: c.GLXDrawable, interval: u32) void {
            assert(has("glXSwapIntervalEXT"));
            u(fns.glXSwapIntervalEXT)(display.inner, drawable, @intCast(c_int, interval));
        }

        pub const ShaderKind = enum(c.GLenum) {
            Compute = c.GL_COMPUTE_SHADER,
            Vertex = c.GL_VERTEX_SHADER,
            TessControl = c.GL_TESS_CONTROL_SHADER,
            TessEvaluation = c.GL_TESS_EVALUATION_SHADER,
            Geometry = c.GL_GEOMETRY_SHADER,
            Fragment = c.GL_FRAGMENT_SHADER,
        };
        pub const Shader = struct {
            id: c.GLuint,

            pub fn init(kind: ShaderKind) Shader {
                const id = u(fns.glCreateShader)(@enumToInt(kind));
                assert(getGlError() == null);
                return Shader{ .id = id };
            }
            pub fn deinit(self: *Shader) void {
                u(fns.glDeleteShader)(self.id);
                assert(getGlError() == null);
                self.* = undefined;
            }

            pub fn source(self: Shader, strs: []const [:0]const u8, lens: ?[]c.GLint) void {
                if (lens != null) assert(lens.?.len == strs.len);
                u(fns.glShaderSource)(
                    self.id,
                    @intCast(c.GLsizei, strs.len),
                    strs.ptr,
                    if (lens != null) lens.?.ptr else null,
                );
                assert(getGlError() == null);
            }

            pub fn compile(self: Shader) void {
                u(fns.glCompileShader)(self.id);
                assert(getGlError() == null);
            }

            pub fn getCompileStatus(self: Shader) bool {
                var result: c.GLint = undefined;
                u(fns.glGetShaderiv)(self.id, c.GL_COMPILE_STATUS, &result);
                assert(getGlError() == null);
                return result == c.GL_TRUE;
            }
        };

        pub const Program = struct {
            id: c.GLuint,

            pub const None = Program{ .id = 0 };

            pub fn init() Program {
                // no idea when this errors, just that it apparently can
                // will just assume probably wont error :)
                const id = u(fns.glCreateProgram)();
                assert(getGlError() == null);
                assert(id != 0);
                return Program{ .id = id };
            }
            pub fn deinit(self: *Program) void {
                u(fns.glDeleteProgram)(self.id);
                assert(getGlError() == null);
                self.* = undefined;
            }

            /// will error if you attach same shader twice
            pub fn attachShader(self: Program, shader: Shader) !void {
                u(fns.glAttachShader)(self.id, shader.id);
                if (getGlError()) |e| return e;
            }
            pub fn link(self: Program) !void {
                u(fns.glLinkProgram)(self.id);
                if (getGlError()) |e| return e;
            }
            pub fn use(self: Program) void {
                u(fns.glUseProgram)(self.id);
                assert(getGlError() == null);
            }
        };

        pub const BufferTarget = enum(c.GLenum) {
            Array = c.GL_ARRAY_BUFFER,
            AtomicCounter = c.GL_ATOMIC_COUNTER_BUFFER,
            CopyRead = c.GL_COPY_READ_BUFFER,
            CopyWrite = c.GL_COPY_WRITE_BUFFER,
            DispatchIndirect = c.GL_DISPATCH_INDIRECT_BUFFER,
            DrawIndirect = c.GL_DRAW_INDIRECT_BUFFER,
            ElementArray = c.GL_ELEMENT_ARRAY_BUFFER,
            PixelPack = c.GL_PIXEL_PACK_BUFFER,
            PixelUnpack = c.GL_PIXEL_UNPACK_BUFFER,
            Query = c.GL_QUERY_BUFFER,
            ShaderStorage = c.GL_SHADER_STORAGE_BUFFER,
            Texture = c.GL_TEXTURE_BUFFER,
            TransformFeedback = c.GL_TRANSFORM_FEEDBACK_BUFFER,
            Uniform = c.GL_UNIFORM_BUFFER,
        };
        pub const UsagePattern = enum(c.GLenum) {
            StreamDraw = c.GL_STREAM_DRAW,
            StreamRead = c.GL_STREAM_READ,
            StreamCopy = c.GL_STREAM_COPY,
            StaticDraw = c.GL_STATIC_DRAW,
            StaticRead = c.GL_STATIC_READ,
            StaticCopy = c.GL_STATIC_COPY,
            DynamicDraw = c.GL_DYNAMIC_DRAW,
            DynamicRead = c.GL_DYNAMIC_READ,
            DynamicCopy = c.GL_DYNAMIC_COPY,
        };
        pub const Buffer = struct {
            id: c.GLuint,

            pub const None = Buffer{ .id = 0 };

            pub fn init() Buffer {
                var id: c.GLuint = undefined;
                u(fns.glGenBuffers)(1, @as(*[1]c.GLuint, &id));
                assert(getGlError() == null);
                return Buffer{ .id = id };
            }
            pub fn deinit(self: *Buffer) void {
                u(fns.glDeleteBuffers)(1, @as(*[1]c.GLuint, &self.id));
                assert(getGlError() == null);
                self.* = undefined;
            }

            pub fn bind(self: Buffer, target: BufferTarget) void {
                u(fns.glBindBuffer)(@enumToInt(target), self.id);
                assert(getGlError() == null);
            }

            pub fn data(target: BufferTarget, comptime T: type, d: []const T, usage: UsagePattern) !void {
                u(fns.glBufferData)(
                    @enumToInt(target),
                    @intCast(c.GLsizeiptr, @sizeOf(T) * d.len),
                    d.ptr,
                    @enumToInt(usage),
                );
                if (getGlError()) |e| return e;
            }
        };

        pub const VertexArray = struct {
            id: c.GLuint,

            pub const None = VertexArray{ .id = 0 };

            pub fn init() VertexArray {
                var id: c.GLuint = undefined;
                u(fns.glGenVertexArrays)(1, @as(*[1]c.GLuint, &id));
                assert(getGlError() == null);
                return VertexArray{ .id = id };
            }
            pub fn deinit(self: *VertexArray) void {
                u(fns.glDeleteVertexArrays)(1, @as(*[1]c.GLuint, &self.id));
                assert(getGlError() == null);
                self.* = undefined;
            }

            pub fn bind(self: VertexArray) void {
                u(fns.glBindVertexArray)(self.id);
                assert(getGlError() == null);
            }

            pub const BGRA = @as(u32, c.GL_BGRA);
        };

        pub fn vertexAttribPointer(
            index: u32,
            size: u32,
            kind: DataKind,
            normalized: bool,
            stride: u32,
            offset: usize,
        ) !void {
            assert(switch (kind) {
                .Byte,
                .UnsignedByte,
                .Short,
                .UnsignedShort,
                .Int,
                .UnsignedInt,
                .HalfFloat,
                .Float,
                .Double,
                .Fixed,
                .Int2101010Rev,
                .UnsignedInt2101010Rev,
                .UnsignedInt10f11f11fRev,
                => true,
                else => false,
            });
            assert(index < c.GL_MAX_VERTEX_ATTRIBS);
            assert((size > 0 and size < 5) or size == VertexArray.BGRA);
            assert(switch (kind) {
                .Int2101010Rev, .UnsignedInt2101010Rev => size == VertexArray.BGRA or size == 4,
                .UnsignedInt10f11f11fRev => size == 3,
                else => (size == VertexArray.BGRA and kind == .UnsignedByte) or size != VertexArray.BGRA,
            });
            assert(size != VertexArray.BGRA or normalized);
            u(fns.glVertexAttribPointer)(
                @intCast(c.GLuint, index),
                @intCast(c.GLint, size),
                @enumToInt(kind),
                @boolToInt(normalized),
                @intCast(c.GLsizei, stride),
                offset,
            );
            if (getGlError()) |e| return e;
        }
        pub fn enableVertexAttribArray(index: u32) void {
            assert(index < c.GL_MAX_VERTEX_ATTRIBS);
            u(fns.glEnableVertexAttribArray)(@intCast(c.GLuint, index));
            assert(getGlError() == null);
        }
    };
}

pub const TextureTarget = enum(c.GLenum) {
    // im sorry. `.2D` would be nice but i dont think that is in zig without doing `.@"2D"`
    // TODO: maybe... `.D2`? or just do `.Texture2D`?
    OneD = c.GL_TEXTURE_1D,
    TwoD = c.GL_TEXTURE_2D,
    ThreeD = c.GL_TEXTURE_3D,
    OneDArray = c.GL_TEXTURE_1D_ARRAY,
    TwoDArray = c.GL_TEXTURE_2D_ARRAY,
    Rectangle = c.GL_TEXTURE_RECTANGLE,
    CubeMap = c.GL_TEXTURE_CUBE_MAP,
    CubeMapArray = c.GL_TEXTURE_CUBE_MAP_ARRAY,
    Buffer = c.GL_TEXTURE_BUFFER,
    TwoDMultisample = c.GL_TEXTURE_2D_MULTISAMPLE,
    TwoDMultisampleArray = c.GL_TEXTURE_2D_MULTISAMPLE_ARRAY,
};
pub const Texture = struct {
    id: c.GLuint,

    pub fn init() Texture {
        var id: c.GLuint = undefined;
        c.glGenTextures(1, &id);
        assert(getGlError() == null);
        return Texture{ .id = id };
    }
    pub fn deinit(self: *Texture) void {
        c.glDeleteTextures(1, &self.id);
        assert(getGlError() == null);
        self.* = undefined;
    }

    pub fn bind(self: Texture, target: TextureTarget) void {
        c.glBindTexture(@enumToInt(target), self.id);
        assert(getGlError() == null);
    }
};
pub const TextureParameter = enum(c.GLenum) {
    DepthStencilMode = c.GL_DEPTH_STENCIL_TEXTURE_MODE,
    BaseLevel = c.GL_TEXTURE_BASE_LEVEL,
    CompareFunc = c.GL_TEXTURE_COMPARE_FUNC,
    CompareMode = c.GL_TEXTURE_COMPARE_MODE,
    LodBias = c.GL_TEXTURE_LOD_BIAS,
    MinFilter = c.GL_TEXTURE_MIN_FILTER,
    MagFilter = c.GL_TEXTURE_MAG_FILTER,
    MinLod = c.GL_TEXTURE_MIN_LOD,
    MaxLod = c.GL_TEXTURE_MAX_LOD,
    MaxLevel = c.GL_TEXTURE_MAX_LEVEL,
    SwizzleR = c.GL_TEXTURE_SWIZZLE_R,
    SwizzleG = c.GL_TEXTURE_SWIZZLE_G,
    SwizzleB = c.GL_TEXTURE_SWIZZLE_B,
    SwizzleA = c.GL_TEXTURE_SWIZZLE_A,
    SwizzleRGBA = c.GL_TEXTURE_SWIZZLE_RGBA,
    WrapS = c.GL_TEXTURE_WRAP_S,
    WrapT = c.GL_TEXTURE_WRAP_T,
    WrapR = c.GL_TEXTURE_WRAP_R,
};
pub fn TextureParameterValue(comptime pname: TextureParameter) type {
    return switch (pname) {
        .DepthStencilMode => enum(c.GLint) {
            DepthComponent = c.GL_DEPTH_COMPONENT,
            StencilIndex = c.GL_STENCIL_INDEX,
        },
        .BaseLevel, .MaxLevel => u32,
        .CompareFunc => enum(c.GLint) {
            Never = c.GL_NEVER,
            L = c.GL_LESS,
            E = c.GL_EQUAL,
            LE = c.GL_LEQUAL,
            G = c.GL_GREATER,
            NE = c.GL_NOTEQUAL,
            GE = c.GL_GEQUAL,
            Always = c.GL_ALWAYS,
        },
        .CompareMode => enum(c.GLint) {
            CompareRefToTexture = c.GL_COMPARE_REF_TO_TEXTURE,
            None = c.GL_NONE,
        },
        .LodBias, .MinLod, .MaxLod => f32,
        .MinFilter => enum(c.GLint) {
            Nearest = c.GL_NEAREST,
            Linear = c.GL_LINEAR,
            NearestMipmapNearest = c.GL_NEAREST_MIPMAP_NEAREST,
            LinearMipmapNearest = c.GL_LINEAR_MIPMAP_NEAREST,
            NearestMipmapLinear = c.GL_NEAREST_MIPMAP_LINEAR,
            LinearMipmapLinear = c.GL_LINEAR_MIPMAP_LINEAR,
        },
        .MagFilter => enum(c.GLint) {
            Nearest = c.GL_NEAREST,
            Linear = c.GL_LINEAR,
        },
        .SwizzleR, .SwizzleG, .SwizzleB, .SwizzleA, .SwizzleRGBA => enum(c.GLint) {
            Red = c.GL_RED,
            Green = c.GL_GREEN,
            Blue = c.GL_BLUE,
            Alpha = c.GL_ALPHA,
            Zero = c.GL_ZERO,
            One = c.GL_ONE,
        },
        .WrapS, .WrapT, .WrapR => enum(c.GLint) {
            ClampToEdge = c.GL_CLAMP_TO_EDGE,
            ClampToBorder = c.GL_CLAMP_TO_BORDER,
            MirroredRepeat = c.GL_MIRRORED_REPEAT,
            Repeat = c.GL_REPEAT,
            MirrorClampToEdge = c.GL_MIRROR_CLAMP_TO_EDGE,
        },
    };
}
pub fn texParameter(
    target: TextureTarget,
    comptime pname: TextureParameter,
    value: TextureParameterValue(pname),
) void {
    // TODO: i might be missing one or two guarantees
    const info = @typeInfo(@TypeOf(value));
    if (info == .Enum)
        c.glTexParameteri(@enumToInt(target), @enumToInt(pname), @enumToInt(value))
    else if (info == .Int)
        c.glTexParameteri(@enumToInt(target), @enumToInt(pname), @intCast(c.GLint, value))
    else if (info == .Float)
        c.glTexParameterf(@enumToInt(target), @enumToInt(pname), value);
    assert(getGlError() == null);
}

// TODO: merge with TextureTarget?
pub const TexImageTarget = enum(c.GLenum) {
    TwoD = c.GL_TEXTURE_2D,
    Proxy2D = c.GL_PROXY_TEXTURE_2D,
    OneDArray = c.GL_TEXTURE_1D_ARRAY,
    Proxy1DArray = c.GL_PROXY_TEXTURE_1D_ARRAY,
    Rectangle = c.GL_TEXTURE_RECTANGLE,
    ProxyRectangle = c.GL_PROXY_TEXTURE_RECTANGLE,
    CubeMapPX = c.GL_TEXTURE_CUBE_MAP_POSITIVE_X,
    CubeMapNX = c.GL_TEXTURE_CUBE_MAP_NEGATIVE_X,
    CubeMapPY = c.GL_TEXTURE_CUBE_MAP_POSITIVE_Y,
    CubeMapNY = c.GL_TEXTURE_CUBE_MAP_NEGATIVE_Y,
    CubeMapPZ = c.GL_TEXTURE_CUBE_MAP_POSITIVE_Z,
    CubeMapNZ = c.GL_TEXTURE_CUBE_MAP_NEGATIVE_Z,
    ProxyCubeMap = c.GL_PROXY_TEXTURE_CUBE_MAP,
};
pub const DataInternalFormat = enum(c.GLint) {
    DepthComponent = c.GL_DEPTH_COMPONENT,
    DepthStencil = c.GL_DEPTH_STENCIL,
    R = c.GL_RED,
    RG = c.GL_RG,
    RGB = c.GL_RGB,
    RGBA = c.GL_RGBA,

    R8 = c.GL_R8,
    R16 = c.GL_R16,
    RG8 = c.GL_RG8,
    RG16 = c.GL_RG16,
    R8SNorm = c.GL_R8_SNORM, // "SNORM": Signed normalized integer format. should we rewrite "SNorm" as "si"?
    R16SNorm = c.GL_R16_SNORM,
    RG8SNorm = c.GL_RG8_SNORM,
    RG16SNorm = c.GL_RG16_SNORM,
    R3G3B2 = c.GL_R3_G3_B2,
    RGB4 = c.GL_RGB4,
    RGB5 = c.GL_RGB5,
    RGB8 = c.GL_RGB8,
    RGB8SNorm = c.GL_RGB8_SNORM,
    RGB10 = c.GL_RGB10,
    RGB12 = c.GL_RGB12,
    RGB16SNorm = c.GL_RGB16_SNORM,
    RGBA2 = c.GL_RGBA2,
    RGBA4 = c.GL_RGBA4,
    RGB5A1 = c.GL_RGB5_A1,
    RGBA8 = c.GL_RGBA8,
    RGBA8SNorm = c.GL_RGBA8_SNORM,
    RGB10A2 = c.GL_RGB10_A2,
    RGB10A2ui = c.GL_RGB10_A2UI,
    RGBA12 = c.GL_RGBA12,
    RGBA16 = c.GL_RGBA16,
    SRGB8 = c.GL_SRGB8,
    SRGB8A8 = c.GL_SRGB8_ALPHA8,
    R16f = c.GL_R16F,
    RG16f = c.GL_RG16F,
    RGB16f = c.GL_RGB16F,
    RGBA16f = c.GL_RGBA16F,
    R32f = c.GL_R32F,
    RG32f = c.GL_RG32F,
    RGB32f = c.GL_RGB32F,
    RGBA32f = c.GL_RGBA32F,
    R11fG11fB10f = c.GL_R11F_G11F_B10F,
    RGB9E5 = c.GL_RGB9_E5,
    R8i = c.GL_R8I,
    R8ui = c.GL_R8UI,
    R16i = c.GL_R16I,
    R16ui = c.GL_R16UI,
    R32i = c.GL_R32I,
    R32ui = c.GL_R32UI,
    RG8i = c.GL_RG8I,
    RG8ui = c.GL_RG8UI,
    RG16i = c.GL_RG16I,
    RG16ui = c.GL_RG16UI,
    RG32i = c.GL_RG32I,
    RG32ui = c.GL_RG32UI,
    RGB8i = c.GL_RGB8I,
    RGB8ui = c.GL_RGB8UI,
    RGB16i = c.GL_RGB16I,
    RGB16ui = c.GL_RGB16UI,
    RGB32i = c.GL_RGB32I,
    RGB32ui = c.GL_RGB32UI,
    RGBA8i = c.GL_RGBA8I,
    RGBA8ui = c.GL_RGBA8UI,
    RGBA16i = c.GL_RGBA16I,
    RGBA16ui = c.GL_RGBA16UI,
    RGBA32i = c.GL_RGBA32I,
    RGBA32ui = c.GL_RGBA32UI,

    CompressedR = c.GL_COMPRESSED_RED,
    CompressedRG = c.GL_COMPRESSED_RG,
    CompressedRGB = c.GL_COMPRESSED_RGB,
    CompressedRGBA = c.GL_COMPRESSED_RGBA,
    CompressedSRGB = c.GL_COMPRESSED_SRGB,
    CompressedSRGBA = c.GL_COMPRESSED_SRGB_ALPHA,
    CompressedR_RGTC1 = c.GL_COMPRESSED_RED_RGTC1,
    CompressedSR_RGTC1 = c.GL_COMPRESSED_SIGNED_RED_RGTC1,
    CompressedRG_RGTC2 = c.GL_COMPRESSED_RG_RGTC2,
    CompressedSRG_RGTC2 = c.GL_COMPRESSED_SIGNED_RG_RGTC2,
    CompressedRGBA_BPTCUNorm = c.GL_COMPRESSED_RGBA_BPTC_UNORM,
    CompressedSRGBA_BPTCUNorm = c.GL_COMPRESSED_SRGB_ALPHA_BPTC_UNORM,
    CompressedRGB_BPTCsf = c.GL_COMPRESSED_RGB_BPTC_SIGNED_FLOAT,
    CompressedRGB_BPTCuf = c.GL_COMPRESSED_RGB_BPTC_UNSIGNED_FLOAT,
};
pub const DataFormat = enum(c.GLenum) {
    R = c.GL_RED,
    G = c.GL_GREEN,
    B = c.GL_BLUE,
    RG = c.GL_RG,
    RGB = c.GL_RGB,
    BGR = c.GL_BGR,
    RGBA = c.GL_RGBA,
    BGRA = c.GL_BGRA,
    Ri = c.GL_RED_INTEGER,
    RGi = c.GL_RG_INTEGER,
    RGBi = c.GL_RGB_INTEGER,
    BGRi = c.GL_BGR_INTEGER,
    RGBAi = c.GL_RGBA_INTEGER,
    BGRAi = c.GL_BGRA_INTEGER,
    StencilIndex = c.GL_STENCIL_INDEX,
    DepthComponent = c.GL_DEPTH_COMPONENT,
    DepthStencil = c.GL_DEPTH_STENCIL,
};
pub fn texImage2D(
    target: TexImageTarget,
    level: u32,
    internal_format: DataInternalFormat,
    width: u32,
    height: u32,
    border: u0,
    format: DataFormat,
    kind: DataKind,
    data: [*]const u8,
) void {
    assert(switch (kind) {
        .UnsignedByte,
        .Byte,
        .UnsignedShort,
        .Short,
        .UnsignedInt,
        .Int,
        .HalfFloat,
        .Float,
        .UnsignedByte332,
        .UnsignedByte233Rev,
        .UnsignedShort565,
        .UnsignedShort565Rev,
        .UnsignedShort4444,
        .UnsignedShort4444Rev,
        .UnsignedShort5551,
        .UnsignedShort1555Rev,
        .UnsignedInt8888,
        .UnsignedInt8888Rev,
        .UnsignedInt1010102,
        .UnsignedInt2101010Rev,
        => true,
        else => false,
    });
    assert(switch (format) {
        .R,
        .RG,
        .RGB,
        .BGR,
        .RGBA,
        .BGRA,
        .Ri,
        .RGi,
        .RGBi,
        .BGRi,
        .RGBAi,
        .BGRAi,
        .StencilIndex,
        .DepthComponent,
        .DepthStencil,
        => true,
        else => false,
    });
    assert(level <= comptime std.math.log2_int(u32, c.GL_MAX_TEXTURE_SIZE));
    if (switch (target) {
        .CubeMapPX, .CubeMapNX, .CubeMapPY, .CubeMapNY, .CubeMapPZ, .CubeMapNZ => true,
        else => false,
    }) assert(width == height);
    assert(width < c.GL_MAX_TEXTURE_SIZE);
    if (target != .OneDArray and target != .Proxy1DArray)
        assert(height < c.GL_MAX_TEXTURE_SIZE)
    else
        assert(height < c.GL_MAX_ARRAY_TEXTURE_LAYERS);
    if (format != .RGB)
        assert(switch (kind) {
            .UnsignedByte332,
            .UnsignedByte233Rev,
            .UnsignedShort565,
            .UnsignedShort565Rev,
            => false,
            else => true,
        });
    if (format != .RGBA and format != .BGRA)
        assert(switch (kind) {
            .UnsignedShort4444,
            .UnsignedShort4444Rev,
            .UnsignedShort5551,
            .UnsignedShort1555Rev,
            .UnsignedInt8888,
            .UnsignedInt8888Rev,
            .UnsignedInt1010102,
            .UnsignedInt2101010Rev,
            => false,
            else => true,
        });
    if (internal_format == .DepthComponent) {
        assert(switch (target) {
            .TwoD, .Proxy2D, .Rectangle, .ProxyRectangle => true,
            else => false,
        });
        assert(format == .DepthComponent);
    }
    if (level != 0) assert(target != .Rectangle and target != .ProxyRectangle);
    c.glTexImage2D(
        @enumToInt(target),
        @intCast(c.GLint, level),
        @enumToInt(internal_format),
        @intCast(c.GLsizei, width),
        @intCast(c.GLsizei, height),
        @intCast(c.GLint, border),
        @enumToInt(format),
        @enumToInt(kind),
        data,
    );
    assert(getGlError() == null);
}

pub fn readPixels(
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    format: DataFormat,
    kind: DataKind,
    out_data: [*]u8,
) void {
    assert(switch (format) {
        .StencilIndex,
        .DepthComponent,
        .DepthStencil,
        .R,
        .G,
        .B,
        .RGB,
        .BGR,
        .RGBA,
        .BGRA,
        => true,
        else => false,
    });
    assert(switch (kind) {
        .UnsignedByte,
        .Byte,
        .UnsignedShort,
        .Short,
        .UnsignedInt,
        .Int,
        .HalfFloat,
        .Float,
        .UnsignedByte332,
        .UnsignedByte233Rev,
        .UnsignedShort565,
        .UnsignedShort565Rev,
        .UnsignedShort4444,
        .UnsignedShort4444Rev,
        .UnsignedShort5551,
        .UnsignedShort1555Rev,
        .UnsignedInt8888,
        .UnsignedInt8888Rev,
        .UnsignedInt1010102,
        .UnsignedInt2101010Rev,
        .UnsignedInt248,
        .UnsignedInt10f11f11fRev,
        .UnsignedInt5999Rev,
        .Float32UnsignedInt248Rev,
        => true,
        else => false,
    });
    if (format == .DepthStencil) assert(kind == .UnsignedInt248 or kind == .Float32UnsignedInt248Rev);
    if (format != .RGB)
        assert(switch (kind) {
            .UnsignedByte332,
            .UnsignedByte233Rev,
            .UnsignedShort565,
            .UnsignedShort565Rev,
            => false,
            else => true,
        });
    if (format != .RGBA and format != .BGRA)
        assert(switch (kind) {
            .UnsignedShort4444,
            .UnsignedShort4444Rev,
            .UnsignedShort5551,
            .UnsignedShort1555Rev,
            .UnsignedInt8888,
            .UnsignedInt8888Rev,
            .UnsignedInt1010102,
            .UnsignedInt2101010Rev,
            => false,
            else => true,
        });
    c.glReadPixels(
        @intCast(c.GLint, x),
        @intCast(c.GLint, y),
        @intCast(c.GLsizei, width),
        @intCast(c.GLsizei, height),
        @enumToInt(format),
        @enumToInt(kind),
        out_data,
    );
    assert(getGlError() == null);
}

pub const ClearBufferKind = enum { //(c.GLbitfield) {
    Color, // = c.GL_COLOR_BUFFER_BIT,
    Depth, // = c.GL_DEPTH_BUFFER_BIT,
    DepthF,
    Stencil, // = c.GL_STENCIL_BUFFER_BIT,
};
pub fn ClearValue(comptime buffers: []const ClearBufferKind) type {
    comptime var fields: [buffers.len]std.builtin.Type.StructField = undefined;
    inline for (buffers) |kind, i| {
        switch (kind) {
            .Color => {
                const T = struct { r: f32 = 0, g: f32 = 0, b: f32 = 0, a: f32 = 0 };
                fields[i] = .{
                    .name = "color",
                    .type = T,
                    .default_value = @ptrCast(?*const anyopaque, &T{}),
                    .is_comptime = false,
                    .alignment = @alignOf(T),
                };
            },
            .Depth => {
                const T = f64;
                fields[i] = .{
                    .name = "depth",
                    .type = T,
                    .default_value = @ptrCast(?*const anyopaque, &@as(T, 1.0)),
                    .is_comptime = false,
                    .alignment = @alignOf(T),
                };
            },
            .DepthF => {
                const T = f32;
                fields[i] = .{
                    .name = "depth",
                    .type = T,
                    .default_value = @ptrCast(?*const anyopaque, &@as(T, 1.0)),
                    .is_comptime = false,
                    .alignment = @alignOf(T),
                };
            },
            .Stencil => {
                const T = u32; // is this supposed to be signed?
                fields[i] = .{
                    .name = "stencil",
                    .type = T,
                    .default_value = @ptrCast(?*const anyopaque, &@as(T, 1)),
                    .is_comptime = false,
                    .alignment = @alignOf(T),
                };
            },
        }
    }
    return @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}
pub fn clear(comptime buffers: []const ClearBufferKind, value: ClearValue(buffers)) void {
    // hopefully `ClearValue` errors if you do both Depth and DepthF
    inline for (buffers) |kind| switch (kind) {
        .Color => c.glClearColor(value.color.r, value.color.g, value.color.b, value.color.a),
        .Depth => c.glClearDepth(value.depth),
        .DepthF => c.glClearDepthf(value.depth),
        .Stencil => c.glClearStencil(@intCast(c.GLint, value.stencil)),
    };
    comptime var mask = 0;
    inline for (buffers) |kind| mask |= switch (kind) {
        .Color => c.GL_COLOR_BUFFER_BIT,
        .Depth => c.GL_DEPTH_BUFFER_BIT,
        .DepthF => c.GL_DEPTH_BUFFER_BIT,
        .Stencil => c.GL_STENCIL_BUFFER_BIT,
    };
    c.glClear(@intCast(c.GLbitfield, mask));
    assert(getGlError() == null);
}

pub const ScaleFactor = enum(c.GLenum) {
    Zero = c.GL_ZERO,
    One = c.GL_ONE,
    SrcColor = c.GL_SRC_COLOR,
    OneMinusSrcColor = c.GL_ONE_MINUS_SRC_COLOR,
    DstColor = c.GL_DST_COLOR,
    OneMinusDstColor = c.GL_ONE_MINUS_DST_COLOR,
    SrcAlpha = c.GL_SRC_ALPHA,
    OneMinusSrcAlpha = c.GL_ONE_MINUS_SRC_ALPHA,
    DstAlpha = c.GL_DST_ALPHA,
    OneMinusDstAlpha = c.GL_ONE_MINUS_DST_ALPHA,
    ConstantColor = c.GL_CONSTANT_COLOR,
    OneMinusConstantColor = c.GL_ONE_MINUS_CONSTANT_COLOR,
    ConstantAlpha = c.GL_CONSTANT_ALPHA,
    OneMinusConstantAlpha = c.GL_ONE_MINUS_CONSTANT_ALPHA,
    SrcAlphaSaturate = c.GL_SRC_ALPHA_SATURATE,
    Src1Color = c.GL_SRC1_COLOR,
    OneMinusSrc1Color = c.GL_ONE_MINUS_SRC1_COLOR,
    Src1Alpha = c.GL_SRC1_ALPHA,
    OneMinusSrc1Alpha = c.GL_ONE_MINUS_SRC1_ALPHA,
};
pub fn blendFunc(sfactor: ScaleFactor, dfactor: ScaleFactor) void {
    c.glBlendFunc(@enumToInt(sfactor), @enumToInt(dfactor));
    assert(getGlError() == null);
}

pub const Capability = enum(c.GLenum) {
    Blend = c.GL_BLEND,
    // ClipDistance = c.GL_CLIP_DISTANCE, // indexed
    ColorLogicOp = c.GL_COLOR_LOGIC_OP,
    CullFace = c.GL_CULL_FACE,
    DebugOutput = c.GL_DEBUG_OUTPUT,
    DebugOutputSynchronous = c.GL_DEBUG_OUTPUT_SYNCHRONOUS,
    DepthClamp = c.GL_DEPTH_CLAMP,
    DepthTest = c.GL_DEPTH_TEST,
    Dither = c.GL_DITHER,
    FramebufferSRGB = c.GL_FRAMEBUFFER_SRGB,
    LineSmooth = c.GL_LINE_SMOOTH,
    Multisample = c.GL_MULTISAMPLE,
    PolygonOffsetFill = c.GL_POLYGON_OFFSET_FILL,
    PolygonOffsetLine = c.GL_POLYGON_OFFSET_LINE,
    PolygonOffsetPoint = c.GL_POLYGON_OFFSET_POINT,
    PolygonSmooth = c.GL_POLYGON_SMOOTH,
    PrimitiveRestart = c.GL_PRIMITIVE_RESTART,
    PrimitiveRestartFixedIndex = c.GL_PRIMITIVE_RESTART_FIXED_INDEX,
    RasterizerDiscard = c.GL_RASTERIZER_DISCARD,
    SampleAlphaToCoverage = c.GL_SAMPLE_ALPHA_TO_COVERAGE,
    SampleAlphaToOne = c.GL_SAMPLE_ALPHA_TO_ONE,
    SampleCoverage = c.GL_SAMPLE_COVERAGE,
    SampleShading = c.GL_SAMPLE_SHADING,
    SampleMask = c.GL_SAMPLE_MASK,
    ScissorTest = c.GL_SCISSOR_TEST,
    StencilTest = c.GL_STENCIL_TEST,
    TextureCubeMapSeamless = c.GL_TEXTURE_CUBE_MAP_SEAMLESS,
    ProgramPointSize = c.GL_PROGRAM_POINT_SIZE,
};
pub fn enable(capability: Capability) void {
    c.glEnable(@enumToInt(capability));
    assert(getGlError() == null);
}

pub const DrawMode = enum(c.GLenum) {
    Points = c.GL_POINTS,
    LineStrip = c.GL_LINE_STRIP,
    LineLoop = c.GL_LINE_LOOP,
    Lines = c.GL_LINES,
    LineStripAdjacency = c.GL_LINE_STRIP_ADJACENCY,
    LinesAdjacency = c.GL_LINES_ADJACENCY,
    TriangleStrip = c.GL_TRIANGLE_STRIP,
    TriangleFan = c.GL_TRIANGLE_FAN,
    Triangles = c.GL_TRIANGLES,
    TriangleStripAdjacency = c.GL_TRIANGLE_STRIP_ADJACENCY,
    TrianglesAdjacency = c.GL_TRIANGLES_ADJACENCY,
    Patches = c.GL_PATCHES,
};
pub fn drawArrays(mode: DrawMode, first: u32, count: u32) void {
    c.glDrawArrays(@enumToInt(mode), @intCast(c.GLint, first), @intCast(c.GLsizei, count));
    assert(getGlError() == null);
}
