const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Module
    const world_music_mod = b.addModule("world_music", .{
        .root_source_file = b.path("src/world_music.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = world_music_mod;

    // Living module
    const living_mod = b.addModule("living", .{
        .root_source_file = b.path("src/living.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = living_mod;

    // Tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/world_music.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Living tests
    const living_tests = b.addTest(.{
        .root_source_file = b.path("src/living.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_living_tests = b.addRunArtifact(living_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_living_tests.step);
}
