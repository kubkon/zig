const std = @import("std");
const log = std.log.scoped(.reloc);
const macho = std.macho;
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;

const aarch64 = @import("../../../codegen/aarch64.zig");

pub const RelocInfo = struct {
    tag: Tag,
    index: u24,
    offset: i32,
    tt: macho.reloc_type_arm64,

    pub const Tag = enum {
        Symbol,
        Section,
    };
};

pub const RelocGrouping = struct {
    relocs: std.ArrayListUnmanaged(RelocInfo) = .{},

    pub fn deinit(self: *RelocGrouping, allocator: *Allocator) void {
        self.relocs.deinit(allocator);
    }
};

pub const Reloc = struct {
    tag: Tag,
    offset: i32,
    length: u4,
    ref: Ref,

    pub const Tag = enum {
        branch,
    };

    pub const Ref = union(enum) {
        Symbol: u24,
        Section: u24,
    };

    pub fn create(raw_reloc: macho.relocation_info) !Reloc {
        const offset = raw_reloc.r_address;
        const length = try math.powi(u4, 2, raw_reloc.r_length);
        const is_pc = raw_reloc.r_pcrel == 1;

        const ref: Ref = if (raw_reloc.r_extern == 1)
            .{ .Symbol = raw_reloc.r_symbolnum }
        else
            .{ .Section = raw_reloc.r_symbolnum - 1 };

        const rel_type = @intToEnum(macho.reloc_type_arm64, raw_reloc.r_type);
        const tag: Tag = tag: {
            switch (rel_type) {
                .ARM64_RELOC_BRANCH26 => {
                    if (!is_pc) return error.NonPCBranchRelocation;
                    break :tag .branch;
                },
                else => return error.TODOReloc,
            }
        };

        return Reloc{
            .offset = offset,
            .length = length,
            .ref = ref,
            .tag = tag,
        };
    }

    pub fn resolve(self: Self, code: []u8, source_addr: u64, dest_addr: u64) !void {
        log.debug("{s}", .{@tagName(self.tag)});
        log.debug("    | source address 0x{x}", .{source_addr});
        log.debug("    | destination address 0x{x}", .{dest_addr});

        const inst = code[self.offset..][0..self.length];
        return switch (self.tag) {
            .branch => self.resolveBranch(inst, source_addr, dest_addr),
        };
    }

    fn resolveBranch(self: Self, code: []u8, source_addr: u64, dest_addr: u64) !void {
        assert(code.len == 4);
        const source_i = try math.cast(i64, source_addr);
        const dest_i = try math.cast(i64, dest_addr);
        const disp = try math.cast(i28, dest_i - source_i);

        log.debug("    | displacement 0x{x}", .{disp});

        const Inst = meta.TagPayload(aarch64.Instruction, aarch64.Instruction.UnconditionalBranchImmediate);
        var parsed = mem.bytesAsValue(Inst, code);
        parsed.imm26 = @truncate(u26, @bitCast(u28, disp) >> 2);
    }
};

test "branch relocation" {
    const raw_reloc = macho.relocation_info{
        .r_address = 0,
        .r_symbolnum = 0,
        .r_pcrel = 1,
        .r_length = 2,
        .r_extern = 1,
        .r_type = @enumToInt(macho.reloc_type_arm64.ARM64_RELOC_BRANCH26),
    };

    const reloc = try Reloc.create(raw_reloc);
    std.debug.print("{any}", .{reloc});
}
