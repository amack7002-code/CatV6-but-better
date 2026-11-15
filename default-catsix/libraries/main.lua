-- SLOP AUTH: server login bypassed, premium role set locally
local License = ... or {Key = "_key"}
local vape = shared.vape
local cloneref = cloneref or function(Reference: Instance)
    return Reference
end

getgenv().catuser = "Slop"
getgenv().catrole = "premium"
getgenv().catispremium = true

if License.Callback then
    task.spawn(License.Callback)
end

print("[slop] auth bypassed, premium granted locally")
