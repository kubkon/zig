pub const RelocAarch64 = @import("reloc/aarch64.zig").Reloc;
pub const RelocX86_64 = @import("reloc/x86_64.zig").Reloc;

test "" {
    @import("std").testing.refAllDecls(@This());
}
