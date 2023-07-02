const std = @import("std");
const builtin = @import("builtin");
const gui = @import("gui");
const ini = @import("ini");
const structs = @import("structs.zig");
const main = @import("main.zig");
const utils = @import("utils.zig");
const qemu = @import("qemu.zig");
const Tag = std.Target.Os.Tag;

pub var vm: structs.VirtualMachine = undefined;
pub var show = false;

var format_buffer = std.mem.zeroes([1024]u8);

var drives: []*structs.Drive = undefined;

var vm_directory: std.fs.Dir = undefined;
var initialized = false;

var setting: u64 = 0;
var option_index: u64 = 0;

var name = std.mem.zeroes([128]u8);
var architecture: u64 = 0;
var has_acceleration = false;
var chipset: u64 = 0;
var usb_type: u64 = 0;
var has_ahci = false;

var ram = std.mem.zeroes([32]u8);

var cpu: u64 = 0;
var features = std.mem.zeroes([1024]u8);
var cores = std.mem.zeroes([16]u8);
var threads = std.mem.zeroes([16]u8);

var network_type: u64 = 0;
var interface: u64 = 0;

var display: u64 = 0;
var gpu: u64 = 0;
var has_vga_emulation = false;
var has_graphics_acceleration = false;

var host_device: u64 = 0;
var sound: u64 = 0;
var has_input = false;
var has_output = false;

var keyboard: u64 = 0;
var mouse: u64 = 0;
var has_mouse_absolute_pointing = false;

var drives_options = std.mem.zeroes([5]struct {
    is_cdrom: bool,
    bus: u64,
    format: u64,
    cache: u64,
    is_ssd: bool,
    path: [512]u8,
});

pub fn init() !void {
    drives = try main.gpa.alloc(*structs.Drive, 5);
    drives[0] = &vm.drive0;
    drives[1] = &vm.drive1;
    drives[2] = &vm.drive2;
    drives[3] = &vm.drive3;
    drives[4] = &vm.drive4;

    vm_directory = try std.fs.cwd().openDir(vm.basic.name, .{});

    try vm_directory.setAsCwd();

    try init_basic();
    try init_memory();
    try init_processor();
    try init_network();
    try init_graphics();
    try init_audio();
    try init_peripherals();
    try init_drives();

    initialized = true;
}

pub fn deinit() !void {
    try main.virtual_machines_directory.setAsCwd();

    vm_directory.close();

    main.gpa.free(drives);
}

pub fn gui_frame() !void {
    if (!show) {
        if (initialized) {
            try deinit();

            setting = 0;
            initialized = false;
        }

        return;
    }

    var window = try gui.floatingWindow(@src(), .{ .open_flag = &show }, .{ .min_size_content = .{ .w = 800, .h = 600 } });
    defer window.deinit();

    try gui.windowHeader("Edit virtual machine", vm.basic.name, &show);

    var hbox = try gui.box(@src(), .horizontal, .{ .expand = .horizontal, .min_size_content = .{ .h = 600 } });
    defer hbox.deinit();

    {
        var vbox = try gui.box(@src(), .vertical, .{ .expand = .both });
        defer vbox.deinit();

        if (try gui.button(@src(), "Basic", .{ .expand = .horizontal })) {
            setting = 0;
        }
        if (try gui.button(@src(), "Memory", .{ .expand = .horizontal })) {
            setting = 1;
        }
        if (try gui.button(@src(), "Processor", .{ .expand = .horizontal })) {
            setting = 2;
        }
        if (try gui.button(@src(), "Network", .{ .expand = .horizontal })) {
            setting = 3;
        }
        if (try gui.button(@src(), "Graphics", .{ .expand = .horizontal })) {
            setting = 4;
        }
        if (try gui.button(@src(), "Audio", .{ .expand = .horizontal })) {
            setting = 5;
        }
        if (try gui.button(@src(), "Peripherals", .{ .expand = .horizontal })) {
            setting = 6;
        }
        if (try gui.button(@src(), "Drives", .{ .expand = .horizontal })) {
            setting = 7;
        }
        if (try gui.button(@src(), "Command line", .{ .expand = .horizontal })) {
            setting = 8;
        }
        if (try gui.button(@src(), "Run", .{ .expand = .horizontal, .color_style = .accent })) {
            var qemu_arguments = try qemu.get_arguments(vm, drives);
            defer qemu_arguments.deinit();

            var qemu_process = std.ChildProcess.init(qemu_arguments.items, main.gpa);

            qemu_process.spawn() catch {
                try gui.dialog(@src(), .{ .title = "Error", .message = "Unable to create a child process for QEMU." });
                return;
            };
        }
    }

    {
        var vbox = try gui.box(@src(), .vertical, .{ .expand = .both });
        defer vbox.deinit();

        switch (setting) {
            0 => {
                try basic_gui_frame();
            },
            1 => {
                try memory_gui_frame();
            },
            2 => {
                try processor_gui_frame();
            },
            3 => {
                try network_gui_frame();
            },
            4 => {
                try graphics_gui_frame();
            },
            5 => {
                try audio_gui_frame();
            },
            6 => {
                try peripherals_gui_frame();
            },
            7 => {
                try drives_gui_frame();
            },
            8 => {
                try command_line_gui_frame();
            },
            else => {},
        }
    }
}

fn init_basic() !void {
    @memset(&name, 0);

    set_buffer(&name, vm.basic.name);
    architecture = @intFromEnum(vm.basic.architecture);
    has_acceleration = vm.basic.has_acceleration;
    chipset = @intFromEnum(vm.basic.chipset);
    usb_type = @intFromEnum(vm.basic.usb_type);
    has_ahci = vm.basic.has_ahci;
}

fn init_memory() !void {
    var ram_format = try std.fmt.allocPrint(main.gpa, "{d}", .{vm.memory.ram});
    defer main.gpa.free(ram_format);

    @memset(&ram, 0);

    set_buffer(&ram, ram_format);
}

fn init_processor() !void {
    var cores_format = try std.fmt.allocPrint(main.gpa, "{d}", .{vm.processor.cores});
    defer main.gpa.free(cores_format);

    var threads_format = try std.fmt.allocPrint(main.gpa, "{d}", .{vm.processor.threads});
    defer main.gpa.free(threads_format);

    @memset(&features, 0);
    @memset(&cores, 0);
    @memset(&threads, 0);

    cpu = @intFromEnum(vm.processor.cpu);
    set_buffer(&features, vm.processor.features);
    set_buffer(&cores, cores_format);
    set_buffer(&threads, threads_format);
}

fn init_network() !void {
    network_type = @intFromEnum(vm.network.type);
    interface = @intFromEnum(vm.network.interface);
}

fn init_graphics() !void {
    display = @intFromEnum(vm.graphics.display);
    gpu = @intFromEnum(vm.graphics.gpu);
    has_vga_emulation = vm.graphics.has_vga_emulation;
    has_graphics_acceleration = vm.graphics.has_graphics_acceleration;
}

fn init_audio() !void {
    host_device = @intFromEnum(vm.audio.host_device);
    sound = @intFromEnum(vm.audio.sound);
    has_input = vm.audio.has_input;
    has_output = vm.audio.has_output;
}

fn init_peripherals() !void {
    keyboard = @intFromEnum(vm.peripherals.keyboard);
    mouse = @intFromEnum(vm.peripherals.mouse);
    has_mouse_absolute_pointing = vm.peripherals.has_mouse_absolute_pointing;
}

fn init_drives() !void {
    for (drives, 0..) |drive, i| {
        var drive_options = &drives_options[i];

        @memset(&drive_options.path, 0);

        drive_options.*.is_cdrom = drive.is_cdrom;
        drive_options.*.bus = @intFromEnum(drive.bus);
        drive_options.*.format = @intFromEnum(drive.format);
        drive_options.*.cache = @intFromEnum(drive.cache);
        drive_options.*.is_ssd = drive.is_ssd;
        set_buffer(&drive_options.path, drive.path);
    }
}

fn basic_gui_frame() !void {
    option_index = 0;

    try utils.add_text_option("Name", &name, &option_index);
    try utils.add_combo_option("Architecture", &[_][]const u8{"AMD64"}, &architecture, &option_index);
    try utils.add_bool_option("Hardware acceleration", &has_acceleration, &option_index); // TODO: Detect host architecture
    try utils.add_combo_option("Chipset", &[_][]const u8{ "i440FX", "Q35" }, &chipset, &option_index);
    try utils.add_combo_option("USB type", &[_][]const u8{ "None", "OHCI (Open 1.0)", "UHCI (Proprietary 1.0)", "EHCI (2.0)", "XHCI (3.0)" }, &usb_type, &option_index);
    try utils.add_bool_option("Use AHCI", &has_ahci, &option_index);

    if (try gui.button(@src(), "Save", .{ .expand = .horizontal, .color_style = .accent })) {
        // Write updated data to struct
        vm.basic.name = (utils.sanitize_output_text(&name, true) catch {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Please enter a valid name!" });
            return;
        }).items;
        vm.basic.architecture = @enumFromInt(architecture);
        vm.basic.has_acceleration = has_acceleration;
        vm.basic.chipset = @enumFromInt(chipset);
        vm.basic.usb_type = @enumFromInt(usb_type);
        vm.basic.has_ahci = has_ahci;

        // Sanity checks
        if (vm.processor.cpu == .host and !vm.basic.has_acceleration) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "CPU model \"host\" requires hardware acceleration." });
            return;
        } else if (vm.basic.usb_type == .none and vm.network.interface == .usb) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Network interface \"usb\" requires a USB controller." });
            return;
        } else if (vm.basic.usb_type == .none and vm.audio.sound == .usb) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Sound device \"usb\" requires a USB controller." });
            return;
        } else if (vm.basic.usb_type == .none and vm.peripherals.keyboard == .usb) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Keyboard model \"usb\" requires a USB controller." });
            return;
        } else if (vm.basic.usb_type == .none and vm.peripherals.mouse == .usb) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Mouse model \"usb\" requires a USB controller." });
            return;
        }

        for (drives, 0..) |drive, i| {
            if (vm.basic.usb_type == .none and drive.bus == .usb) {
                try gui.dialog(@src(), .{ .title = "Error", .message = try std.fmt.bufPrint(&format_buffer, "Bus \"usb\" of drive {d} requires a USB controller.", .{i}) });
                return;
            } else if (!vm.basic.has_ahci and drive.bus == .sata) {
                try gui.dialog(@src(), .{ .title = "Error", .message = try std.fmt.bufPrint(&format_buffer, "Bus \"sata\" of drive {d} requires a USB controller.", .{i}) });
                return;
            }
        }

        // Write to file
        try save_changes();
    }
}

fn memory_gui_frame() !void {
    option_index = 0;

    try utils.add_text_option("RAM (in MiB)", &ram, &option_index);

    if (try gui.button(@src(), "Save", .{ .expand = .horizontal, .color_style = .accent })) {
        // Write updated data to struct
        vm.memory.ram = utils.sanitize_output_number(&ram) catch {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Please enter a valid amount of RAM!" });
            return;
        };

        // Write to file
        try save_changes();
    }
}

fn processor_gui_frame() !void {
    option_index = 0;

    try utils.add_combo_option("CPU", &[_][]const u8{ "Host", "Max" }, &cpu, &option_index);
    try utils.add_text_option("Features", &features, &option_index);
    try utils.add_text_option("Cores", &cores, &option_index);
    try utils.add_text_option("Threads", &threads, &option_index);

    if (try gui.button(@src(), "Save", .{ .expand = .horizontal, .color_style = .accent })) {
        // Write updated data to struct
        vm.processor.cpu = @enumFromInt(cpu);
        vm.processor.features = (utils.sanitize_output_text(&features, false) catch {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Please enter a valid feature subset!" });
            return;
        }).items;
        vm.processor.cores = utils.sanitize_output_number(&cores) catch {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Please enter a valid amount of cores!" });
            return;
        };
        vm.processor.threads = utils.sanitize_output_number(&threads) catch {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Please enter a valid amount of threads!" });
            return;
        };

        // Sanity checks
        if (vm.processor.cpu == .host and !vm.basic.has_acceleration) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "CPU model \"host\" requires hardware acceleration." });
            return;
        }

        // Write to file
        try save_changes();
    }
}

fn network_gui_frame() !void {
    option_index = 0;

    try utils.add_combo_option("Type", &[_][]const u8{ "None", "NAT" }, &network_type, &option_index);
    try utils.add_combo_option("Interface", &[_][]const u8{ "RTL8139", "E1000", "E1000e", "VMware", "USB", "VirtIO" }, &interface, &option_index);

    if (try gui.button(@src(), "Save", .{ .expand = .horizontal, .color_style = .accent })) {
        // Write updated data to struct
        vm.network.type = @enumFromInt(network_type);
        vm.network.interface = @enumFromInt(interface);

        // Write to file
        try save_changes();
    }
}

fn graphics_gui_frame() !void {
    option_index = 0;

    try utils.add_combo_option("Display", &[_][]const u8{ "None", "SDL", "GTK", "SPICE", "Cocoa", "D-Bus" }, &display, &option_index);
    try utils.add_combo_option("GPU", &[_][]const u8{ "None", "VGA", "QXL", "VMware", "VirtIO" }, &gpu, &option_index);
    try utils.add_bool_option("VGA emulation", &has_vga_emulation, &option_index);
    try utils.add_bool_option("Graphics acceleration", &has_graphics_acceleration, &option_index);

    if (try gui.button(@src(), "Save", .{ .expand = .horizontal, .color_style = .accent })) {
        // Write updated data to struct
        vm.graphics.display = @enumFromInt(display);
        vm.graphics.gpu = @enumFromInt(gpu);
        vm.graphics.has_vga_emulation = has_vga_emulation;
        vm.graphics.has_graphics_acceleration = has_graphics_acceleration;

        // Sanity checks
        if (vm.graphics.gpu == .vga and !vm.graphics.has_vga_emulation) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "GPU model \"vga\" requires VGA emulation." });
            return;
        } else if (vm.graphics.gpu == .vga and vm.graphics.has_graphics_acceleration) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "GPU model \"vga\" doesn't support graphics acceleration." });
            return;
        } else if (vm.graphics.gpu == .qxl and vm.graphics.has_graphics_acceleration) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "GPU model \"qxl\" doesn't support graphics acceleration." });
            return;
        } else if (vm.graphics.display == .cocoa and builtin.os.tag != .macos) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Display \"cocoa\" is only supported on macOS." });
            return;
        } else if (vm.graphics.display == .dbus and builtin.os.tag != .linux and !Tag.isBSD(builtin.os.tag)) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Display \"cocoa\" is only supported on Linux/BSD." });
            return;
        }

        // Write to file
        try save_changes();
    }
}

fn audio_gui_frame() !void {
    option_index = 0;

    try utils.add_combo_option("Host device", &[_][]const u8{ "None", "SDL", "ALSA", "OSS", "PulseAudio", "sndio", "CoreAudio", "DirectSound", "WAV" }, &host_device, &option_index);
    try utils.add_combo_option("Sound", &[_][]const u8{ "Sound Blaster 16", "AC97", "HDA ICH6", "HDA ICH9", "USB" }, &sound, &option_index);
    try utils.add_bool_option("Input", &has_input, &option_index);
    try utils.add_bool_option("Output", &has_output, &option_index);

    if (try gui.button(@src(), "Save", .{ .expand = .horizontal, .color_style = .accent })) {
        // Write updated data to struct
        vm.audio.host_device = @enumFromInt(host_device);
        vm.audio.sound = @enumFromInt(sound);
        vm.audio.has_input = has_input;
        vm.audio.has_output = has_output;

        // Sanity checks
        if (vm.audio.sound == .sb16) {
            if (vm.audio.has_input) {
                try gui.dialog(@src(), .{ .title = "Error", .message = "Cannot add input to sound device \"sb16\" (unsupported operation)." });
                return;
            } else if (!vm.audio.has_output) {
                try gui.dialog(@src(), .{ .title = "Error", .message = "Cannot remove output from sound device \"sb16\" (unsupported operation)." });
                return;
            }
        } else if (vm.audio.sound == .ac97) {
            if (vm.audio.has_input) {
                try gui.dialog(@src(), .{ .title = "Error", .message = "Cannot add input to sound device \"ac97\" (unsupported operation)." });
                return;
            } else if (!vm.audio.has_output) {
                try gui.dialog(@src(), .{ .title = "Error", .message = "Cannot remove output from sound device \"ac97\" (unsupported operation)." });
                return;
            }
        } else if (vm.audio.sound == .usb) {
            if (vm.audio.has_input) {
                try gui.dialog(@src(), .{ .title = "Error", .message = "Cannot add input to sound device \"usb\" (unsupported operation)." });
                return;
            } else if (!vm.audio.has_output) {
                try gui.dialog(@src(), .{ .title = "Error", .message = "Cannot remove output from sound device \"usb\" (unsupported operation)." });
                return;
            } else if (vm.basic.usb_type == .none) {
                try gui.dialog(@src(), .{ .title = "Error", .message = "Sound device \"usb\" requires a USB controller." });
                return;
            }
        } else if (builtin.os.tag == .windows and host_device >= 2 and host_device <= 6) {
            try gui.dialog(@src(), .{ .title = "Error", .message = try std.fmt.bufPrint(&format_buffer, "Audio host device \"{}\" is unsupported by Windows.", .{vm.audio.host_device}) });
            return;
        } else if (builtin.os.tag == .macos and ((host_device >= 2 and host_device <= 5) or host_device == 7)) {
            try gui.dialog(@src(), .{ .title = "Error", .message = try std.fmt.bufPrint(&format_buffer, "Audio host device \"{}\" is unsupported by macOS.", .{vm.audio.host_device}) });
            return;
        } else if (host_device == 6 or host_device == 7) {
            try gui.dialog(@src(), .{ .title = "Error", .message = try std.fmt.bufPrint(&format_buffer, "Audio host device \"{}\" is unsupported by your Unix-based OS.", .{vm.audio.host_device}) });
            return;
        }

        // Write to file
        try save_changes();
    }
}

fn peripherals_gui_frame() !void {
    option_index = 0;

    try utils.add_combo_option("Keyboard", &[_][]const u8{ "None", "USB", "VirtIO" }, &keyboard, &option_index);
    try utils.add_combo_option("Mouse", &[_][]const u8{ "None", "USB", "VirtIO" }, &mouse, &option_index);
    try utils.add_bool_option("Absolute mouse pointing", &has_mouse_absolute_pointing, &option_index);

    if (try gui.button(@src(), "Save", .{ .expand = .horizontal, .color_style = .accent })) {
        // Write updated data to struct
        vm.peripherals.keyboard = @enumFromInt(keyboard);
        vm.peripherals.mouse = @enumFromInt(mouse);
        vm.peripherals.has_mouse_absolute_pointing = has_mouse_absolute_pointing;

        // Sanity checks
        if (vm.peripherals.keyboard == .usb and vm.basic.usb_type == .none) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Keyboard model \"usb\" requires a USB controller." });
            return;
        } else if (vm.peripherals.mouse == .usb and vm.basic.usb_type == .none) {
            try gui.dialog(@src(), .{ .title = "Error", .message = "Mouse model \"usb\" requires a USB controller." });
            return;
        }

        // Write to file
        try save_changes();
    }
}

fn drives_gui_frame() !void {
    option_index = 0;

    var scroll = try gui.scrollArea(@src(), .{}, .{ .expand = .both, .color_style = .window });
    defer scroll.deinit();

    for (drives, 0..) |_, i| {
        var drive_options = &drives_options[i];

        try gui.label(@src(), "Drive {d}:", .{i}, .{ .id_extra = option_index });

        try utils.add_bool_option("CD-ROM", &drive_options.is_cdrom, &option_index);
        try utils.add_combo_option("Bus", &[_][]const u8{ "USB", "IDE", "SATA", "VirtIO" }, &drive_options.bus, &option_index);
        try utils.add_combo_option("Format", &[_][]const u8{ "Raw", "QCOW2", "VMDK", "VDI", "VHD" }, &drive_options.format, &option_index);
        try utils.add_combo_option("Cache", &[_][]const u8{ "None", "Writeback", "Writethrough", "Directsync", "Unsafe" }, &drive_options.cache, &option_index);
        try utils.add_bool_option("SSD", &drive_options.is_ssd, &option_index);
        try utils.add_text_option("Path", &drive_options.path, &option_index);
    }

    if (try gui.button(@src(), "Save", .{ .expand = .horizontal, .color_style = .accent })) {
        // Write updated data to struct
        for (drives, 0..) |drive, i| {
            var drive_options = drives_options[i];

            drive.*.is_cdrom = drive_options.is_cdrom;
            drive.*.bus = @enumFromInt(drive_options.bus);
            drive.*.format = @enumFromInt(drive_options.format);
            drive.*.cache = @enumFromInt(drive_options.cache);
            drive.*.is_ssd = drive_options.is_ssd;
            drive.*.path = (utils.sanitize_output_text(&drive_options.path, false) catch {
                try gui.dialog(@src(), .{ .title = "Error", .message = "Please enter a valid drive path!" });
                return;
            }).items;

            // Sanity checks
            if (drive.bus == .usb and vm.basic.usb_type == .none) {
                try gui.dialog(@src(), .{ .title = "Error", .message = try std.fmt.bufPrint(&format_buffer, "Bus \"usb\" of drive {d} requires a USB controller.", .{i}) });
                return;
            } else if (drive.bus == .sata and !vm.basic.has_ahci) {
                try gui.dialog(@src(), .{ .title = "Error", .message = try std.fmt.bufPrint(&format_buffer, "Bus \"sata\" of drive {d} requires a SATA controller.", .{i}) });
                return;
            } else if (drive.bus == .usb and drive.is_cdrom) {
                try gui.dialog(@src(), .{ .title = "Error", .message = try std.fmt.bufPrint(&format_buffer, "Bus \"usb\" of drive {d} cannot have a CD-ROM drive.", .{i}) });
                return;
            } else if (drive.bus == .virtio and drive.is_cdrom) {
                try gui.dialog(@src(), .{ .title = "Error", .message = try std.fmt.bufPrint(&format_buffer, "Bus \"virtio\" of drive {d} cannot have a CD-ROM drive.", .{i}) });
                return;
            }
        }

        // Write to file
        try save_changes();
    }
}

fn command_line_gui_frame() !void {
    var qemu_arguments = try qemu.get_arguments(vm, drives);
    defer qemu_arguments.deinit();

    var arguments = std.ArrayList(u8).init(main.gpa);
    defer arguments.deinit();

    for (qemu_arguments.items) |arg| {
        for (arg) |c| {
            try arguments.append(c);
        }
        try arguments.appendSlice(" \\\n    ");
    }

    try gui.textEntry(@src(), .{ .text = arguments.items }, .{ .expand = .both });
}

fn save_changes() !void {
    // TODO: If we change the VM name, we need to change the directory name as well
    var file = try std.fs.cwd().createFile("config.ini", .{});
    defer file.close();

    try ini.writeStruct(vm, file.writer());
}

fn set_buffer(buffer: []u8, value: []const u8) void {
    var index: u64 = 0;

    for (value) |c| {
        buffer[index] = c;
        index += 1;
    }
}
