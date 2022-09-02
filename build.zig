const std = @import("std");

const GitRepoStep = @import("GitRepoStep.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("chatsoftware", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    const serde_repo = GitRepoStep.create(b, .{
        .url = "git@github.com:regenerativep/zig-serde.git",
        .branch = "main",
        .sha = "d0e38abab3ec37ec2c42554f430f05e84fb5b45a",
    });
    exe.step.dependOn(&serde_repo.step);
    exe.addPackagePath("serde", std.fs.path.join(b.allocator, &[_][]const u8{
        serde_repo.getPath(&exe.step),
        "serde.zig",
    }) catch unreachable);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
