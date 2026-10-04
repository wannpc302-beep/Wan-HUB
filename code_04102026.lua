-- ============================================================
--  WAN HUB V3 — FULL VERSION
--  รันตรงได้เลย ไม่ต้องดึงอะไรเพิ่ม
-- ============================================================

local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = players.LocalPlayer
local character, humanoid, HRP

-- รีเฟรชตัวละคร
local function refreshCharacter()
    character = player.Character or player.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    HRP = character:WaitForChild("HumanoidRootPart")
end
refreshCharacter()
player.CharacterAdded:Connect(function() task.wait() refreshCharacter() end)

-- สี
local COLORS = {
    Main = Color3.fromRGB(184, 242, 230),
    Mint = Color3.fromRGB(101, 214, 176),
    LightBlue = Color3.fromRGB(142, 216, 232),
    Soft = Color3.fromRGB(217, 245, 242),
    Working = Color3.fromRGB(245, 215, 122),
    Error = Color3.fromRGB(233, 139, 139),
    Text = Color3.fromRGB(36, 67, 77)
}

-- ลบ UI เก่า
pcall(function()
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, name in ipairs({"WAN_HUB_Notifications", "CopyBuildStatus"}) do
            local old = pg:FindFirstChild(name)
            if old then old:Destroy() end
        end
    end
end)

-- ตัวแปรหลัก
local copyBusy = false
local updateBusy = false
local copyEnabled = true
local selectedPlayer = nil
local statusFrame, statusText, progressFill
local dragging = false, dragStartPos, frameStartPos
local blockData, blocksFolder
local COPY_MAX_ATTEMPTS = 5
local COPY_VERIFY_TIMEOUT = 1.5
local COPY_VERIFY_TOLERANCE = 5
local viewEnabled = false, viewSelectedPlayer = nil, viewConnection = nil
local viewDistance = 18, viewHeight = 6

local function canStartTask() return not copyBusy and not updateBusy end

-- ============================================================
--  การแจ้งเตือน
-- ============================================================
local MAX_NOTIFICATIONS = 3
local activeNotifications, notificationHolder = {}, nil

local function createNotificationHolder()
    if notificationHolder then return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "WAN_HUB_Notifications"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = player:WaitForChild("PlayerGui")
    notificationHolder = Instance.new("Frame")
    notificationHolder.AnchorPoint = Vector2.new(1, 1)
    notificationHolder.Size = UDim2.new(0, 340, 0, 280)
    notificationHolder.Position = UDim2.new(1, -18, 1, -18)
    notificationHolder.BackgroundTransparency = 1
    notificationHolder.Parent = gui
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    layout.Padding = UDim.new(0, 8)
    layout.Parent = notificationHolder
end

local function notifyCustom(title, content, duration, icon)
    createNotificationHolder()
    duration = duration or 3; icon = icon or "ℹ️"
    while #activeNotifications >= MAX_NOTIFICATIONS do
        local oldest = table.remove(activeNotifications, 1)
        if oldest and oldest.Frame then
            TweenService:Create(oldest.Frame, TweenInfo.new(0.18),
                {BackgroundTransparency = 1, Size = UDim2.new(0, 330, 0, 0)}):Play()
            task.wait(0.22); oldest.Frame:Destroy()
        end
    end
    local card = Instance.new("Frame")
    card.Size = UDim2.new(0, 330, 0, 75)
    card.BackgroundColor3 = COLORS.Soft
    card.BackgroundTransparency = 0.05
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", card)
    stroke.Color = COLORS.Mint; stroke.Thickness = 1.2

    local iconLbl = Instance.new("TextLabel", card)
    iconLbl.BackgroundTransparency = 1
    iconLbl.Position = UDim2.new(0, 10, 0, 10)
    iconLbl.Size = UDim2.new(0, 35, 0, 35)
    iconLbl.Font = Enum.Font.GothamBold; iconLbl.TextSize = 22
    iconLbl.Text = icon; iconLbl.TextColor3 = COLORS.Text

    local titleLbl = Instance.new("TextLabel", card)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Position = UDim2.new(0, 50, 0, 8)
    titleLbl.Size = UDim2.new(1, -60, 0, 22)
    titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 14
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Text = title; titleLbl.TextColor3 = COLORS.Text

    local contentLbl = Instance.new("TextLabel", card)
    contentLbl.BackgroundTransparency = 1
    contentLbl.Position = UDim2.new(0, 50, 0, 30)
    contentLbl.Size = UDim2.new(1, -60, 0, 38)
    contentLbl.Font = Enum.Font.Gotham; contentLbl.TextSize = 12
    contentLbl.TextWrapped = true; contentLbl.TextXAlignment = Enum.TextXAlignment.Left
    contentLbl.Text = content; contentLbl.TextColor3 = COLORS.Text

    card.Parent = notificationHolder
    table.insert(activeNotifications, {Frame = card})
    card.Size = UDim2.new(0, 0, 0, 75)
    TweenService:Create(card, TweenInfo.new(0.2), {Size = UDim2.new(0, 330, 0, 75)}):Play()

    task.delay(duration, function()
        for i = #activeNotifications, 1, -1 do
            if activeNotifications[i].Frame == card then table.remove(activeNotifications, i) end
        end
        if card and card.Parent then
            TweenService:Create(card, TweenInfo.new(0.2),
                {BackgroundTransparency = 1, Size = UDim2.new(0, 330, 0, 0)}):Play()
            task.wait(0.22); card:Destroy()
        end
    end)
end

-- ============================================================
--  แถบสถานะ — ลากได้ ปิดได้
-- ============================================================
local function createStatusUI()
    if statusFrame then return end
    statusFrame = Instance.new("Frame")
    statusFrame.Name = "CopyBuildStatus"
    statusFrame.Size = UDim2.new(0, 310, 0, 145)
    statusFrame.Position = UDim2.new(0.5, -155, 0, 80)
    statusFrame.BackgroundColor3 = COLORS.LightBlue
    statusFrame.BackgroundTransparency = 0.05
    statusFrame.Parent = player:WaitForChild("PlayerGui")
    Instance.new("UICorner", statusFrame).CornerRadius = UDim.new(0, 12)

    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 35)
    titleBar.BackgroundColor3 = COLORS.Mint
    titleBar.Parent = statusFrame
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 2.5)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Text = "✕"
    closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 18
    closeBtn.TextColor3 = COLORS.Text
    closeBtn.Parent = titleBar
    closeBtn.MouseButton1Click:Connect(function()
        statusFrame.Visible = not statusFrame.Visible
    end)

    local titleLbl = Instance.new("TextLabel", titleBar)
    titleLbl.Size = UDim2.new(1, -40, 0, 30)
    titleLbl.Position = UDim2.new(0, 12, 0, 2.5)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "WAN HUB V3 — Copy"
    titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 15
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.TextColor3 = COLORS.Text

    statusText = Instance.new("TextLabel", statusFrame)
    statusText.Size = UDim2.new(1, -20, 0, 65)
    statusText.Position = UDim2.new(0, 10, 0, 40)
    statusText.BackgroundTransparency = 1
    statusText.Text = "พร้อมใช้งาน"
    statusText.Font = Enum.Font.Gotham; statusText.TextSize = 13
    statusText.TextWrapped = true
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    statusText.TextColor3 = COLORS.Text

    local barBg = Instance.new("Frame", statusFrame)
    barBg.Size = UDim2.new(1, -20, 0, 14)
    barBg.Position = UDim2.new(0, 10, 1, -24)
    barBg.BackgroundColor3 = COLORS.Soft
    barBg.BackgroundTransparency = 0.3
    Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 7)

    progressFill = Instance.new("Frame", barBg)
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.BackgroundColor3 = COLORS.Mint
    Instance.new("UICorner", progressFill).CornerRadius = UDim.new(0, 7)

    -- ลากได้
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStartPos = input.Position
            frameStartPos = Vector2.new(statusFrame.Position.X.Offset, statusFrame.Position.Y.Offset)
            input:StopPropagation()
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or
           input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - dragStartPos
            statusFrame.Position = UDim2.new(0, frameStartPos.X + d.X, 0, frameStartPos.Y + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local function updateStatus(total, placed, missing, running, phase)
    createStatusUI()
    local pct = total > 0 and math.floor(placed / total * 100.5) or 0
    statusText.Text = ("%s\nทั้งหมด: %d | สำเร็จ: %d | ขาด: %d\nความคืบหน้า: %d%%")
        :format(phase or (running and "กำลังทำงาน..." or "พร้อม"), total, placed, missing, pct)
    progressFill.Size = UDim2.new(math.clamp(pct / 100, 0, 1), 0, 1, 0)
end

-- ============================================================
--  ตรวจสอบรองรับ → ยึด/ปล่อย
-- ============================================================
local function findSupportBlock(destFolder, pos)
    local best, minD = nil, 6
    for _, b in ipairs(destFolder:GetChildren()) do
        if b:IsA("Model") then
            local pp = b:FindFirstChild("PPart")
            if pp and pp:IsA("BasePart") and pp.Anchored then
                local d = (pp.Position - pos).Magnitude
                if d < minD then minD = d; best = b end
            end
        end
    end
    return best
end

local function shouldAnchorBlock(exp, destFolder)
    if exp.Anchored == true then return true, "ยึดตามต้นฉบับ" end
    if exp.Anchored == false then
        local sup = findSupportBlock(destFolder, Vector3.new(exp.Pos.X, exp.Pos.Y - 2.6, exp.Pos.Z))
        if not sup then return true, "ไม่มีรองรับ → ยึดอัตโนมัติ" end
        return false, "มีรองรับ → ปล่อยแรงโน้มถ่วง"
    end
    local sup = findSupportBlock(destFolder, Vector3.new(exp.Pos.X, exp.Pos.Y - 2.6, exp.Pos.Z))
    return not sup, sup and "มีฐานรองรับ" or "ไม่มีฐาน → ยึดอัตโนมัติ"
end

-- ============================================================
--  เครื่องมือและข้อมูลบล็อก
-- ============================================================
local function equipTool(name)
    if not character or not humanoid then refreshCharacter() task.wait(0.1) end
    local t = character:FindFirstChild(name)
    if t then return t end
    local bp = player:FindFirstChildOfClass("Backpack")
    t = bp and bp:FindFirstChild(name)
    if not t then return nil end
    pcall(function() humanoid:EquipTool(t) end)
    for _ = 1, 30 do t = character:FindFirstChild(name) if t then return t end task.wait(0.05) end
    return nil
end

local function setAnchored(block, want)
    local pp = block:FindFirstChild("PPart")
    if not pp or pp.Anchored == want then return true end
    local t = equipTool("PropertiesTool")
    if not t or not t:FindFirstChild("SetPropertieRF") then return false end
    pcall(function() t.SetPropertieRF:InvokeServer("Anchored", {block}) end)
    task.wait(0.06)
    return pp.Anchored == want
end

local function getBlockID(n) return blockData:FindFirstChild(n) and blockData[n].Value or 9 end

local function getPlayerZone(p)
    local tc = p.TeamColor
    for _, v in ipairs(workspace:GetChildren()) do
        local c = v:FindFirstChild("TeamColor")
        if c and c.Value == tc then return v end
    end
    return nil
end

local function cframeKey(cf)
    local x, y, z = cf.Position.X, cf.Position.Y, cf.Position.Z
    local r1, r2, r3 = cf:ToOrientation()
    return ("%.3f|%.3f|%.3f|%.4f|%.4f|%.4f"):format(x, y, z, r1, r2, r3)
end

local function makeKey(n, cf) return n and cf and n .. "|" .. cframeKey(cf) end

local function captureBuild(p)
    local base, destBase = getPlayerZone(p), getPlayerZone(player)
    local folder = blocksFolder:FindFirstChild(p.Name)
    if not folder or not base or not destBase then return {} end
    local res = {}
    for _, b in ipairs(folder:GetChildren()) do
        local pp = b:FindFirstChild("PPart")
        if pp then table.insert(res, {
            Name = b.Name, Pos = destBase.CFrame * base.CFrame:ToObjectSpace(pp.CFrame),
            Relative = destBase, Anchored = pp.Anchored, Size = pp.Size,
            Color = pp.Color, Transparency = pp.Transparency
        }) end
    end
    table.sort(res, function(a, b) return a.Pos.Position.Y < b.Pos.Position.Y end)
    return res
end

local function captureExisting(folder)
    local m = {}
    for _, b in ipairs(folder:GetChildren()) do
        local pp = b:FindFirstChild("PPart")
        if pp then local k = makeKey(b.Name, pp.CFrame) if k then m[k] = true end end
    end
    return m
end

-- ============================================================
--  หาบล็อกสำรอง
-- ============================================================
local function featureScore(exp, b)
    local pp = b:FindFirstChild("PPart")
    if not pp then return math.huge end
    local ds = (pp.Size - (exp.Size or Vector3.one)).Magnitude
    local dc = math.abs(pp.Color.R - (exp.Color.R or 0)) + math.abs(pp.Color.G - (exp.Color.G or 0)) + math.abs(pp.Color.B - (exp.Color.B or 0))
    local da = (exp.Anchored ~= nil and pp.Anchored ~= exp.Anchored) and 0.5 or 0
    return ds + dc * 4 + da
end

local function getFallback(exp, destFolder)
    local bestName, bestS = nil, math.huge
    for _, b in ipairs(destFolder:GetChildren()) do
        if b.Name ~= exp.Name then
            local s = featureScore(exp, b)
            if s < bestS then bestS = s; bestName = b.Name end
        end
    end
    return bestName
end

local function prepareData(exp, destFolder)
    if blockData:FindFirstChild(exp.Name) then return exp end
    local fb = getFallback(exp, destFolder)
    if not fb then return exp end
    local c = {}; for k, v in pairs(exp) do c[k] = v end
    c.Name = fb; c.FallbackFrom = exp.Name
    return c
end

-- ============================================================
--  วางและตรวจสอบ
-- ============================================================
local function placeBlock(exp)
    local t = equipTool("BuildingTool")
    if not t or not t:FindFirstChild("RF") then return false end
    local rel = exp.Relative or getPlayerZone(player)
    if not rel then return false end
    return pcall(function() t.RF:InvokeServer(exp.Name, getBlockID(exp.Name), rel, rel.CFrame:ToObjectSpace(exp.Pos), exp.Anchored, exp.Pos, false) end)
end

local function findPlaced(folder, exp)
    local best, minD = nil, COPY_VERIFY_TOLERANCE
    for _, b in ipairs(folder:GetChildren()) do
        if b.Name == exp.Name then
            local pp = b:FindFirstChild("PPart")
            if pp then local d = (pp.Position - exp.Pos.Position).Magnitude if d < minD then minD = d; best = b end end
        end
    end
    return best
end

local function placeAndVerify(exp, destFolder)
    local data = prepareData(exp, destFolder)
    local anchorNow, reason = shouldAnchorBlock(data, destFolder)
    data.Anchored = anchorNow
    if data.FallbackFrom then
        notifyCustom("🔁 เปลี่ยนบล็อก", ("%s → %s\n(%s)"):format(data.FallbackFrom, data.Name, reason), 3, "🔁")
    else
        notifyCustom("📦 วางบล็อก", data.Name .. ": " .. reason, 2, "📦")
    end
    for att = 1, COPY_MAX_ATTEMPTS do
        if att > 1 then task.wait(0.12 * att) end
        placeBlock(data)
        local stop = os.clock() + COPY_VERIFY_TIMEOUT
        repeat
            local b = findPlaced(destFolder, data)
            if b then setAnchored(b, anchorNow) return b, data end
            task.wait(0.06)
        until os.clock() >= stop
    end
    return nil, data
end

local function customizeBlock(b, exp)
    setAnchored(b, exp.Anchored); task.wait(0.03)
    local t = equipTool("ScalingTool")
    if t and t:FindFirstChild("RF") then pcall(function() t.RF:InvokeServer(b, exp.Size, exp.Pos) end) end
    task.wait(0.03)
    t = equipTool("PaintingTool")
    if t and t:FindFirstChild("RF") then pcall(function() t.RF:InvokeServer({{b, exp.Color}}) end) end
end

-- ============================================================
--  ก๊อปปี้หลัก
-- ============================================================
local function runCopyBuild(targetPlayer)
    refreshCharacter()
    blockData = player:FindFirstChild("Data")
    blocksFolder = workspace:FindFirstChild("Blocks")
    if not blockData or not blocksFolder then
        notifyCustom("❌ ไม่พร้อม", "ไม่พบ Data หรือ Blocks ของเกม", 5, "⚠️")
        return
    end
    if not canStartTask() then notifyCustom("⚠️ ไม่ว่าง", "กำลังทำงานอยู่", 3, "⏳") return end
    if not copyEnabled then notifyCustom("⛔ ปิดระบบ", "เปิดระบบก่อน", 3, "⛔") return end
    if not targetPlayer or targetPlayer == player then notifyCustom("⚠️ เลือกคน", "เลือกผู้เล่นอื่น", 3, "👤") return end
    local destFolder = blocksFolder:FindFirstChild(player.Name)
    if not destFolder then notifyCustom("❌ ไม่พบโฟลเดอร์ของเรา", "", 4, "❌") return end

    copyBusy = true
    notifyCustom("📋 เริ่มก๊อปปี้", "จาก: " .. targetPlayer.DisplayName, 3, "🔍")
    local ok, err = pcall(function()
        local build = captureBuild(targetPlayer)
        if #build == 0 then notifyCustom("⚠️ ไม่มีบล็อก", "", 4, "⚠️") return end
        notifyCustom("📊 ตรวจพบ", #build .. " บล็อก", 3, "📦")
        local existing = captureExisting(destFolder)
        local queue = {}
        for _, e in ipairs(build) do local k = makeKey(e.Name, e.Pos) if k and not existing[k] then table.insert(queue, e) end end
        if #queue == 0 then
            notifyCustom("✅ ตรงกันแล้ว", "ไม่ต้องวางเพิ่ม", 4, "✅")
            updateStatus(#build, #build, 0, false, "เสร็จสิ้น") return
        end
        notifyCustom("🏗️ กำลังวาง", #queue .. " บล็อก", 3, "🔨")
        local placed, failed = 0, {}
        for i, exp in ipairs(queue) do
            local b, data = placeAndVerify(exp, destFolder)
            if b then placed += 1; customizeBlock(b, data) else table.insert(failed, exp) end
            updateStatus(#queue, placed, #failed, true, "กำลังวาง...")
            if i % 8 == 0 then task.wait() end
        end
        if #failed > 0 then
            notifyCustom("🔁 ลองใหม่", #failed .. " บล็อก", 3, "🔄")
            local retry = failed; failed = {}
            for _, exp in ipairs(retry) do
                local b = placeAndVerify(exp, destFolder)
                if b then placed += 1 else table.insert(failed, exp) end
            end
        end
        if #failed == 0 then notifyCustom("✅ สำเร็จ", placed .. " บล็อกครบ", 5, "🎉")
        else notifyCustom("⚠️ เสร็จบางส่วน", "สำเร็จ " .. placed .. " | พลาด " .. #failed, 5, "⚠️") end
        updateStatus(#queue, placed, #failed, false, "เสร็จสิ้น")
    end)
    copyBusy = false
    if not ok then notifyCustom("❌ ผิดพลาด", tostring(err), 5, "❌") end
end

-- ============================================================
--  VIEW กล้อง
-- ============================================================
local function restoreOwnCamera()
    local cam = workspace.CurrentCamera
    if cam and humanoid then cam.CameraType = Enum.CameraType.Custom; cam.CameraSubject = humanoid end
end

local function setViewEnabled(enable)
    viewEnabled = enable
    if viewConnection then viewConnection:Disconnect() end
    if not enable then restoreOwnCamera(); notifyCustom("👁️ ปิด View", "กล้องคืนแล้ว", 3, "⏹️") return end
    if not viewSelectedPlayer then notifyCustom("⚠️ ไม่มีเป้าหมาย", "เลือกผู้เล่นก่อน", 3, "👤") return end
    local cam = workspace.CurrentCamera
    cam.CameraType = Enum.CameraType.Scriptable
    viewConnection = RunService.RenderStepped:Connect(function()
        if not viewEnabled then return end
        local tChar = viewSelectedPlayer.Character
        local root = tChar and tChar:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local focus = root.Position + Vector3.new(0, viewHeight, 0)
        local offset = -root.CFrame.LookVector * viewDistance + Vector3.new(0, viewHeight * 0.35, 0)
        cam.CFrame = CFrame.lookAt(root.Position + offset, focus)
    end)
    notifyCustom("👁️ เปิด View", "ดู: " .. viewSelectedPlayer.DisplayName, 3, "👁️")
end

-- ============================================================
--  เมนู Rayfield
-- ============================================================
local success, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)

if not success or not Rayfield then
    notifyCustom("⚠️ เมนูไม่โหลด", "แต่ระบบทำงานได้", 5, "ℹ️")
else
    local Window = Rayfield:CreateWindow({
        Name = "WAN HUB V3",
        LoadingTitle = "WAN HUB V3",
        Theme = "Ocean",
        ToggleUIKeybind = "G"
    })

    local function getPlayerList()
        local t = {}
        for _, p in ipairs(players:GetPlayers()) do
            if p ~= player then table.insert(t, p.DisplayName .. " (@" .. p.Name .. ")") end
        end
        table.sort(t); return t
    end

    local function findPlayerByDisplay(nameStr)
        local un = nameStr:match("@([%w_]+)%)")
        if un then return players:FindFirstChild(un) end
        for _, p in ipairs(players:GetPlayers()) do
            if p.DisplayName .. " (@" .. p.Name .. ")" == nameStr then return p end
        end
    end

    local copyTab = Window:CreateTab("📋 Copy", "rewind")
    local ddPlayer = copyTab:CreateDropdown({
        Name = "👤 เลือกผู้เล่น",
        Options = getPlayerList(),
        Callback = function(opt)
            selectedPlayer = findPlayerByDisplay(type(opt) == "table" and opt[1] or opt)
        end
    })
    copyTab:CreateButton({Name = "🔄 รีเฟรช", Callback = function() ddPlayer:Refresh(getPlayerList()) end})
    copyTab:CreateToggle({Name = "📋 เปิด/ปิดระบบ", CurrentValue = true, Callback = function(v) copyEnabled = v end})
    copyTab:CreateButton({Name = "📋 Copy Build", Callback = function() runCopyBuild(selectedPlayer) end})

    local viewTab = Window:CreateTab("👁️ View", "eye")
    local ddView = viewTab:CreateDropdown({
        Name = "👤 เลือกผู้เล่น",
        Options = getPlayerList(),
        Callback = function(opt)
            viewSelectedPlayer = findPlayerByDisplay(type(opt) == "table" and opt[1] or opt)
        end
    })
    viewTab:CreateToggle({Name = "👁️ เปิด/ปิด View", Callback = setViewEnabled})
    viewTab:CreateSlider({Name = "📷 ระยะกล้อง", Range = {8, 60}, CurrentValue = 18, Callback = function(v) viewDistance = v end})
    viewTab:CreateSlider({Name = "↕️ ความสูงกล้อง", Range = {-5, 30}, CurrentValue = 6, Callback = function(v) viewHeight = v end})
    viewTab:CreateButton({Name = "🎯 คืนกล้อง", Callback = function() setViewEnabled(false) end})

    players.PlayerAdded:Connect(function(p)
        p.CharacterAdded:Connect(function()
            task.wait(0.3)
            ddPlayer:Refresh(getPlayerList())
            ddView:Refresh(getPlayerList())
        end)
    end)
    players.PlayerRemoving:Connect(function(p)
        if selectedPlayer == p then selectedPlayer = nil end
        if viewSelectedPlayer == p then viewSelectedPlayer = nil setViewEnabled(false) end
        task.wait(0.2)
        ddPlayer:Refresh(getPlayerList())
        ddView:Refresh(getPlayerList())
    end)
end

-- เริ่มทำงาน
notifyCustom("✅ พร้อมใช้งาน", "WAN HUB V3 โหลดเสร็จ — ลากสถานะได้ ปิดได้", 5, "🎉")
updateStatus(0, 0, 0, false, "พร้อมใช้งาน")
