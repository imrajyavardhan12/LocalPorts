const std = @import("std");
const app_version = @import("src/version.zig").version;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "localports",
        .version = std.SemanticVersion.parse(app_version) catch unreachable,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    b.installArtifact(exe);
    b.installFile("man/localports.1", "share/man/man1/localports.1");
    b.installFile("completions/localports.bash", "share/bash-completion/completions/localports");
    b.installFile("completions/_localports", "share/zsh/site-functions/_localports");
    b.installFile("completions/localports.fish", "share/fish/vendor_completions.d/localports.fish");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run localports");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
