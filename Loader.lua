--====== WAVE CLIENT v3 - MAX PvP EDITION ======--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
 
--====== AYARLAR VE KONTROLLER ======--
local Config = {
    AimbotEnabled = true,
    ToggleKey = Enum.KeyCode.F4,       -- Menü gizleme/açma tuşu
    AimbotKey = Enum.KeyCode.E,
    AimbotKeyEnabled = false,
 
    -- PvP Ayarları
    KillAuraEnabled = true,
    ReachDistance = 16,                -- Reach / Vuruş Menzili (Max 16 önerilir)
    HitCooldown = 0.01,
    WallCheck = false,                 -- PvP modunda duvar arkası vurma açık kalması için false default
    WallPadding = 1.5,
 
    -- Target Strafe Ayarları
    TargetStrafe = true,               -- Adamın etrafında dönme
    StrafeRadius = 4.5,                -- Çemberin genişliği (Mesafe)
    StrafeSpeed = 12,                  -- Dönüş hızı
    StrafeHeight = 0,                  -- Dönüş yüksekliği zıplama payı
 
    -- FOV & ESP
    UseFOV = false,
    FOVRadius = 150,
    EspEnabled = false,
 
    -- Arkadaş Listesi
    Friends = {}
}
 
--====== DEĞİŞKENLER ======--
local lastHit = 0
local velHistory = {}
local VEL_HISTORY_SIZE = 6
local MAX_PREDICT_TIME = 0.15
local currentTarget = nil
local targetLockTime = 0
local targetKeyHolding = false
local strafeAngle = 0
 
--====== FOV VE 3D LINE ÇİZİCİLER ======--
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 1.5
FOVCircle.Color = Color3.fromRGB(0, 255, 150)
FOVCircle.Filled = false
FOVCircle.Transparency = 1
FOVCircle.Visible = false
 
-- 3D Target Çember Çizgileri (Part tabanlı performans optimizasyonlu render)
local VisualCircleParts = {}
local function clearVisualCircle()
    for _, part in ipairs(VisualCircleParts) do part:Destroy() end
    table.clear(VisualCircleParts)
end
 
local function draw3DCircle(position, radius)
    clearVisualCircle()
    if not Config.TargetStrafe or not currentTarget then return end
 
    local segments = 16
    for i = 1, segments do
        local angle1 = (i / segments) * math.pi * 2
        local angle2 = ((i + 1) / segments) * math.pi * 2
 
        local p1 = position + Vector3.new(math.cos(angle1) * radius, -2.5, math.sin(angle1) * radius)
        local p2 = position + Vector3.new(math.cos(angle2) * radius, -2.5, math.sin(angle2) * radius)
 
        local dist = (p1 - p2).Magnitude
        local part = Instance.new("Part")
        part.Anchored = true
        part.CanCollide = false
        part.Size = Vector3.new(0.1, 0.1, dist)
        part.CFrame = CFrame.new(p1:Lerp(p2, 0.5), p2)
        part.Color = Color3.fromRGB(0, 255, 150) -- Neon Yeşil Çember
        part.Material = Enum.Material.Neon
        part.Parent = Workspace
        table.insert(VisualCircleParts, part)
    end
end
 
--====== YARDIMCI FONKSİYONLAR ======--
local function getChar(plr) return plr.Character end
local function getHum(plr)
    local c = getChar(plr)
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end
local function isAlive(plr)
    local hum = getHum(plr)
    return hum and hum.Health > 0
end
local function getHitbox(plr)
    local c = getChar(plr)
    if not c then return nil end
    return c:FindFirstChild("PlayerHitbox") or c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head")
end
local function getPos(plr)
    local h = getHitbox(plr)
    return h and h.Position or nil
end
local function getVel(plr)
    local h = getHitbox(plr)
    return h and h.AssemblyLinearVelocity or Vector3.new()
end
local function getMyPos() return getPos(LocalPlayer) end
local function getMyEye()
    local c = getChar(LocalPlayer)
    if not c then return nil end
    return c:FindFirstChild("PlayerEyeLevel") and c.PlayerEyeLevel.Position or getMyPos()
end
 
local function isFriend(plr)
    return table.find(Config.Friends, plr.Name) ~= nil
end
 
--====== KILL AURA SEÇİM MOTORU ======--
local function getTargetScore(plr)
    local myPos = getMyPos()
    if not myPos or not isAlive(plr) or isFriend(plr) then return -10000 end
 
    local pos = getPos(plr)
    if not pos then return -10000 end
 
    local dist = (pos - myPos).Magnitude
    if dist > Config.ReachDistance then return -10000 end
 
    if Config.UseFOV then
        local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
        if not onScreen then return -10000 end
        local mousePos = UserInputService:GetMouseLocation()
        local fovDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
        if fovDist > Config.FOVRadius then return -10000 end
    end
 
    local score = 1000 - dist -- Yakın olana öncelik ver (Menzil içi)
    if currentTarget == plr then score = score + 200 end -- Hedef kilit koruması
    return score
end
 
local function findBestTarget()
    local best, bestScore = nil, -10000
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local score = getTargetScore(plr)
            if score > bestScore then
                bestScore = score
                best = plr
            end
        end
    end
    return best
end
 
--====== HIT MOTORU ======--
local function executeAttack(target)
    local eye = getMyEye()
    local targetPos = getPos(target)
    if not eye or not targetPos then return false end
 
    local dir = (targetPos - eye).Unit
    local hr = game.ReplicatedStorage:FindFirstChild("Remotes") and game.ReplicatedStorage.Remotes:FindFirstChild("HitRequest")
    local ar = game.ReplicatedStorage:FindFirstChild("Remotes") and game.ReplicatedStorage.Remotes:FindFirstChild("AnimateHit")
 
    if hr then
        hr:FireServer(eye, dir, target)
        if ar then ar:FireServer() end
        return true
    end
    return false
end
 
--====== TARGET STRAFE MOTORU ======--
local function handleTargetStrafe(target)
    if not Config.TargetStrafe or not target then return end
    local myChar = getChar(LocalPlayer)
    local myHrp = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("PlayerHitbox"))
    local targetHrp = getHitbox(target)
 
    if myHrp and targetHrp then
        strafeAngle = strafeAngle + (Config.StrafeSpeed / 100)
        local offset = Vector3.new(math.cos(strafeAngle) * Config.StrafeRadius, Config.StrafeHeight, math.sin(strafeAngle) * Config.StrafeRadius)
        local targetGoal = targetHrp.Position + offset
 
        -- Karakteri pürüzsüzce hedefin etrafına taşı
        myHrp.CFrame = CFrame.new(targetGoal, targetHrp.Position)
    end
end
 
--====== ESP SİSTEMİ ======--
local function createEsp(plr)
    if plr == LocalPlayer then return end
    local highlight = Instance.new("Highlight")
    highlight.Name = "Esp_Highlight"
    highlight.FillColor = Color3.fromRGB(255, 0, 50)
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
 
    local function apply() if plr.Character then highlight.Parent = plr.Character end end
    apply()
    plr.CharacterAdded:Connect(apply)
end
for _, p in ipairs(Players:GetPlayers()) do createEsp(p) end
Players.PlayerAdded:Connect(createEsp)
 
RunService.RenderStepped:Connect(function()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and p.Character:FindFirstChild("Esp_Highlight") then
            p.Character.Esp_Highlight.Enabled = Config.EspEnabled and isAlive(p) and not isFriend(p)
            if isFriend(p) and Config.EspEnabled then
                p.Character.Esp_Highlight.Enabled = true
                p.Character.Esp_Highlight.FillColor = Color3.fromRGB(0, 255, 100)
            elseif not isFriend(p) and Config.EspEnabled then
                p.Character.Esp_Highlight.FillColor = Color3.fromRGB(255, 0, 50)
            end
        end
    end
end)
 
--====== MENÜ (GUI) TASARIMI ======--
local ScreenGui = Instance.new("ScreenGui", game.CoreGui)
ScreenGui.ResetOnSpawn = false
 
local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 420, 0, 480)
MainFrame.Position = UDim2.new(0.35, 0, 0.2, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
 
local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, 0, 0, 40)
Title.Text = "WAVE CLIENT v3 - RAGE PVP"
Title.TextColor3 = Color3.fromRGB(0, 255, 150)
Title.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
 
local Container = Instance.new("ScrollingFrame", MainFrame)
Container.Size = UDim2.new(1, -20, 1, -60)
Container.Position = UDim2.new(0, 10, 0, 50)
Container.BackgroundTransparency = 1
Container.CanvasSize = UDim2.new(0, 0, 0, 500)
Container.ScrollBarThickness = 4
local UIList = Instance.new("UIListLayout", Container)
UIList.Padding = UDim.new(0, 8)
 
local function createToggle(text, startState, callback)
    local frame = Instance.new("Frame", Container)
    frame.Size = UDim2.new(1, 0, 0, 40)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
 
    local label = Instance.new("TextLabel", frame)
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Text = text
    label.TextColor3 = Color3.fromRGB(230, 230, 230)
    label.Font = Enum.Font.Gotham
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.BackgroundTransparency = 1
 
    local btn = Instance.new("TextButton", frame)
    btn.Size = UDim2.new(0, 60, 0, 24)
    btn.Position = UDim2.new(1, -70, 0, 8)
    btn.Text = startState and "ON" or "OFF"
    btn.BackgroundColor3 = startState and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(200, 50, 50)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
 
    btn.MouseButton1Click:Connect(function()
        startState = not startState
        btn.Text = startState and "ON" or "OFF"
        btn.BackgroundColor3 = startState and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(200, 50, 50)
        callback(startState)
    end)
end
 
createToggle("KillAura & Reach", Config.KillAuraEnabled, function(v) Config.KillAuraEnabled = v end)
createToggle("Target Strafe (Etrafında Dönme)", Config.TargetStrafe, function(v) Config.TargetStrafe = v end)
createToggle("Wall Check", Config.WallCheck, function(v) Config.WallCheck = v end)
createToggle("Görsel ESP", Config.EspEnabled, function(v) Config.EspEnabled = v end)
 
-- Arkadaş Ekleme Frame
local FriendFrame = Instance.new("Frame", Container)
FriendFrame.Size = UDim2.new(1, 0, 0, 50)
FriendFrame.BackgroundTransparency = 1
 
local FriendInput = Instance.new("TextBox", FriendFrame)
FriendInput.Size = UDim2.new(0.65, 0, 0, 35)
FriendInput.Position = UDim2.new(0, 0, 0, 5)
FriendInput.PlaceholderText = "Arkadaş Username..."
FriendInput.Text = ""
FriendInput.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
FriendInput.TextColor3 = Color3.fromRGB(255, 255, 255)
FriendInput.Font = Enum.Font.Gotham
FriendInput.TextSize = 13
Instance.new("UICorner", FriendInput).CornerRadius = UDim.new(0, 5)
 
local FriendBtn = Instance.new("TextButton", FriendFrame)
FriendBtn.Size = UDim2.new(0.3, 0, 0, 35)
FriendBtn.Position = UDim2.new(0.7, 0, 0, 5)
FriendBtn.Text = "Ekle/Sil"
FriendBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
FriendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FriendBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", FriendBtn).CornerRadius = UDim.new(0, 5)
 
FriendBtn.MouseButton1Click:Connect(function()
    local name = FriendInput.Text
    if name ~= "" then
        local found = table.find(Config.Friends, name)
        if found then
            table.remove(Config.Friends, found)
            FriendBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        else
            table.insert(Config.Friends, name)
            FriendBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
        end
        task.wait(0.4)
        FriendBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
        FriendInput.Text = ""
    end
end)
 
--====== ANA DÖNGÜ (PvP HEARTBEAT) ======--
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Config.ToggleKey then MainFrame.Visible = not MainFrame.Visible end
    if input.KeyCode == Config.AimbotKey then targetKeyHolding = true end
end)
UserInputService.InputEnded:Connect(function(input, gpe)
    if input.KeyCode == Config.AimbotKey then targetKeyHolding = false end
end)
 
RunService.Heartbeat:Connect(function()
    if not Config.KillAuraEnabled then 
        currentTarget = nil 
        clearVisualCircle()
        return 
    end
    if Config.AimbotKeyEnabled and not targetKeyHolding then 
        currentTarget = nil 
        clearVisualCircle()
        return 
    end
 
    local char = getChar(LocalPlayer)
    if not char or not isAlive(LocalPlayer) then 
        clearVisualCircle()
        return 
    end
 
    local target = findBestTarget()
    if not target then
        currentTarget = nil
        clearVisualCircle()
        return
    end
 
    currentTarget = target
 
    -- Target Strafe Aktif Etme ve Çember Çizme
    local targetPos = getPos(currentTarget)
    if targetPos then
        handleTargetStrafe(currentTarget)
        draw3DCircle(targetPos, Config.StrafeRadius)
    else
        clearVisualCircle()
    end
 
    -- Otomatik Kamera Odaklanması (İsteğe bağlı pürüzsüz kilit)
    local targetHrp = getHitbox(currentTarget)
    if targetHrp then
        local targetCF = CFrame.new(Camera.CFrame.Position, targetHrp.Position)
        Camera.CFrame = Camera.CFrame:Lerp(targetCF, 0.20)
    end
 
    -- Saniyede Onlarca Kez Vuran KillAura Reach Döngüsü
    local now = tick()
    if now - lastHit >= Config.HitCooldown then
        if executeAttack(currentTarget) then
            lastHit = now
        end
    end
end)
 
-- Resetler
LocalPlayer.CharacterAdded:Connect(function()
    lastHit = 0
    currentTarget = nil
    clearVisualCircle()
end)
