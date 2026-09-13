local Deobfuscator = require("deobfuscator")

-- Example usage of the deobfuscator

local examples = {
    -- Example 1: Octal encoded strings
    [[
    local v1 = "\112\114\105\110\116"
    local v2 = "\72\101\108\108\111"
    _G[v1](v2)
    ]],
    
    -- Example 2: Hex encoded strings
    [[
    local v1 = "\x70\x72\x69\x6e\x74"
    local v2 = "\x48\x65\x6c\x6c\x6f"
    _G[v1](v2)
    ]],
    
    -- Example 3: Function wrapping
    [[
    (function()
        print("Hello World")
    end)()
    ]],
    
    -- Example 4: Mixed obfuscation
    [[
    local lIlIIIlII = "\112\114\105\110\116"
    local v2 = "Hello"
    if true then
        _G[lIlIIIlII](v2)
    else
        print("junk code")
    end
    ]],
}

print("WeAreDev Lua Deobfuscator - Examples\n")

for i, code in ipairs(examples) do
    print(string.rep("=", 80))
    print("Example " .. i .. " - OBFUSCATED:")
    print(string.rep("=", 80))
    print(code)
    
    local deobf = Deobfuscator.new()
    local result = deobf:deobfuscate(code)
    
    print("\nExample " .. i .. " - DEOBFUSCATED:")
    print(string.rep("=", 80))
    print(result)
    print()
end
