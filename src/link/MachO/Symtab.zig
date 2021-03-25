const Symtab = @This();

const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.symtab);
const macho = std.macho;
const mem = std.mem;

const Allocator = mem.Allocator;

symbols: std.StringArrayHashMapUnmanaged(Symbol) = .{},

pub const Symbol = struct {
    tt: Type,
    index: u16,
    address: ?u64 = null,
    section_id: ?u16 = null,
};

pub const Type = enum {
    Weak,
    Strong,
    Extern,
    Undef,
};

pub fn deinit(self: *Symtab, allocator: *Allocator) void {
    for (self.symbols.items()) |*entry| {
        allocator.free(entry.key);
    }
    self.symbols.deinit(allocator);
}

pub fn get(self: Symtab, key: []const u8) ?Symbol {
    return self.symbols.get(key);
}

pub fn put(self: *Symtab, allocator: *Allocator, key: []const u8, symbol: Symbol) !void {
    log.warn("putting '{s}' into the symbol table", .{key});

    const entry = self.symbols.getEntry(key) orelse {
        log.warn("    | symbol type {s}", .{symbol.tt});
        log.warn("    | {any}", .{symbol});
        const name = try allocator.dupe(u8, key);
        return self.symbols.putNoClobber(allocator, name, symbol);
    };

    switch (symbol.tt) {
        .Strong => {
            if (entry.value.tt == .Strong) {
                log.err("symbol '{s}' defined multiple times", .{key});
                return error.MultipleSymbolDefinitions;
            }
        },
        .Weak => {
            switch (entry.value.tt) {
                .Undef, .Extern => {},
                else => return,
            }
        },
        .Extern => {
            if (entry.value.tt != .Undef) return;
        },
        .Undef => return,
    }

    log.warn("    | promoting {s} -> {s}", .{ entry.value.tt, symbol.tt });
    log.warn("    | {any}", .{symbol});

    entry.value = symbol;
}
