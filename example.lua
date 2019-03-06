local Filter = require('sre_filter')

local patterns = {
    [[\d+]],
    [[\W+]],
    [[^(a|b|c|d)+$]]
}

local ids = { 1, 2, 3 } 

filter = Filter:new()
filter:init_multi(patterns, ids)

print(filter:scan('test'))
print(filter:scan('10000'))
print(filter:scan('abcdabcd'))
print(filter:scan('abcdeabcd'))
print(filter:scan('+=-#%'))
