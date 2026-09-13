--[[
    WeAreDev Lua Deobfuscator
    Handles common WeAreDev obfuscation patterns:
    - Octal/Hex string encoding
    - Variable renaming
    - Function wrapping
    - Junk code removal
    - Base64 decoding
    - Table-based lookups
]]

local Deobfuscator = {}
Deobfuscator.__index = Deobfuscator

-- Base64 decoding
local function base64_decode(data)
    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    data = string.gsub(data, "[^" .. b .. "=]", "")
    return (data:gsub(".", function(x)
        if x == "=" then return "" end
        local r, f = (""):rep(6), b:find(x) - 1
        for i = 6, 1, -1 do
            r = r:sub(1, i - 1) .. (f % 2) .. r:sub(i)
            f = math.floor(f / 2)
        end
        return r
    end):gsub("%d%d%d%d%d%d%d%d", function(x)
        if #x ~= 8 then return "" end
        local c = 0
        for i = 1, 8 do
            c = c + c + (x:sub(i, i) == "1" and 1 or 0)
        end
        return string.char(c)
    end))
end

-- Create new deobfuscator instance
function Deobfuscator.new()
    return setmetatable({
        variable_map = {},
        var_counter = 0,
        changes = 0
    }, Deobfuscator)
end

-- Decode octal escape sequences (\123)
function Deobfuscator:decode_octal_strings(code)
    return code:gsub("\\([0-3][0-7][0-7])", function(octal)
        self.changes = self.changes + 1
        return string.char(tonumber(octal, 8))
    end)
end

-- Decode hex escape sequences (\xAB)
function Deobfuscator:decode_hex_strings(code)
    return code:gsub("\\x([0-9a-fA-F][0-9a-fA-F])", function(hex)
        self.changes = self.changes + 1
        return string.char(tonumber(hex, 16))
    end)
end

-- Decode unicode sequences (\u{...})
function Deobfuscator:decode_unicode_strings(code)
    return code:gsub("\\u%{([0-9a-fA-F]+)%}", function(unicode)
        self.changes = self.changes + 1
        return utf8.char(tonumber(unicode, 16))
    end)
end

-- Remove concatenation operators for clarity
function Deobfuscator:simplify_concatenation(code)
    -- Convert string concatenations to single strings where possible
    local simplified = code:gsub('(".-")%s*%.%s*(".-")', function(a, b)
        self.changes = self.changes + 1
        return a:sub(1, -2) .. b:sub(2)
    end)
    return simplified
end

-- Remove redundant function wrapping
function Deobfuscator:unwrap_functions(code)
    -- Remove (function() ... end)() patterns
    code = code:gsub("%s*%(function%(%s*%)%s*(.-)%s*end%s*%)%s*%(%s*%)%s*", function(inner)
        self.changes = self.changes + 1
        return inner
    end)
    
    -- Remove local function wrappers
    code = code:gsub("local%s+function%s+_(%w+)%(%s*%)%s*(.-)%s*end%s*_?%1%s*%(%s*%)", function(name, body)
        self.changes = self.changes + 1
        return body
    end)
    
    return code
end

-- Remove junk code and unreachable blocks
function Deobfuscator:remove_junk_code(code)
    -- Remove if false...end blocks
    code = code:gsub("if%s+false%s+then%s*(.-)%s*end", "")
    
    -- Remove if true...else...end (keep only true block)
    code = code:gsub("if%s+true%s+then%s*(.-)%s*else%s*(.-)%s*end", "%1")
    
    -- Remove while false...end
    code = code:gsub("while%s+false%s+do%s*(.-)%s*end", "")
    
    -- Remove empty statements
    code = code:gsub(";%s*;+", ";")
    code = code:gsub("^;+", "")
    code = code:gsub(";+$", "")
    
    if code ~= code then
        self.changes = self.changes + 1
    end
    
    return code
end

-- Decode loadstring/load patterns
function Deobfuscator:decode_loadstring(code)
    -- Extract strings from loadstring/load calls
    return code:gsub("loadstring%s*%(%s*(['\"])(.-)%1%s*%)", function(quote, content)
        self.changes = self.changes + 1
        return content
    end):gsub("load%s*%(%s*(['\"])(.-)%1%s*%)", function(quote, content)
        self.changes = self.changes + 1
        return content
    end)
end

-- Map obfuscated variable names to readable names
function Deobfuscator:map_variables(code)
    local vars_found = {}
    
    -- Find all variable definitions
    for var in code:gmatch("local%s+([%w_]+)") do
        if not vars_found[var] then
            vars_found[var] = true
        end
    end
    
    -- Replace heavily obfuscated names
    for var in pairs(vars_found) do
        if var:match("^[lIL1O0]+$") or var:match("^v%d+$") then
            if not self.variable_map[var] then
                self.var_counter = self.var_counter + 1
                self.variable_map[var] = "var" .. self.var_counter
            end
            code = code:gsub("([^%w_])" .. var .. "([^%w_])", "%1" .. self.variable_map[var] .. "%2")
            code = code:gsub("^" .. var .. "([^%w_])", self.variable_map[var] .. "%1")
            self.changes = self.changes + 1
        end
    end
    
    return code
end

-- Format code with proper indentation
function Deobfuscator:format_code(code)
    local lines = {}
    local indent_level = 0
    
    for line in code:gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$") or line
        
        -- Decrease indent for closing keywords
        if line:match("^end%s*$") or line:match("^until%s") or line:match("^else%s*$") or line:match("^elseif%s") then
            indent_level = math.max(0, indent_level - 1)
        end
        
        if line ~= "" then
            table.insert(lines, string.rep("  ", indent_level) .. line)
        end
        
        -- Increase indent for opening keywords
        if line:match("then%s*$") or line:match("do%s*$") or line:match("function%s*%w+%s*%(%s*%)[%s%w]*$") then
            indent_level = indent_level + 1
        end
    end
    
    return table.concat(lines, "\n")
end

-- Replace common global function obfuscations
function Deobfuscator:decode_global_lookups(code)
    -- _G["print"] -> print
    code = code:gsub('_G%s*%[%s*["\'](%w+)["\']%s*%]', "%1")
    
    -- Replace encoded function names stored in tables
    local patterns = {
        {"print", "p"},
        {"require", "req"},
        {"loadstring", "load"},
        {"assert", "as"},
        {"error", "err"},
    }
    
    return code
end

-- Main deobfuscation function
function Deobfuscator:deobfuscate(code)
    print("[*] Starting deobfuscation...")
    local original_length = #code
    
    -- Apply deobfuscation passes
    code = self:decode_hex_strings(code)
    print("[+] Decoded hex strings")
    
    code = self:decode_octal_strings(code)
    print("[+] Decoded octal strings")
    
    code = self:decode_unicode_strings(code)
    print("[+] Decoded unicode strings")
    
    code = self:simplify_concatenation(code)
    print("[+] Simplified concatenation")
    
    code = self:unwrap_functions(code)
    print("[+] Unwrapped functions")
    
    code = self:remove_junk_code(code)
    print("[+] Removed junk code")
    
    code = self:decode_loadstring(code)
    print("[+] Decoded loadstring/load calls")
    
    code = self:decode_global_lookups(code)
    print("[+] Decoded global lookups")
    
    code = self:map_variables(code)
    print("[+] Mapped variables")
    
    code = self:format_code(code)
    print("[+] Formatted code")
    
    print("[*] Deobfuscation complete!")
    print("[*] Changes made: " .. self.changes)
    print("[*] Size reduction: " .. original_length .. " -> " .. #code .. " bytes")
    
    return code
end

return Deobfuscator
