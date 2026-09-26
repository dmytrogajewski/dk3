// SPDX-License-Identifier: GPL-2.0-or-later
pub const c = @cImport({
    @cDefine("STANDALONE", "1");
    @cInclude("time.h");
    @cInclude("q_shared.h");
    @cInclude("qcommon.h");
});
