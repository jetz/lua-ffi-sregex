local ffi = require('ffi')

local ffi_new = ffi.new
local ffi_cast = ffi.cast
local ffi_sizeof = ffi.sizeof
local tonumber = tonumber
local str_fmt = string.format
local table_insert = table.insert

cdef_tpl = [[
typedef uint8_t  sre_char;
typedef intptr_t  sre_int_t;
typedef uintptr_t  sre_uint_t;

/* the memory pool API */
struct sre_pool_s;
typedef struct sre_pool_s  sre_pool_t;

SRE_API sre_pool_t *sre_create_pool(size_t size);
SRE_API void sre_reset_pool(sre_pool_t *pool);
SRE_API void sre_destroy_pool(sre_pool_t *pool);


/* the regex parser API */
struct sre_regex_s;
typedef struct sre_regex_s  sre_regex_t;

SRE_API sre_regex_t *sre_regex_parse(sre_pool_t *pool, sre_char *src,
    sre_uint_t *ncaps, int flags, sre_int_t *err_offset);

SRE_API sre_regex_t * sre_regex_parse_multi(sre_pool_t *pool,
    sre_char **regexes, sre_int_t nregexes, sre_uint_t *max_ncaps,
    int *multi_flags, sre_int_t *err_offset, sre_int_t *err_regex_id);

SRE_API void sre_regex_dump(sre_regex_t *re);


/* the regex compiler API */
struct sre_program_s;
typedef struct sre_program_s  sre_program_t;

SRE_API sre_program_t *sre_regex_compile(sre_pool_t *pool, sre_regex_t *re);
SRE_API void sre_program_dump(sre_program_t *prog);


/* the Pike VM API */
struct sre_vm_pike_ctx_s;
typedef struct sre_vm_pike_ctx_s  sre_vm_pike_ctx_t;

SRE_API sre_vm_pike_ctx_t *sre_vm_pike_create_ctx(sre_pool_t *pool,
    sre_program_t *prog, sre_int_t *ovector, size_t ovecsize);

SRE_API sre_int_t sre_vm_pike_exec(sre_vm_pike_ctx_t *ctx, sre_char *input,
    size_t len, unsigned eof, sre_int_t **pending_matched);


/* the Thompson VM API */
struct sre_vm_thompson_ctx_s;
typedef struct sre_vm_thompson_ctx_s  sre_vm_thompson_ctx_t;

SRE_API sre_vm_thompson_ctx_t *sre_vm_thompson_create_ctx(sre_pool_t *pool,
    sre_program_t *prog);

SRE_API sre_int_t sre_vm_thompson_exec(sre_vm_thompson_ctx_t *ctx, sre_char *input,
    size_t len, unsigned eof);


/* Thompson VM JIT API */
struct sre_vm_thompson_code_s;
typedef struct sre_vm_thompson_code_s  sre_vm_thompson_code_t;

typedef sre_int_t (*sre_vm_thompson_exec_pt)(sre_vm_thompson_ctx_t *ctx,
    sre_char *input, size_t size, unsigned eof);

SRE_API sre_int_t sre_vm_thompson_jit_compile(sre_pool_t *pool,
    sre_program_t *prog, sre_vm_thompson_code_t **pcode);

SRE_API sre_vm_thompson_ctx_t *sre_vm_thompson_jit_create_ctx(sre_pool_t *pool,
    sre_program_t *prog);

SRE_API sre_vm_thompson_exec_pt
    sre_vm_thompson_jit_get_handler(sre_vm_thompson_code_t *code);

SRE_API sre_int_t sre_vm_thompson_jit_free(sre_vm_thompson_code_t *code);
]]

if ffi.os == 'Linux' then
    local cdef_str = cdef_tpl:gsub('SRE_API', '__attribute__ ((visibility ("default")))')
    ffi.cdef(cdef_str)
else
    error('Not support ' .. ffi.os)
end

local so_path = './sregex/libsregex.so'
if not so_path then
    error('Fail to load shared objs: ' .. so_path)
end
local clib = ffi.load(so_path)

local _M = {
    OK       = 0,
    ERROR    = -1,
    AGAIN    = -2,
    BUSY     = -3,
    DONE     = -4,
    DECLINED = -5,

    REGEX_CASELESS = 1
}

function _M.create_pool(size)
    return clib.sre_create_pool(size)
end

function _M.reset_pool(pool)
    clib.sre_reset_pool(pool)
end

function _M.destory_pool(pool)
    clib.sre_destroy_pool(pool)
end

function _M.regex_parse(pool, pattern, flags)
    local regex = ffi_new('sre_char[?]', #pattern, pattern)
    local ncaps_ptr = ffi_new('sre_uint_t[1]')
    local err_offset_ptr = ffi.new('sre_int_t[1]')
    local r = clib.sre_regex_parse(pool, regex, ncaps_ptr, flags, err_offset_ptr)
    if r == nil then
        return nil, nil, str_fmt('regex "%s" error at %d', pattern, tonumber(err_offset_ptr[0]))
    end
    return r, tonumber(ncaps_ptr[0]), nil
end

function _M.regex_parse_multi(pool, patterns, multi_flags)
    local const_regex_array = ffi_new('const char*[?]', #patterns, patterns)
    local regex_array = ffi_cast('sre_char**', const_regex_array)
    local max_ncaps_ptr = ffi_new('sre_uint_t[1]')
    local flags_array = ffi_new('int[?]', #multi_flags, multi_flags)
    local err_offset_ptr = ffi.new('sre_int_t[1]')
    local err_regex_id_ptr = ffi.new('sre_int_t[1]')
    local r = clib.sre_regex_parse_multi(pool, 
                                        regex_array, #patterns, max_ncaps_ptr,
                                        flags_array, err_offset_ptr, err_regex_id_ptr)
    if r == nil then
        return nil, nil, str_fmt('regexes[%d] error at %d', 
                                tonumber(err_regex_id_ptr[0]), 
                                tonumber(err_offset_ptr[0]))
    end
    return r, tonumber(max_ncaps_ptr[0]), nil
end

function _M.regex_dump(re)
    return clib.sre_regex_dump(re)
end

function _M.regex_compile(pool, re)
    return clib.sre_regex_compile(pool, re)
end

function _M.program_dump(prog)
    return clib.sre_program_dump(prog)
end

function _M.vm_pike_create_ctx(pool, prog, ncaps)
    local ovecsize = 2 * (ncaps + 1) * ffi_sizeof('sre_int_t')
    local ovector_array = ffi_new('sre_int_t[?]', ovecsize)
    return clib.sre_vm_pike_create_ctx(pool, prog, ovector_array, ovecsize)
end

function _M.vm_pike_exec(ctx, data, mode)
    local pending_matched_ptr = ffi_new('sre_int_t*[1]') 
    local input = ffi_new('sre_char[?]', #data, data)
    local len = ffi_sizeof(input)
    local r = clib.sre_vm_pike_exec(ctx, input, len, mode, pending_matched_ptr)
    if r >= 0 then
        return true, tonumber(r)
    else
        return false, nil
    end
end

function _M.vm_thompson_create_ctx(pool, prog)
    return clib.sre_vm_thompson_create_ctx(pool, prog)
end

function _M.vm_thompson_exec(ctx, data, mode)
    local input = ffi_new('sre_char[?]', #data, data)
    local len = ffi_sizeof(input)
    return clib.sre_vm_thompson_exec(ctx, input, len, mode) == _M.OK
end

function _M.vm_thompson_jit_compile(pool, prog)
    local pcode_ptr = ffi_new('sre_vm_thompson_code_t*[1]')
    local r = clib.sre_vm_thompson_jit_compile(pool, prog, pcode_ptr)
    if r == _M.OK then
        return pcode_ptr[0], nil
    elseif r == _M.DECLINED then
        return nil, 'arch not supported'
    elseif r == _M.ERROR then
        return nil, 'fatal error'
    end
    return nil, 'unknown error'
end

function _M.vm_thompson_jit_get_handler(code)
    return clib.sre_vm_thompson_jit_get_handler(code)
end

function _M.vm_thompson_jit_create_ctx(pool, prog)
    return clib.sre_vm_thompson_jit_create_ctx(pool, prog)
end

function _M.vm_thompson_jit_exec(handler, ctx, data, mode)
    local input = ffi_new('sre_char[?]', #data, data)
    local len = ffi_sizeof(input)
    return handler(ctx, input, len, mode)
end

function _M.vm_thompson_jit_free(code)
    return clib.sre_vm_thompson_jit_free(code)
end

return _M
