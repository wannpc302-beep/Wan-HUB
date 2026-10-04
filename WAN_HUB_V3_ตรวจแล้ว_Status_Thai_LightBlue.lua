-- ============================================================
--  WAN HUB V3 — ตรวจแก้แล้ว
--  ระบบ View ไม่แก้ความเร็ว | หาบล็อกใกล้เคียงแทนอัตโนมัติ
--  เพิ่ม: สถานะภาษาไทย + อีโมจิเครื่องมือ + รายชื่อบล็อกที่ขาด
--  แก้: scope ของ equipTool, ddView, การ retry, Status GUI
-- ============================================================

local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local player = players.LocalPlayer
local character, humanoid, HRP

local function refreshCharacter()
    character = player.Character or player.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    HRP = character:WaitForChild("HumanoidRootPart")
end
refreshCharacter()
player.CharacterAdded:Connect(function() task.wait() refreshCharacter() end)

local COLORS = {
    Main = Color3.fromRGB(184, 242, 230),
    Mint = Color3.fromRGB(101, 214, 176),
    LightBlue = Color3.fromRGB(142, 216, 232),
    Soft = Color3.fromRGB(217, 245, 242),
    Working = Color3.fromRGB(245, 215, 122),
    Error = Color3.fromRGB(233, 139, 139),
    Text = Color3.fromRGB(36, 67, 77)
}

-- ============================================================
--  STATE SYSTEM
-- ============================================================
local copyBusy = false
local updateBusy = false
local copyEnabled = true
local knownBlocks = {}

local function canStartTask()
    return not copyBusy and not updateBusy
end

-- ลบ UI จากรอบเก่าถ้ามี เพื่อป้องกันหน้าต่างซ้อน
pcall(function()
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if pg then
        local oldNotif = pg:FindFirstChild("WAN_HUB_Notifications")
        if oldNotif then oldNotif:Destroy() end
        local oldStatus = pg:FindFirstChild("WAN_HUB_V3_Status")
        if oldStatus then oldStatus:Destroy() end
    end
end)

-- ============================================================
--  NOTIFICATION — แจ้งเตือนอัตโนมัติทุกขั้นตอน
-- ============================================================
local MAX_NOTIFICATIONS = 3
local activeNotifications = {}
local notificationHolder = nil
local notificationCounter = 0

local function createNotificationHolder()
    if notificationHolder and notificationHolder.Parent then return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "WAN_HUB_Notifications"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = player:WaitForChild("PlayerGui")
    notificationHolder = Instance.new("Frame")
    notificationHolder.Name = "Holder"
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
    duration = duration or 3
    icon = icon or "ℹ️"
    if #activeNotifications >= MAX_NOTIFICATIONS then
        local oldest = table.remove(activeNotifications, 1)
        if oldest and oldest.Frame and oldest.Frame.Parent then
            task.spawn(function()
                TweenService:Create(oldest.Frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad),
                    {BackgroundTransparency = 1, Size = UDim2.new(0, 330, 0, 0)}):Play()
                task.wait(0.2)
                oldest.Frame:Destroy()
            end)
        end
    end
    notificationCounter += 1
    local card = Instance.new("Frame")
    card.Name = "Notif_"..notificationCounter
    card.Size = UDim2.new(0, 330, 0, 75)
    card.BackgroundColor3 = COLORS.Soft
    card.BackgroundTransparency = 0.05
    card.LayoutOrder = notificationCounter
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
            if activeNotifications[i].Frame == card then table.remove(activeNotifications, i) break end
        end
        if card and card.Parent then
            TweenService:Create(card, TweenInfo.new(0.2), {BackgroundTransparency = 1, Size = UDim2.new(0, 330, 0, 0)}):Play()
            task.wait(0.22); card:Destroy()
        end
    end)
end

-- ============================================================
--  GRAVITY SYSTEM — กันบล็อกตกอัตโนมัติ
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

local function shouldAnchor(expected, destFolder)
    if expected.Anchored == true then return true, "ยึดตามต้นฉบับ" end
    if expected.Anchored == false then
        local below = Vector3.new(expected.Pos.X, expected.Pos.Y - 2.6, expected.Pos.Z)
        local sup = findSupportBlock(destFolder, below)
        if not sup then return true, "ไม่มีรองรับ → ยึดอัตโนมัติ" end
        return false, "มีรองรับ → ปล่อยแรงโน้มถ่วง"
    end
    local below = Vector3.new(expected.Pos.X, expected.Pos.Y - 2.6, expected.Pos.Z)
    local sup = findSupportBlock(destFolder, below)
    return not sup, sup and "มีฐานรองรับ" or "ไม่มีฐาน → ยึดอัตโนมัติ"
end

local equipTool

local function setAnchored(block, want)
    local pp = block and block:FindFirstChild("PPart")
    if not pp or pp.Anchored == want then return true end

    local t = equipTool and equipTool("PropertiesTool")
    if not t or not t:FindFirstChild("SetPropertieRF") then
        return false
    end

    local ok = pcall(function()
        t.SetPropertieRF:InvokeServer("Anchored", {block})
    end)
    if not ok then
        return false
    end

    task.wait(0.06)
    return pp.Anchored == want
end

-- ============================================================
--  COPY SYSTEM
-- ============================================================
local blockData = player:WaitForChild("Data")
local blocksFolder = workspace:WaitForChild("Blocks")
local selectedPlayer = nil
local COPY_MAX_ATTEMPTS = 5
local COPY_VERIFY_TIMEOUT = 1.5
local COPY_VERIFY_TOLERANCE = 5
local COPY_BATCH_YIELD = 8

equipTool = function(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not character or not humanoid then
        refreshCharacter()
        task.wait(0.1)
    end

    local t = character:FindFirstChild(name)
    if t then return t end

    local bp = player:FindFirstChildOfClass("Backpack")
    t = bp and bp:FindFirstChild(name)
    if not t then return nil end

    pcall(function()
        humanoid:EquipTool(t)
    end)

    for _ = 1, 30 do
        t = character:FindFirstChild(name)
        if t then return t end
        task.wait(0.05)
    end

    return nil
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

local function getSourceFolder(p) return blocksFolder:FindFirstChild(p.Name) end

local function cframeKey(cf)
    local x,y,z = cf.Position.X, cf.Position.Y, cf.Position.Z
    local r1,r2,r3 = cf:ToOrientation()
    return ("%.3f|%.3f|%.3f|%.4f|%.4f|%.4f"):format(x,y,z,r1,r2,r3)
end

local function makeKey(n, cf) return n and cf and n.."|"..cframeKey(cf) or nil end

local function captureBuild(p)
    local base = getPlayerZone(p)
    local destBase = getPlayerZone(player)
    local folder = getSourceFolder(p)
    if not folder or not base or not destBase then return {} end
    local res = {}
    for _, b in ipairs(folder:GetChildren()) do
        local pp = b:FindFirstChild("PPart")
        if b:IsA("Model") and pp then
            table.insert(res, {
                Name = b.Name,
                Pos = destBase.CFrame * base.CFrame:ToObjectSpace(pp.CFrame),
                Relative = destBase,
                Anchored = pp.Anchored,
                Size = pp.Size,
                Color = pp.Color,
                Transparency = pp.Transparency,
                Source = b
            })
        end
    end
    table.sort(res, function(a,b) return a.Pos.Position.Y < b.Pos.Position.Y end)
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

local function featureScore(exp, b)
    local pp = b:FindFirstChild("PPart")
    if not pp then return math.huge end
    local ds = (pp.Size - (exp.Size or Vector3.one)).Magnitude
    local dc = math.abs(pp.Color.R-(exp.Color and exp.Color.R or 0))
        + math.abs(pp.Color.G-(exp.Color and exp.Color.G or 0))
        + math.abs(pp.Color.B-(exp.Color and exp.Color.B or 0))
    local da = (exp.Anchored~=nil and pp.Anchored~=exp.Anchored) and 0.5 or 0
    return ds + dc*4 + da
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
    if not exp then return exp end
    if blockData:FindFirstChild(exp.Name) then return exp end
    local fb = getFallback(exp, destFolder)
    if not fb then return exp end
    local c = {}; for k,v in pairs(exp) do c[k]=v end
    c.Name = fb; c.FallbackFrom = exp.Name
    return c
end

local function placeBlock(exp)
    if not exp or not exp.Name then return false end

    setCurrentAction("กำลังวางบล็อก", "BuildingTool", exp.Name)

    local t = equipTool("BuildingTool")
    if not t or not t:FindFirstChild("RF") then
        return false
    end
    local rel = exp.Relative or getPlayerZone(player)
    if not rel then return false end
    local ok = pcall(function()
        t.RF:InvokeServer(exp.Name, getBlockID(exp.Name), rel,
            rel.CFrame:ToObjectSpace(exp.Pos), exp.Anchored, exp.Pos, false)
    end)
    return ok
end

local function findPlaced(folder, exp)
    local best, minD = nil, COPY_VERIFY_TOLERANCE
    for _, b in ipairs(folder:GetChildren()) do
        if b.Name == exp.Name then
            local pp = b:FindFirstChild("PPart")
            if pp then
                local d = (pp.Position - exp.Pos.Position).Magnitude
                if d < minD then minD = d; best = b end
            end
        end
    end
    return best
end

local function placeAndVerify(exp, destFolder)
    local data = prepareData(exp, destFolder)
    local anchorNow, reason = shouldAnchor(data, destFolder)
    data.Anchored = anchorNow
    if data.FallbackFrom then
        notifyCustom("🔁 เปลี่ยนบล็อก", ("%s → %s\n(%s)"):format(data.FallbackFrom, data.Name, reason), 3, "🔁")
    else
        notifyCustom("📦 วางบล็อก", data.Name..": "..reason, 2, "📦")
    end
    for att = 1, COPY_MAX_ATTEMPTS do
        if att > 1 then task.wait(0.12*att) end
        placeBlock(data)
        local stop = os.clock() + COPY_VERIFY_TIMEOUT
        repeat
            local b = findPlaced(destFolder, data)
            if b then
                setAnchored(b, anchorNow)
                return b, data
            end
            task.wait(0.06)
        until os.clock() >= stop
    end
    return nil, data
end

local TOOL_INFO = {
    BuildingTool = {Emoji = "🔨", Name = "BuildingTool", Action = "กำลังวางบล็อก"},
    ScalingTool = {Emoji = "📏", Name = "ScalingTool", Action = "กำลังปรับขนาด"},
    PaintingTool = {Emoji = "🎨", Name = "PaintingTool", Action = "กำลังระบายสี"},
    PropertiesTool = {Emoji = "⚙️", Name = "PropertiesTool", Action = "กำลังตั้งค่า"},
}

local currentAction = "พร้อมใช้งาน"
local currentTool = nil
local currentBlock = nil
local currentMissingNames = {}

local function setCurrentAction(action, toolName, blockName, missingNames)
    currentAction = action or "กำลังทำงาน..."
    currentTool = TOOL_INFO[toolName]
    currentBlock = blockName
    if missingNames then
        currentMissingNames = table.clone(missingNames)
    end
end

local function makeMissingText(names)
    if not names or #names == 0 then
        return "✅ ไม่มีบล็อกที่ขาด"
    end

    local maxShow = 6
    local shown = {}
    local seen = {}

    for _, name in ipairs(names) do
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(shown, name)
            if #shown >= maxShow then break end
        end
    end

    local extra = 0
    for _, name in ipairs(names) do
        if name and name ~= "" and not seen[name] then
            extra += 1
        end
    end

    local result = table.concat(shown, ", ")
    if extra > 0 then
        result ..= (" … +%d รายการ"):format(extra)
    end
    return result
end

local copyStatus = {
    total = 0,
    placed = 0,
    missing = 0,
    running = false
}
local statusGui, statusFrame, statusText, progressFill

local function createStatusUI()
    if statusFrame and statusFrame.Parent then return end

    local old = player:WaitForChild("PlayerGui"):FindFirstChild("WAN_HUB_V3_Status")
    if old then old:Destroy() end

    statusGui = Instance.new("ScreenGui")
    statusGui.Name = "WAN_HUB_V3_Status"
    statusGui.ResetOnSpawn = false
    statusGui.IgnoreGuiInset = true
    statusGui.DisplayOrder = 20
    statusGui.Parent = player.PlayerGui

    statusFrame = Instance.new("Frame")
    statusFrame.Size = UDim2.new(0, 340, 0, 205)
    statusFrame.Position = UDim2.new(0.5, -170, 0, 70)
    statusFrame.BackgroundColor3 = COLORS.LightBlue
    statusFrame.BackgroundTransparency = 0.04
    statusFrame.Parent = statusGui

    Instance.new("UICorner", statusFrame).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke", statusFrame)
    stroke.Color = COLORS.Main
    stroke.Thickness = 1.4
    stroke.Transparency = 0.05

    local title = Instance.new("TextLabel", statusFrame)
    title.Size = UDim2.new(1, -20, 0, 30)
    title.Position = UDim2.new(0, 10, 0, 8)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "WAN HUB V3 — สถานะ Copy"
    title.TextColor3 = COLORS.Text

    statusText = Instance.new("TextLabel", statusFrame)
    statusText.Size = UDim2.new(1, -20, 0, 125)
    statusText.Position = UDim2.new(0, 10, 0, 40)
    statusText.BackgroundTransparency = 1
    statusText.Font = Enum.Font.Gotham
    statusText.TextSize = 12
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    statusText.TextYAlignment = Enum.TextYAlignment.Top
    statusText.TextWrapped = true
    statusText.RichText = false
    statusText.Text = "พร้อมใช้งาน"
    statusText.TextColor3 = COLORS.Text

    local bar = Instance.new("Frame", statusFrame)
    bar.Size = UDim2.new(1, -20, 0, 14)
    bar.Position = UDim2.new(0, 10, 1, -24)
    bar.BackgroundColor3 = COLORS.Soft
    bar.BackgroundTransparency = 0.1
    bar.ClipsDescendants = true
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 7)

    progressFill = Instance.new("Frame", bar)
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.BackgroundColor3 = COLORS.Mint
    Instance.new("UICorner", progressFill).CornerRadius = UDim.new(0, 7)
end

local function updateStatus(total, placed, missing, running, phase, missingNames)
    createStatusUI()

    copyStatus.total = math.max(0, tonumber(total) or 0)
    copyStatus.placed = math.max(0, tonumber(placed) or 0)
    copyStatus.missing = math.max(0, tonumber(missing) or 0)
    copyStatus.running = running == true

    if missingNames then
        currentMissingNames = table.clone(missingNames)
    end

    local pct = copyStatus.total > 0
        and math.clamp(math.floor((copyStatus.placed / copyStatus.total) * 100 + 0.5), 0, 100)
        or 0

    local phaseText = phase or (running and "กำลังทำงาน..." or "พร้อมใช้งาน")
    local actionText = currentAction or phaseText

    if currentTool then
        actionText = ("%s\n%s %s"):format(
            actionText,
            currentTool.Emoji,
            currentTool.Action
        )
        if currentBlock and currentBlock ~= "" then
            actionText ..= " → " .. currentBlock
        end
    end

    local missingText
    if copyStatus.missing > 0 then
        missingText = ("ขาด %d บล็อก: %s"):format(
            copyStatus.missing,
            makeMissingText(currentMissingNames)
        )
    else
        missingText = "ขาด 0 บล็อก"
    end

    statusText.Text = ("%s\nทั้งหมด: %d | สำเร็จ: %d\n%s\nความคืบหน้า: %d%%")
        :format(
            actionText,
            copyStatus.total,
            copyStatus.placed,
            missingText,
            pct
        )

    progressFill.Size = UDim2.new(pct / 100, 0, 1, 0)
end

local function runCopyBuild(targetPlayer)
    refreshCharacter()

    if not canStartTask() then
        notifyCustom("⚠️ ไม่ว่าง", "กำลังทำงานอยู่ รอสักครู่", 3, "⏳")
        return
    end

    if not copyEnabled then
        notifyCustom("⛔ ปิดระบบ", "เปิดระบบก่อน", 3, "⛔")
        return
    end

    if not targetPlayer or not targetPlayer.Parent or targetPlayer == player then
        notifyCustom("⚠️ เลือกคน", "เลือกผู้เล่นอื่นก่อน", 3, "👤")
        return
    end

    local destFolder = blocksFolder:FindFirstChild(player.Name)
    if not destFolder then
        notifyCustom("❌ ไม่พบ", "ไม่พบโฟลเดอร์ของเรา", 4, "❌")
        return
    end

    copyBusy = true
    currentMissingNames = {}
    setCurrentAction("กำลังอ่านแบบสร้าง", nil, nil)
    notifyCustom("📋 เริ่มก๊อปปี้", "กำลังอ่านข้อมูลจาก: "..targetPlayer.DisplayName, 3, "🔍")

    local ok, err = pcall(function()
        local build = captureBuild(targetPlayer)
        if #build == 0 then
            notifyCustom("⚠️ ไม่มี", "ไม่พบบล็อกที่คัดลอกได้", 4, "⚠️")
            updateStatus(0, 0, 0, false, "ไม่พบบล็อก")
            return
        end

        notifyCustom("📊 ตรวจพบ", "พบ "..#build.." บล็อก", 3, "📦")

        setCurrentAction("กำลังตรวจสอบบล็อกที่มีอยู่", nil, nil)

        local existing = captureExisting(destFolder)
        local queue = {}

        for _, e in ipairs(build) do
            local k = makeKey(e.Name, e.Pos)
            if k and not existing[k] then
                table.insert(queue, {
                    data = e,
                    key = k
                })
            end
        end

        local function getMissingNames(items)
            local names = {}
            for _, item in ipairs(items) do
                if item and item.data and item.data.Name then
                    table.insert(names, item.data.Name)
                end
            end
            return names
        end

        if #queue == 0 then
            setCurrentAction("เสร็จสิ้น", nil, nil, {})
            notifyCustom("✅ ตรงกัน", "บล็อกครบถ้วนแล้ว ไม่ต้องวางเพิ่ม", 4, "✅")
            updateStatus(#build, #build, 0, false, "เสร็จสิ้น", {})
            knownBlocks = existing
            return
        end

        local missingNames = getMissingNames(queue)
        currentMissingNames = missingNames

        notifyCustom("🏗️ กำลังวาง", "ต้องวาง "..#queue.." บล็อก", 3, "🔨")

        local placed = 0
        local failed = {}

        updateStatus(#queue, placed, #queue, true, "กำลังเตรียมวาง...", missingNames)

        for i, item in ipairs(queue) do
            local b, data = placeAndVerify(item.data, destFolder)

            if b then
                placed += 1
                existing[item.key] = true
                customizeBlock(b, data)
            else
                table.insert(failed, item)
            end

            local remaining = getMissingNames(failed)
            setCurrentAction(
                b and "กำลังจัดรูปแบบบล็อก" or "วางไม่สำเร็จ",
                b and "PaintingTool" or "BuildingTool",
                data and data.Name or item.data.Name,
                remaining
            )
            updateStatus(#queue, placed, #failed, true, b and "กำลังทำงาน..." or "พบรายการที่ต้องลองใหม่", remaining)

            if i % COPY_BATCH_YIELD == 0 then
                task.wait()
            end
        end

        if #failed > 0 then
            local retry = failed
            failed = {}

            notifyCustom("🔁 ลองใหม่", "ลองวางซ้ำ "..#retry.." บล็อก", 3, "🔄")

            local retryNames = getMissingNames(retry)
            updateStatus(#queue, placed, #retry, true, "กำลังลองใหม่...", retryNames)

            for i, item in ipairs(retry) do
                local b, data = placeAndVerify(item.data, destFolder)

                if b then
                    placed += 1
                    existing[item.key] = true
                    customizeBlock(b, data)
                else
                    table.insert(failed, item)
                end

                local remaining = getMissingNames(failed)
                setCurrentAction(
                    b and "ลองใหม่สำเร็จ" or "ยังวางไม่สำเร็จ",
                    b and "PaintingTool" or "BuildingTool",
                    (data and data.Name) or item.data.Name,
                    remaining
                )
                updateStatus(#queue, placed, #failed, true, "กำลังลองใหม่...", remaining)

                if i % COPY_BATCH_YIELD == 0 then
                    task.wait()
                end
            end
        end

        knownBlocks = existing

        local finalMissing = getMissingNames(failed)
        currentMissingNames = finalMissing

        if #failed == 0 then
            setCurrentAction("เสร็จสิ้น", nil, nil, {})
            notifyCustom("✅ สำเร็จ", "วางครบทั้ง "..placed.." บล็อก", 5, "🎉")
            updateStatus(#queue, placed, 0, false, "เสร็จสิ้น", {})
        else
            setCurrentAction("เสร็จบางส่วน", nil, nil, finalMissing)
            notifyCustom(
                "⚠️ เสร็จบางส่วน",
                ("สำเร็จ %d | ขาด %d"):format(placed, #failed),
                5,
                "⚠️"
            )
            updateStatus(#queue, placed, #failed, false, "เสร็จบางส่วน", finalMissing)
        end
    end)

    copyBusy = false

    if not ok then
        currentMissingNames = {}
        setCurrentAction("เกิดข้อผิดพลาด", nil, nil, {})
        notifyCustom("❌ ผิดพลาด", tostring(err), 5, "❌")
        updateStatus(0, 0, 0, false, "เกิดข้อผิดพลาด", {})
    end
end

local function runUpdateBuild()
    refreshCharacter()

    if not canStartTask() then
        notifyCustom("⚠️ ไม่ว่าง", "กำลังทำงานอยู่", 3, "⏳")
        return
    end

    if not copyEnabled then
        notifyCustom("⛔ ปิดระบบ", "เปิดระบบก่อน", 3, "⛔")
        return
    end

    if not selectedPlayer or not selectedPlayer.Parent then
        notifyCustom("⚠️ ไม่มีเป้าหมาย", "เลือกผู้เล่นก่อน", 3, "👤")
        return
    end

    local destFolder = blocksFolder:FindFirstChild(player.Name)
    if not destFolder then
        notifyCustom("❌ ไม่พบ", "ไม่พบโฟลเดอร์ของเรา", 4, "❌")
        return
    end

    copyBusy = true
    updateBusy = true
    currentMissingNames = {}
    setCurrentAction("กำลังเปรียบเทียบงานสร้าง", nil, nil)
    notifyCustom("➕ เริ่มอัปเดต", "เปรียบเทียบกับ: "..selectedPlayer.DisplayName, 3, "🔍")

    local ok, err = pcall(function()
        local build = captureBuild(selectedPlayer)
        local used = {}
        local updateCnt, addCnt, failCnt = 0, 0, 0
        local failedNames = {}

        if #build == 0 then
            notifyCustom("⚠️ ไม่มี", "ไม่พบบล็อกของเป้าหมาย", 4, "⚠️")
            updateStatus(0, 0, 0, false, "ไม่มีข้อมูลสำหรับอัปเดต", {})
            return
        end

        local allBuildNames = {}
        for _, exp in ipairs(build) do
            table.insert(allBuildNames, exp.Name)
        end
        updateStatus(#build, 0, #build, true, "กำลังตรวจสอบทีละบล็อก", allBuildNames)

        for _, exp in ipairs(build) do
            local found = nil

            for _, b in ipairs(destFolder:GetChildren()) do
                if not used[b] and b:IsA("Model") and b.Name == exp.Name then
                    local pp = b:FindFirstChild("PPart")
                    if pp and (pp.Position - exp.Pos.Position).Magnitude < COPY_VERIFY_TOLERANCE then
                        found = b
                        used[b] = true
                        break
                    end
                end
            end

            if found then
                setCurrentAction("กำลังปรับบล็อกเดิม", "PropertiesTool", exp.Name)
                local wantAnchor = shouldAnchor(exp, destFolder)
                customizeBlock(found, exp, wantAnchor)
                updateCnt += 1
            else
                local b, data = placeAndVerify(exp, destFolder)
                if b then
                    addCnt += 1
                    customizeBlock(b, data)
                else
                    failCnt += 1
                    table.insert(failedNames, exp.Name)
                end
            end

            updateStatus(
                #build,
                updateCnt + addCnt,
                #failedNames,
                true,
                "กำลังอัปเดต...",
                failedNames
            )
        end

        -- Recalculate the final failed names rather than relying on the running list.
        -- Any failedNames left here are blocks that could not be updated/added.
        failCnt = #failedNames

        if failCnt == 0 then
            currentMissingNames = {}
            setCurrentAction("เสร็จสิ้น", nil, nil, {})
            notifyCustom(
                "✅ อัปเดตเสร็จ",
                ("ปรับปรุง %d | เพิ่มใหม่ %d"):format(updateCnt, addCnt),
                5,
                "✅"
            )
            updateStatus(#build, updateCnt + addCnt, 0, false, "เสร็จสิ้น", {})
        else
            currentMissingNames = table.clone(failedNames)
            setCurrentAction("อัปเดตเสร็จบางส่วน", nil, nil, failedNames)
            notifyCustom(
                "⚠️ เสร็จบางส่วน",
                ("ปรับ %d | เพิ่ม %d | ขาด %d"):format(updateCnt, addCnt, failCnt),
                5,
                "⚠️"
            )
            updateStatus(
                #build,
                updateCnt + addCnt,
                failCnt,
                false,
                "เสร็จบางส่วน",
                failedNames
            )
        end
    end)

    copyBusy = false
    updateBusy = false

    if not ok then
        currentMissingNames = {}
        setCurrentAction("เกิดข้อผิดพลาด", nil, nil, {})
        notifyCustom("❌ ผิดพลาด", tostring(err), 5, "❌")
        updateStatus(0, 0, 0, false, "เกิดข้อผิดพลาด", {})
    end
end

-- ============================================================
--  VIEW SYSTEM — ไม่แก้ความเร็วตามที่ต้องการ
-- ============================================================
local viewEnabled = false
local viewSelectedPlayer = nil
local viewConnection = nil
local viewDistance = 18
local viewHeight = 6

local function restoreOwnCamera()
    local cam = workspace.CurrentCamera
    if cam and character and humanoid then
        cam.CameraType = Enum.CameraType.Custom
        cam.CameraSubject = humanoid
    end
end

local function setViewEnabled(enable)
    viewEnabled = enable
    if viewConnection then viewConnection:Disconnect() end
    if not enable then
        restoreOwnCamera()
        notifyCustom("👁️ ปิด View", "กล้องคืนสู่ตัวเอง", 3, "⏹️")
        return
    end
    if not viewSelectedPlayer or not viewSelectedPlayer.Parent then
        viewEnabled = false
        notifyCustom("⚠️ ไม่มีเป้าหมาย", "เลือกผู้เล่นก่อน", 3, "👤")
        return
    end
    local cam = workspace.CurrentCamera
    cam.CameraType = Enum.CameraType.Scriptable
    viewConnection = RunService.RenderStepped:Connect(function()
        if not viewEnabled then return end
        local tChar = viewSelectedPlayer.Character
        local root = tChar and tChar:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local focus = root.Position + Vector3.new(0, viewHeight, 0)
        local offset = -root.CFrame.LookVector * viewDistance + Vector3.new(0, viewHeight*0.35, 0)
        cam.CFrame = CFrame.lookAt(root.Position + offset, focus)
    end)
    notifyCustom("👁️ เปิด View", "กำลังดู: "..viewSelectedPlayer.DisplayName, 3, "👁️")
end

-- ============================================================
--  UI MENU
-- ============================================================
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Window = Rayfield:CreateWindow({
    Name = "WAN HUB V3",
    LoadingTitle = "WAN HUB V3",
    Theme = "Ocean",
    ToggleUIKeybind = "G"
})

local function getPlayerList()
    local t = {}
    for _, p in ipairs(players:GetPlayers()) do
        if p ~= player then table.insert(t, p.DisplayName.." (@"..p.Name..")") end
    end
    table.sort(t)
    return t
end

local function findPlayerByDisplay(nameStr)
    local un = nameStr:match("@([%w_]+)%)")
    if un then return players:FindFirstChild(un) end
    for _, p in ipairs(players:GetPlayers()) do
        if p.DisplayName.." (@"..p.Name..")" == nameStr then return p end
    end
    return nil
end

local copyTab = Window:CreateTab("📋 Copy", "rewind")
local ddPlayer = copyTab:CreateDropdown({
    Name = "👤 เลือกผู้เล่น",
    Options = getPlayerList(),
    Callback = function(opt)
        selectedPlayer = findPlayerByDisplay(type(opt)=="table" and opt[1] or opt)
    end
})

copyTab:CreateButton({Name = "🔄 รีเฟรชรายชื่อ", Callback = function() ddPlayer:Refresh(getPlayerList()) end})
copyTab:CreateToggle({Name = "📋 เปิด/ปิดระบบ", CurrentValue = true, Callback = function(v) copyEnabled = v end})
copyTab:CreateButton({Name = "📋 Copy Build", Callback = function() runCopyBuild(selectedPlayer) end})
copyTab:CreateButton({Name = "➕ Update Build", Callback = function() runUpdateBuild() end})

local viewTab = Window:CreateTab("👁️ View", "eye")
local ddView = viewTab:CreateDropdown({
    Name = "👤 เลือกผู้เล่น",
    Options = getPlayerList(),
    Callback = function(opt)
        viewSelectedPlayer = findPlayerByDisplay(type(opt)=="table" and opt[1] or opt)
    end
})

viewTab:CreateToggle({Name = "👁️ เปิด/ปิด View", Callback = setViewEnabled})
viewTab:CreateSlider({Name = "📷 ระยะกล้อง", Range={8,60}, CurrentValue=18, Callback=function(v) viewDistance = v end})
viewTab:CreateSlider({Name = "↕️ ความสูงกล้อง", Range={-5,30}, CurrentValue=6, Callback=function(v) viewHeight = v end})
viewTab:CreateButton({Name = "🎯 คืนกล้อง", Callback = function() setViewEnabled(false) end})

players.PlayerAdded:Connect(function(p)
    task.defer(function()
        task.wait(0.2)
        if ddPlayer then ddPlayer:Refresh(getPlayerList()) end
        if ddView then ddView:Refresh(getPlayerList()) end
    end)

    p.CharacterAdded:Connect(function()
        task.wait(0.3)
        if ddPlayer then ddPlayer:Refresh(getPlayerList()) end
        if ddView then ddView:Refresh(getPlayerList()) end
    end)
end)
players.PlayerRemoving:Connect(function(p)
    if selectedPlayer == p then
        selectedPlayer = nil
    end

    if viewSelectedPlayer == p then
        viewSelectedPlayer = nil
        setViewEnabled(false)
    end

    task.wait(0.2)
    if ddPlayer then ddPlayer:Refresh(getPlayerList()) end
    if ddView then ddView:Refresh(getPlayerList()) end
end)

currentMissingNames = {}
setCurrentAction("พร้อมใช้งาน", nil, nil, {})
notifyCustom("✅ พร้อมใช้งาน", "WAN HUB V3 โหลดเสร็จ — กันตกอัตโนมัติ + แจ้งเตือนครบ", 5, "🎉")
updateStatus(0, 0, 0, false, "พร้อมใช้งาน", {})
