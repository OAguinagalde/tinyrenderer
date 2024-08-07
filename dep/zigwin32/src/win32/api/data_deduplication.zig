//! NOTE: this file is autogenerated, DO NOT MODIFY
//--------------------------------------------------------------------------------
// Section: Constants (0)
//--------------------------------------------------------------------------------

//--------------------------------------------------------------------------------
// Section: Types (6)
//--------------------------------------------------------------------------------
const CLSID_DedupBackupSupport_Value = @import("../zig.zig").Guid.initString("73d6b2ad-2984-4715-b2e3-924c149744dd");
pub const CLSID_DedupBackupSupport = &CLSID_DedupBackupSupport_Value;

pub const DEDUP_CONTAINER_EXTENT = extern struct {
    ContainerIndex: u32,
    StartOffset: i64,
    Length: i64,
};

pub const DDP_FILE_EXTENT = extern struct {
    Length: i64,
    Offset: i64,
};

pub const DEDUP_BACKUP_SUPPORT_PARAM_TYPE = extern enum(i32) {
    UNOPTIMIZED = 1,
    OPTIMIZED = 2,
};
pub const DEDUP_RECONSTRUCT_UNOPTIMIZED = DEDUP_BACKUP_SUPPORT_PARAM_TYPE.UNOPTIMIZED;
pub const DEDUP_RECONSTRUCT_OPTIMIZED = DEDUP_BACKUP_SUPPORT_PARAM_TYPE.OPTIMIZED;

// TODO: this type is limited to platform 'windowsServer2012'
const IID_IDedupReadFileCallback_Value = @import("../zig.zig").Guid.initString("7bacc67a-2f1d-42d0-897e-6ff62dd533bb");
pub const IID_IDedupReadFileCallback = &IID_IDedupReadFileCallback_Value;
pub const IDedupReadFileCallback = extern struct {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        ReadBackupFile: fn(
            self: *const IDedupReadFileCallback,
            FileFullPath: BSTR,
            FileOffset: i64,
            SizeToRead: u32,
            FileBuffer: [*:0]u8,
            ReturnedSize: *u32,
            Flags: u32,
        ) callconv(@import("std").os.windows.WINAPI) HRESULT,
        OrderContainersRestore: fn(
            self: *const IDedupReadFileCallback,
            NumberOfContainers: u32,
            ContainerPaths: [*]BSTR,
            ReadPlanEntries: *u32,
            ReadPlan: [*]*DEDUP_CONTAINER_EXTENT,
        ) callconv(@import("std").os.windows.WINAPI) HRESULT,
        PreviewContainerRead: fn(
            self: *const IDedupReadFileCallback,
            FileFullPath: BSTR,
            NumberOfReads: u32,
            ReadOffsets: [*]DDP_FILE_EXTENT,
        ) callconv(@import("std").os.windows.WINAPI) HRESULT,
    };
    vtable: *const VTable,
    pub fn MethodMixin(comptime T: type) type { return struct {
        pub usingnamespace IUnknown.MethodMixin(T);
        // NOTE: method is namespaced with interface name to avoid conflicts for now
        pub fn IDedupReadFileCallback_ReadBackupFile(self: *const T, FileFullPath: BSTR, FileOffset: i64, SizeToRead: u32, FileBuffer: [*:0]u8, ReturnedSize: *u32, Flags: u32) callconv(.Inline) HRESULT {
            return @ptrCast(*const IDedupReadFileCallback.VTable, self.vtable).ReadBackupFile(@ptrCast(*const IDedupReadFileCallback, self), FileFullPath, FileOffset, SizeToRead, FileBuffer, ReturnedSize, Flags);
        }
        // NOTE: method is namespaced with interface name to avoid conflicts for now
        pub fn IDedupReadFileCallback_OrderContainersRestore(self: *const T, NumberOfContainers: u32, ContainerPaths: [*]BSTR, ReadPlanEntries: *u32, ReadPlan: [*]*DEDUP_CONTAINER_EXTENT) callconv(.Inline) HRESULT {
            return @ptrCast(*const IDedupReadFileCallback.VTable, self.vtable).OrderContainersRestore(@ptrCast(*const IDedupReadFileCallback, self), NumberOfContainers, ContainerPaths, ReadPlanEntries, ReadPlan);
        }
        // NOTE: method is namespaced with interface name to avoid conflicts for now
        pub fn IDedupReadFileCallback_PreviewContainerRead(self: *const T, FileFullPath: BSTR, NumberOfReads: u32, ReadOffsets: [*]DDP_FILE_EXTENT) callconv(.Inline) HRESULT {
            return @ptrCast(*const IDedupReadFileCallback.VTable, self.vtable).PreviewContainerRead(@ptrCast(*const IDedupReadFileCallback, self), FileFullPath, NumberOfReads, ReadOffsets);
        }
    };}
    pub usingnamespace MethodMixin(@This());
};

// TODO: this type is limited to platform 'windowsServer2012'
const IID_IDedupBackupSupport_Value = @import("../zig.zig").Guid.initString("c719d963-2b2d-415e-acf7-7eb7ca596ff4");
pub const IID_IDedupBackupSupport = &IID_IDedupBackupSupport_Value;
pub const IDedupBackupSupport = extern struct {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        RestoreFiles: fn(
            self: *const IDedupBackupSupport,
            NumberOfFiles: u32,
            FileFullPaths: [*]BSTR,
            Store: *IDedupReadFileCallback,
            Flags: u32,
            FileResults: [*]HRESULT,
        ) callconv(@import("std").os.windows.WINAPI) HRESULT,
    };
    vtable: *const VTable,
    pub fn MethodMixin(comptime T: type) type { return struct {
        pub usingnamespace IUnknown.MethodMixin(T);
        // NOTE: method is namespaced with interface name to avoid conflicts for now
        pub fn IDedupBackupSupport_RestoreFiles(self: *const T, NumberOfFiles: u32, FileFullPaths: [*]BSTR, Store: *IDedupReadFileCallback, Flags: u32, FileResults: [*]HRESULT) callconv(.Inline) HRESULT {
            return @ptrCast(*const IDedupBackupSupport.VTable, self.vtable).RestoreFiles(@ptrCast(*const IDedupBackupSupport, self), NumberOfFiles, FileFullPaths, Store, Flags, FileResults);
        }
    };}
    pub usingnamespace MethodMixin(@This());
};


//--------------------------------------------------------------------------------
// Section: Functions (0)
//--------------------------------------------------------------------------------

//--------------------------------------------------------------------------------
// Section: Unicode Aliases (0)
//--------------------------------------------------------------------------------
pub usingnamespace switch (@import("../zig.zig").unicode_mode) {
    .ansi => struct {
    },
    .wide => struct {
    },
    .unspecified => if (@import("builtin").is_test) struct {
    } else struct {
    },
};
//--------------------------------------------------------------------------------
// Section: Imports (3)
//--------------------------------------------------------------------------------
const BSTR = @import("automation.zig").BSTR;
const IUnknown = @import("com.zig").IUnknown;
const HRESULT = @import("com.zig").HRESULT;

test {
    @setEvalBranchQuota(
        @import("std").meta.declarations(@This()).len * 3
    );

    // reference all the pub declarations
    if (!@import("std").builtin.is_test) return;
    inline for (@import("std").meta.declarations(@This())) |decl| {
        if (decl.is_pub) {
            _ = decl;
        }
    }
}
