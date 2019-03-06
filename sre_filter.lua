local ffi = require('ffi')
local sre = require('sregex')

local ffi_gc = ffi.gc
local ipairs = ipairs
local table_insert = table.insert
local setmetatable = setmetatable

-----------------------------------------------------------------------------
-- Filter
-----------------------------------------------------------------------------
local _M = {
    _VERSION = '1.0',
    modes = {
        s = 0, -- stream
        b = 1, -- block
    }
}

function _M.new(self, mode)
    local mode = (mode or 'b'):lower()
    local sre_mode = _M.modes[mode] or 1
    return setmetatable({ name = 'sre_filter', sre_mode = sre_mode }, { __index = self })
end

function _M.init_multi(self, patterns, ids, flags)
    if #patterns ~= #ids then
        return false, 'patterns and ids not matched'
    end

    if flags and #patterns ~= #flags then
        return false, 'patterns and flags not matched'
    else
        flags = { }
        local flag = sre.REGEX_CASELESS
        for i=0, #patterns, 1 do
            table_insert(flags, flag)
        end
    end

    local pool = sre.create_pool(1024)
    self.pool = ffi_gc(pool, sre.destory)

    local re, ncaps, err = sre.regex_parse_multi(self.pool, patterns, flags)
    if not re then
        return false, err
    end
    self.prog = sre.regex_compile(self.pool, re)
    if self.prog == nil then
        return false, 'fail to compile regex'
    end

    self.ids = ids
    self.ncaps = ncaps

    return true, nil
end

function _M.scan(self, data)
    local ctx = sre.vm_pike_create_ctx(self.pool, self.prog, self.ncaps)
    if ctx ~= nil then
        local matched, pos = sre.vm_pike_exec(ctx, data, self.sre_mode)
        if matched then
            return true, self.ids[pos+1]
        end
    end
    return false, nil
end

return _M
