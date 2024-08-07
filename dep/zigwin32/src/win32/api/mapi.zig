//! NOTE: this file is autogenerated, DO NOT MODIFY
//--------------------------------------------------------------------------------
// Section: Constants (0)
//--------------------------------------------------------------------------------

//--------------------------------------------------------------------------------
// Section: Types (20)
//--------------------------------------------------------------------------------
pub const MapiFileDesc = extern struct {
    ulReserved: u32,
    flFlags: u32,
    nPosition: u32,
    lpszPathName: PSTR,
    lpszFileName: PSTR,
    lpFileType: *c_void,
};

pub const MapiFileDescW = extern struct {
    ulReserved: u32,
    flFlags: u32,
    nPosition: u32,
    lpszPathName: PWSTR,
    lpszFileName: PWSTR,
    lpFileType: *c_void,
};

pub const MapiFileTagExt = extern struct {
    ulReserved: u32,
    cbTag: u32,
    lpTag: *u8,
    cbEncoding: u32,
    lpEncoding: *u8,
};

pub const MapiRecipDesc = extern struct {
    ulReserved: u32,
    ulRecipClass: u32,
    lpszName: PSTR,
    lpszAddress: PSTR,
    ulEIDSize: u32,
    lpEntryID: *c_void,
};

pub const MapiRecipDescW = extern struct {
    ulReserved: u32,
    ulRecipClass: u32,
    lpszName: PWSTR,
    lpszAddress: PWSTR,
    ulEIDSize: u32,
    lpEntryID: *c_void,
};

pub const MapiMessage = extern struct {
    ulReserved: u32,
    lpszSubject: PSTR,
    lpszNoteText: PSTR,
    lpszMessageType: PSTR,
    lpszDateReceived: PSTR,
    lpszConversationID: PSTR,
    flFlags: u32,
    lpOriginator: *MapiRecipDesc,
    nRecipCount: u32,
    lpRecips: *MapiRecipDesc,
    nFileCount: u32,
    lpFiles: *MapiFileDesc,
};

pub const MapiMessageW = extern struct {
    ulReserved: u32,
    lpszSubject: PWSTR,
    lpszNoteText: PWSTR,
    lpszMessageType: PWSTR,
    lpszDateReceived: PWSTR,
    lpszConversationID: PWSTR,
    flFlags: u32,
    lpOriginator: *MapiRecipDescW,
    nRecipCount: u32,
    lpRecips: *MapiRecipDescW,
    nFileCount: u32,
    lpFiles: *MapiFileDescW,
};

pub const LPMAPILOGON = fn(
    ulUIParam: usize,
    lpszProfileName: ?PSTR,
    lpszPassword: ?PSTR,
    flFlags: u32,
    ulReserved: u32,
    lplhSession: *usize,
) callconv(@import("std").os.windows.WINAPI) u32;

pub const LPMAPILOGOFF = fn(
    lhSession: usize,
    ulUIParam: usize,
    flFlags: u32,
    ulReserved: u32,
) callconv(@import("std").os.windows.WINAPI) u32;

pub const LPMAPISENDMAIL = fn(
    lhSession: usize,
    ulUIParam: usize,
    lpMessage: *MapiMessage,
    flFlags: u32,
    ulReserved: u32,
) callconv(@import("std").os.windows.WINAPI) u32;

pub const LPMAPISENDMAILW = fn(
    lhSession: usize,
    ulUIParam: usize,
    lpMessage: *MapiMessageW,
    flFlags: u32,
    ulReserved: u32,
) callconv(@import("std").os.windows.WINAPI) u32;

pub const LPMAPISENDDOCUMENTS = fn(
    ulUIParam: usize,
    lpszDelimChar: PSTR,
    lpszFilePaths: PSTR,
    lpszFileNames: PSTR,
    ulReserved: u32,
) callconv(@import("std").os.windows.WINAPI) u32;

pub const LPMAPIFINDNEXT = fn(
    lhSession: usize,
    ulUIParam: usize,
    lpszMessageType: PSTR,
    lpszSeedMessageID: PSTR,
    flFlags: u32,
    ulReserved: u32,
    lpszMessageID: PSTR,
) callconv(@import("std").os.windows.WINAPI) u32;

pub const LPMAPIREADMAIL = fn(
    lhSession: usize,
    ulUIParam: usize,
    lpszMessageID: PSTR,
    flFlags: u32,
    ulReserved: u32,
    lppMessage: **MapiMessage,
) callconv(@import("std").os.windows.WINAPI) u32;

pub const LPMAPISAVEMAIL = fn(
    lhSession: usize,
    ulUIParam: usize,
    lpMessage: *MapiMessage,
    flFlags: u32,
    ulReserved: u32,
    lpszMessageID: PSTR,
) callconv(@import("std").os.windows.WINAPI) u32;

pub const LPMAPIDELETEMAIL = fn(
    lhSession: usize,
    ulUIParam: usize,
    lpszMessageID: PSTR,
    flFlags: u32,
    ulReserved: u32,
) callconv(@import("std").os.windows.WINAPI) u32;

pub const LPMAPIFREEBUFFER = fn(
    pv: *c_void,
) callconv(@import("std").os.windows.WINAPI) u32;

pub const LPMAPIADDRESS = fn(
    lhSession: usize,
    ulUIParam: usize,
    lpszCaption: PSTR,
    nEditFields: u32,
    lpszLabels: PSTR,
    nRecips: u32,
    lpRecips: *MapiRecipDesc,
    flFlags: u32,
    ulReserved: u32,
    lpnNewRecips: *u32,
    lppNewRecips: **MapiRecipDesc,
) callconv(@import("std").os.windows.WINAPI) u32;

pub const LPMAPIDETAILS = fn(
    lhSession: usize,
    ulUIParam: usize,
    lpRecip: *MapiRecipDesc,
    flFlags: u32,
    ulReserved: u32,
) callconv(@import("std").os.windows.WINAPI) u32;

pub const LPMAPIRESOLVENAME = fn(
    lhSession: usize,
    ulUIParam: usize,
    lpszName: PSTR,
    flFlags: u32,
    ulReserved: u32,
    lppRecip: **MapiRecipDesc,
) callconv(@import("std").os.windows.WINAPI) u32;


//--------------------------------------------------------------------------------
// Section: Functions (1)
//--------------------------------------------------------------------------------
pub extern "MAPI32" fn MAPIFreeBuffer(
    pv: *c_void,
) callconv(@import("std").os.windows.WINAPI) u32;


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
// Section: Imports (2)
//--------------------------------------------------------------------------------
const PWSTR = @import("system_services.zig").PWSTR;
const PSTR = @import("system_services.zig").PSTR;

test {
    // The following '_ = <FuncPtrType>' lines are a workaround for https://github.com/ziglang/zig/issues/4476
    if (@hasDecl(@This(), "LPMAPILOGON")) { _ = LPMAPILOGON; }
    if (@hasDecl(@This(), "LPMAPILOGOFF")) { _ = LPMAPILOGOFF; }
    if (@hasDecl(@This(), "LPMAPISENDMAIL")) { _ = LPMAPISENDMAIL; }
    if (@hasDecl(@This(), "LPMAPISENDMAILW")) { _ = LPMAPISENDMAILW; }
    if (@hasDecl(@This(), "LPMAPISENDDOCUMENTS")) { _ = LPMAPISENDDOCUMENTS; }
    if (@hasDecl(@This(), "LPMAPIFINDNEXT")) { _ = LPMAPIFINDNEXT; }
    if (@hasDecl(@This(), "LPMAPIREADMAIL")) { _ = LPMAPIREADMAIL; }
    if (@hasDecl(@This(), "LPMAPISAVEMAIL")) { _ = LPMAPISAVEMAIL; }
    if (@hasDecl(@This(), "LPMAPIDELETEMAIL")) { _ = LPMAPIDELETEMAIL; }
    if (@hasDecl(@This(), "LPMAPIFREEBUFFER")) { _ = LPMAPIFREEBUFFER; }
    if (@hasDecl(@This(), "LPMAPIADDRESS")) { _ = LPMAPIADDRESS; }
    if (@hasDecl(@This(), "LPMAPIDETAILS")) { _ = LPMAPIDETAILS; }
    if (@hasDecl(@This(), "LPMAPIRESOLVENAME")) { _ = LPMAPIRESOLVENAME; }

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
