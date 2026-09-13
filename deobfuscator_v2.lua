--[[
    Advanced WeAreDev Lua Deobfuscator v2.0
    Handles complex obfuscation with bytecode analysis
]]

local Deobfuscator = {}
Deobfuscator.__index = Deobfuscator

-- Charset for base64/custom encoding
local charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function Deobfuscator.new()
    return setmetatable({
        variable_map = {},
        string_map = {},
        var_counter = 0,
        changes = 0,
        debug = false
    }, Deobfuscator)
end

-- Extract string table from WeAreDev code
function Deobfuscator:extract_string_table(code)
    local strings = {}
    local in_table = false
    local current_string = ""
    local depth = 0
    
    -- Find the string table: return(function(...)local U={...}
    local table_start = code:find("local%s+U%s*=%s*{")
    if not table_start then
        return strings
    end
    
    local pos = table_start
    local i = 0
    
    -- Parse strings from the table
    for str in code:gmatch('"[^"]*"') do
        i = i + 1
        strings[i] = str:sub(2, -2) -- Remove quotes
    end
    
    for str in code:gmatch("'[^']*'") do
        i = i + 1
        strings[i] = str:sub(2, -2) -- Remove quotes
    end
    
    return strings
end

-- Decode octal escape sequences in strings
function Deobfuscator:decode_octal(str)
    return str:gsub("\\([0-3][0-7][0-7])", function(octal)
        self.changes = self.changes + 1
        return string.char(tonumber(octal, 8))
    end)
end

-- Decode hex escape sequences
function Deobfuscator:decode_hex(str)
    return str:gsub("\\x([0-9a-fA-F][0-9a-fA-F])", function(hex)
        self.changes = self.changes + 1
        return string.char(tonumber(hex, 16))
    end)
end

-- Decode unicode escapes
function Deobfuscator:decode_unicode(str)
    return str:gsub("\\u%{([0-9a-fA-F]+)%}", function(unicode)
        self.changes = self.changes + 1
        return utf8.char(tonumber(unicode, 16))
    end)
end

-- Decode all strings in code
function Deobfuscator:decode_all_strings(code)
    code = code:gsub('"([^"]*)"', function(str)
        local decoded = self:decode_octal(str)
        decoded = self:decode_hex(decoded)
        decoded = self:decode_unicode(decoded)
        if decoded ~= str then
            self.changes = self.changes + 1
            return '"' .. decoded .. '"'
        end
        return '"' .. str .. '"'
    end)
    
    code = code:gsub("'([^']*)'", function(str)
        local decoded = self:decode_octal(str)
        decoded = self:decode_hex(decoded)
        decoded = self:decode_unicode(decoded)
        if decoded ~= str then
            self.changes = self.changes + 1
            return "'" .. decoded .. "'"
        end
        return "'" .. str .. "'"
    end)
    
    return code
end

-- Remove table unpacking and obfuscation wrappers
function Deobfuscator:simplify_structure(code)
    -- Replace local U={...} style table with cleaner format
    code = code:gsub("local%s+%w+%s*=%s*{(.-)}", function(content)
        if content:match("^%?") then
            self.changes = self.changes + 1
            return "local StringTable = {" .. content .. "}"
        end
        return "local " .. "U" .. " = {" .. content .. "}"
    end)
    
    -- Remove function(...)local U= patterns
    code = code:gsub("function%(%s*%.%.%.%s*%)%s*local", "function() local", 1)
    
    -- Simplify return statements
    code = code:gsub("return%s*%(%s*function%s*%(%s*%.%.%.%s*%)", "return function()")
    
    return code
end

-- Replace obfuscated function calls
function Deobfuscator:decode_function_calls(code)
    -- Replace S(-number) patterns with actual string indices
    code = code:gsub("S%s*%(%s*(-?%d+)%s*%)", function(num)
        self.changes = self.changes + 1
        local idx = tonumber(num)
        if idx then
            return "StringTable[" .. idx .. "]"
        end
        return "S(" .. num .. ")"
    end)
    
    -- Replace _G[...] lookups
    code = code:gsub("_G%s*%[%s*(['\"])([^'\"]*?)%1%s*%]", function(quote, name)
        self.changes = self.changes + 1
        return name
    end)
    
    return code
end

-- Remove junk code blocks
function Deobfuscator:remove_junk_code(code)
    -- Remove if false...end blocks
    code = code:gsub("if%s+false%s+then%s*(.-)%s*end", "")
    
    -- Remove while false...end
    code = code:gsub("while%s+false%s+do%s*(.-)%s*end", "")
    
    -- Remove if true...else...end (keep true block)
    code = code:gsub("if%s+true%s+then%s*(.-)%s*else%s*(.-)%s*end", "%1")
    
    -- Remove dead code patterns
    code = code:gsub("%s*and%s+false%s*", "")
    code = code:gsub("%s*or%s+true%s*", "")
    
    return code
end

-- Simplify arithmetic obfuscation
function Deobfuscator:simplify_arithmetic(code)
    -- Simplify addition/subtraction patterns like (X + (-Y))
    code = code:gsub("(%d+)%s*%+%s*%(%s*%-(%d+)%s*%)", function(a, b)
        self.changes = self.changes + 1
        return tostring(tonumber(a) - tonumber(b))
    end)
    
    -- Simplify (X - (-Y)) to X + Y
    code = code:gsub("(%d+)%s*%-%s*%(%s*%-(%d+)%s*%)", function(a, b)
        self.changes = self.changes + 1
        return tostring(tonumber(a) + tonumber(b))
    end)
    
    -- Simplify (-X + Y) patterns
    code = code:gsub("%(%s*%-(%d+)%s*%+%s*(%d+)%s*%)", function(a, b)
        self.changes = self.changes + 1
        return tostring(tonumber(b) - tonumber(a))
    end)
    
    return code
end

-- Format code with indentation
function Deobfuscator:format_code(code)
    local lines = {}
    local indent = 0
    local indent_keywords = {then=1, do=1, function=1, repeat=1}
    local dedent_keywords = {end=1, until=1, else=1, elseif=1}
    
    for line in code:gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$") or line
        
        -- Check for dedent keywords at start
        for kw in pairs(dedent_keywords) do
            if line:match("^" .. kw .. "%W") then
                indent = math.max(0, indent - 1)
                break
            end
        end
        
        if line ~= "" then
            table.insert(lines, string.rep("  ", indent) .. line)
        end
        
        -- Check for indent keywords at end
        for kw in pairs(indent_keywords) do
            if line:match(kw .. "%s*$") then
                indent = indent + 1
                break
            end
        end
    end
    
    return table.concat(lines, "\n")
end

-- Main deobfuscation pipeline
function Deobfuscator:deobfuscate(code)
    if self.debug then
        print("[*] Starting deobfuscation...")
        print("[*] Original size: " .. #code .. " bytes")
    end
    
    local original_length = #code
    
    -- Pass 1: Extract and decode strings
    if self.debug then print("[+] Pass 1: Decoding strings...") end
    code = self:decode_all_strings(code)
    
    -- Pass 2: Simplify structure
    if self.debug then print("[+] Pass 2: Simplifying structure...") end
    code = self:simplify_structure(code)
    
    -- Pass 3: Decode function calls
    if self.debug then print("[+] Pass 3: Decoding function calls...") end
    code = self:decode_function_calls(code)
    
    -- Pass 4: Remove junk code
    if self.debug then print("[+] Pass 4: Removing junk code...") end
    code = self:remove_junk_code(code)
    
    -- Pass 5: Simplify arithmetic
    if self.debug then print("[+] Pass 5: Simplifying arithmetic...") end
    code = self:simplify_arithmetic(code)
    
    -- Pass 6: Format code
    if self.debug then print("[+] Pass 6: Formatting code...") end
    code = self:format_code(code)
    
    if self.debug then
        print("[*] Deobfuscation complete!")
        print("[*] Final size: " .. #code .. " bytes")
        print("[*] Reduction: " .. math.floor((1 - #code/original_length) * 100) .. "%")
        print("[*] Total changes: " .. self.changes)
    end
    
    return code
end

return Deobfuscator
