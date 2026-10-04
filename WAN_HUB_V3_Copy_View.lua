-- ============================================================
-- 0. SERVICES & INITIALIZATION
-- ============================================================
local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")

local player = players.LocalPlayer
local character
local humanoid
local HRP

local function refreshCharacter()
    character = player.Character or player.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    HRP = character:WaitForChild("HumanoidRootPart")
end

refreshCharacter()

player.CharacterAdded:Connect(function()
    task.wait()
    refreshCharacter()
    if not viewEnabled then
        local camera = workspace.CurrentCamera
        if camera and humanoid then camera.CameraSubject = humanoid end
    end
end)

-- COLOR PALETTE CONSTANTS (Milky Blue & Mint Theme)
local COLORS = {
    Main = Color3.fromRGB(184, 242, 230),      -- #B8F2E6
    Mint = Color3.fromRGB(101, 214, 176),      -- #65D6B0
    LightBlue = Color3.fromRGB(142, 216, 232), -- #8ED8E8
    Soft = Color3.fromRGB(217, 245, 242),      -- #D9F5F2
    Working = Color3.fromRGB(245, 215, 122),   -- #F5D77A
    Error = Color3.fromRGB(233, 139, 139),     -- #E98B8B
    Text = Color3.fromRGB(36, 67, 77)          -- #24434D
}


-- ============================================================
-- 1. STATE / LOCK SYSTEM
-- ============================================================
local copyBusy = false
local updateBusy = false
local knownBlocks = {}

local function canStartTask()
    return not copyBusy and not updateBusy
end


-- ============================================================
-- 2. NOTIFICATION SYSTEM (Bottom-Right, Strict Max 3 Cards)
-- ============================================================
local MAX_NOTIFICATIONS = 3
local activeNotifications = {}
local notificationHolder = nil
local notificationCounter = 0

local function createNotificationHolder()
    if notificationHolder and notificationHolder.Parent then return end

    local gui = Instance.new("ScreenGui")
    gui.Name = "BABFT_NotificationHolder"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
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
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = notificationHolder
end

local function notifyCustom(title, content, duration, icon)
    createNotificationHolder()

    duration = duration or 3
    icon = icon or "ℹ️"

    -- FIFO Queue: ลบกล่องที่เก่าที่สุดทันทีเมื่อเกิน 3 กล่อง
    if #activeNotifications >= MAX_NOTIFICATIONS then
        local oldest = table.remove(activeNotifications, 1)
        if oldest and oldest.Frame and oldest.Frame.Parent then
            task.spawn(function()
                local tweenOut = TweenService:Create(
                    oldest.Frame,
                    TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { BackgroundTransparency = 1, Size = UDim2.new(0, 330, 0, 0) }
                )
                tweenOut:Play()
                tweenOut.Completed:Wait()
                if oldest.Frame then oldest.Frame:Destroy() end
            end)
        end
    end

    notificationCounter += 1

    local card = Instance.new("Frame")
    card.Name = "Notif_" .. tostring(notificationCounter)
    card.Size = UDim2.new(0, 330, 0, 75)
    card.BackgroundColor3 = COLORS.Soft
    card.BackgroundTransparency = 0.05
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.LayoutOrder = notificationCounter

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.Mint
    stroke.Thickness = 1.2
    stroke.Transparency = 0.2
    stroke.Parent = card

    local iconLbl = Instance.new("TextLabel")
    iconLbl.BackgroundTransparency = 1
    iconLbl.Position = UDim2.new(0, 10, 0, 10)
    iconLbl.Size = UDim2.new(0, 35, 0, 35)
    iconLbl.Font = Enum.Font.GothamBold
    iconLbl.TextSize = 22
    iconLbl.Text = icon
    iconLbl.TextColor3 = COLORS.Text
    iconLbl.Parent = card

    local titleLbl = Instance.new("TextLabel")
    titleLbl.BackgroundTransparency = 1
    titleLbl.Position = UDim2.new(0, 50, 0, 8)
    titleLbl.Size = UDim2.new(1, -60, 0, 22)
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 14
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Text = title
    titleLbl.TextColor3 = COLORS.Text
    titleLbl.Parent = card

    local contentLbl = Instance.new("TextLabel")
    contentLbl.BackgroundTransparency = 1
    contentLbl.Position = UDim2.new(0, 50, 0, 30)
    contentLbl.Size = UDim2.new(1, -60, 0, 38)
    contentLbl.Font = Enum.Font.Gotham
    contentLbl.TextSize = 12
    contentLbl.TextWrapped = true
    contentLbl.TextXAlignment = Enum.TextXAlignment.Left
    contentLbl.TextYAlignment = Enum.TextYAlignment.Top
    contentLbl.Text = content
    contentLbl.TextColor3 = COLORS.Text
    contentLbl.Parent = card

    card.Parent = notificationHolder

    local notifObj = { Frame = card }
    table.insert(activeNotifications, notifObj)

    -- Tween In
    card.Size = UDim2.new(0, 0, 0, 75)
    local tweenIn = TweenService:Create(
        card,
        TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = UDim2.new(0, 330, 0, 75) }
    )
    tweenIn:Play()

    -- Auto Dismiss
    task.delay(duration, function()
        if card and card.Parent then
            for idx, item in ipairs(activeNotifications) do
                if item.Frame == card then
                    table.remove(activeNotifications, idx)
                    break
                end
            end
            local tweenExit = TweenService:Create(
                card,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                { BackgroundTransparency = 1, Size = UDim2.new(0, 330, 0, 0) }
            )
            tweenExit:Play()
            tweenExit.Completed:Wait()
            card:Destroy()
        end
    end)
end



-- ============================================================
-- 3. COPY SYSTEM — WAN HUB V3
-- ============================================================
local blockData = player:WaitForChild("Data")
local blocksFolder = workspace:WaitForChild("Blocks")

local ignoreAnchored = true
local selectedPlayer = nil
local viewSelectedPlayer = nil

local copyBusy = false
local knownBlocks = {}
local knownBlockCount = 0

local COPY_MAX_ATTEMPTS = 5
local COPY_VERIFY_TIMEOUT = 1.5
local COPY_VERIFY_TOLERANCE = 5
local COPY_BATCH_YIELD = 8

local function equipTool(toolName)
    if not character or not humanoid then
        refreshCharacter()
    end

    local tool = character and character:FindFirstChild(toolName)
    if tool then
        return tool
    end

    local backpack = player:FindFirstChildOfClass("Backpack")
    local backpackTool = backpack and backpack:FindFirstChild(toolName)
    if not backpackTool then
        return nil
    end

    local ok = pcall(function()
        humanoid:EquipTool(backpackTool)
    end)
    if not ok then
        return nil
    end

    for _ = 1, 30 do
        tool = character and character:FindFirstChild(toolName)
        if tool then
            return tool
        end
        task.wait(0.05)
    end

    return nil
end

local function getBlockID(name)
    local value = blockData:FindFirstChild(name)
    return value and value.Value or 9
end

local function getPlayerZone(playerInstance)
    if not playerInstance then return nil end

    local teamColor = playerInstance.TeamColor
    for _, v in ipairs(workspace:GetChildren()) do
        local tc = v:FindFirstChild("TeamColor")
        if tc and tc.Value == teamColor then
            return v
        end
    end

    return nil
end

local function getSourceFolder(p)
    if not p then return nil end
    return blocksFolder:FindFirstChild(p.Name)
end

local function getNewBlockPos(sourceBase, block, destinationBase)
    if not block or not block:FindFirstChild("PPart") then
        return nil
    end

    if not sourceBase or not destinationBase then
        return block.PPart.CFrame
    end

    return destinationBase.CFrame * sourceBase.CFrame:ToObjectSpace(block.PPart.CFrame)
end

local function cframeKey(cf)
    local x, y, z = cf.Position.X, cf.Position.Y, cf.Position.Z
    local rx, ry, rz = cf:ToOrientation()
    return string.format(
        "%.3f|%.3f|%.3f|%.4f|%.4f|%.4f",
        x, y, z, rx, ry, rz
    )
end

local function makeBlockKey(name, cf, size)
    if not name or not cf or not size then return nil end
    return string.format(
        "%s|%s|%.3f|%.3f|%.3f",
        tostring(name),
        cframeKey(cf),
        size.X, size.Y, size.Z
    )
end

local function captureExistingBlocks(folder)
    local map = {}
    local count = 0

    if not folder then
        return map, count
    end

    for _, block in ipairs(folder:GetChildren()) do
        local pp = block:FindFirstChild("PPart")
        if block:IsA("Model") and pp and pp:IsA("BasePart") then
            local key = makeBlockKey(block.Name, pp.CFrame, pp.Size)
            if key and not map[key] then
                map[key] = true
                count += 1
            end
        end
    end

    return map, count
end

local function captureBuild(sourcePlayer)
    local sourceFolder = getSourceFolder(sourcePlayer)
    local sourceBase = getPlayerZone(sourcePlayer)
    local destinationBase = getPlayerZone(player)

    if not sourceFolder or not destinationBase then
        return {}
    end

    local result = {}

    for _, block in ipairs(sourceFolder:GetChildren()) do
        local pp = block:FindFirstChild("PPart")
        if block:IsA("Model") and pp and pp:IsA("BasePart") then
            local pos = getNewBlockPos(sourceBase, block, destinationBase)

            if pos then
                table.insert(result, {
                    Name = block.Name,
                    Pos = pos,
                    Relative = destinationBase,
                    Transparency = pp.Transparency,
                    Anchored = pp.Anchored,
                    Size = pp.Size,
                    Color = pp.Color,
                    Source = block,
                })
            end
        end
    end

    -- Stable order: lower blocks first, then distance from origin.
    table.sort(result, function(a, b)
        local ay, by = a.Pos.Position.Y, b.Pos.Position.Y
        if math.abs(ay - by) > 0.05 then
            return ay < by
        end
        return a.Pos.Position.Magnitude < b.Pos.Position.Magnitude
    end)

    return result
end

local function placeBlock(expected)
    local tool = equipTool("BuildingTool")
    if not tool or not tool:FindFirstChild("RF") then
        return false
    end

    local relativeTo = expected.Relative or getPlayerZone(player)
    if not relativeTo then
        return false
    end

    local args = {
        expected.Name,
        getBlockID(expected.Name),
        relativeTo,
        relativeTo.CFrame:ToObjectSpace(expected.Pos),
        ignoreAnchored and true or expected.Anchored,
        expected.Pos,
        false,
    }

    local ok = pcall(function()
        tool.RF:InvokeServer(unpack(args))
    end)

    return ok
end

local function findPlacedBlock(folder, expected, tolerance)
    if not folder then return nil, math.huge end

    local best, bestDist = nil, math.huge
    local wanted = expected.Pos.Position

    for _, block in ipairs(folder:GetChildren()) do
        if block:IsA("Model") and block.Name == expected.Name then
            local pp = block:FindFirstChild("PPart")
            if pp and pp:IsA("BasePart") then
                local dist = (pp.Position - wanted).Magnitude
                if dist < bestDist then
                    best = block
                    bestDist = dist
                end
            end
        end
    end

    if best and bestDist <= (tolerance or COPY_VERIFY_TOLERANCE) then
        return best, bestDist
    end

    return nil, bestDist
end

local function placeAndVerify(expected, destinationFolder)
    for attempt = 1, COPY_MAX_ATTEMPTS do
        if attempt > 1 then
            task.wait(0.12 * attempt)
        end

        placeBlock(expected)

        local deadline = os.clock() + COPY_VERIFY_TIMEOUT
        repeat
            local block = findPlacedBlock(destinationFolder, expected)
            if block then
                return block
            end
            task.wait(0.06)
        until os.clock() >= deadline
    end

    return nil
end

local function setTransparency(transparencyWanted, block)
    if not block or not block:FindFirstChild("PPart") then return end
    if block.PPart.Transparency == transparencyWanted then return end

    local tool = equipTool("PropertiesTool")
    if not tool or not tool:FindFirstChild("SetPropertieRF") then return end

    local steps = math.max(1, math.floor(transparencyWanted / 0.25))
    for _ = 1, steps do
        pcall(function()
            tool.SetPropertieRF:InvokeServer("Transparency", {block})
        end)
        task.wait(0.03)
    end
end

local function setAnchored(block)
    if not block then return end

    local tool = equipTool("PropertiesTool")
    if not tool or not tool:FindFirstChild("SetPropertieRF") then return end

    pcall(function()
        tool.SetPropertieRF:InvokeServer("Anchored", {block})
    end)
end

local function rescaleBlock(block, newPos, newSize)
    if not block then return end

    local tool = equipTool("ScalingTool")
    if not tool or not tool:FindFirstChild("RF") then return end

    pcall(function()
        tool.RF:InvokeServer(block, newSize, newPos)
    end)
end

local function paintBlock(block, color)
    if not block or not block:FindFirstChild("PPart") then return end

    local tool = equipTool("PaintingTool")
    if not tool or not tool:FindFirstChild("RF") then return end

    pcall(function()
        tool.RF:InvokeServer({{block, color}})
    end)
end

local function customizeBlock(block, expected)
    if not block then return end

    rescaleBlock(block, expected.Pos, expected.Size)
    task.wait(0.03)

    paintBlock(block, expected.Color)
    task.wait(0.03)

    if expected.Transparency > 0 then
        setTransparency(expected.Transparency, block)
        task.wait(0.03)
    end

    if expected.Anchored then
        setAnchored(block)
    end
end

local copyStatus = {
    total = 0,
    placed = 0,
    missing = 0,
    percent = 0,
    running = false,
}

local statusFrame, statusTitle, statusText, progressFill

local function createCopyStatusUI()
    if statusFrame and statusFrame.Parent then return end

    statusFrame = Instance.new("Frame")
    statusFrame.Name = "CopyBuildStatus"
    statusFrame.Size = UDim2.new(0, 310, 0, 145)
    statusFrame.Position = UDim2.new(0.5, -155, 0, 80)
    statusFrame.BackgroundTransparency = 0.08
    statusFrame.BackgroundColor3 = COLORS.LightBlue
    statusFrame.BorderSizePixel = 0
    statusFrame.Parent = player:WaitForChild("PlayerGui")

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = statusFrame

    statusTitle = Instance.new("TextLabel")
    statusTitle.Size = UDim2.new(1, -20, 0, 30)
    statusTitle.Position = UDim2.new(0, 10, 0, 8)
    statusTitle.BackgroundTransparency = 1
    statusTitle.Text = "WAN HUB — Copy"
    statusTitle.TextSize = 18
    statusTitle.Font = Enum.Font.GothamBold
    statusTitle.TextColor3 = COLORS.Text
    statusTitle.TextXAlignment = Enum.TextXAlignment.Left
    statusTitle.Parent = statusFrame

    statusText = Instance.new("TextLabel")
    statusText.Size = UDim2.new(1, -20, 0, 55)
    statusText.Position = UDim2.new(0, 10, 0, 40)
    statusText.BackgroundTransparency = 1
    statusText.Text = "พร้อมใช้งาน"
    statusText.TextSize = 14
    statusText.Font = Enum.Font.Gotham
    statusText.TextColor3 = COLORS.Text
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    statusText.TextYAlignment = Enum.TextYAlignment.Top
    statusText.Parent = statusFrame

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -20, 0, 14)
    bar.Position = UDim2.new(0, 10, 1, -25)
    bar.BackgroundTransparency = 0.35
    bar.BackgroundColor3 = COLORS.Soft
    bar.BorderSizePixel = 0
    bar.Parent = statusFrame

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 7)
    barCorner.Parent = bar

    progressFill = Instance.new("Frame")
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.BackgroundColor3 = COLORS.Mint
    progressFill.BorderSizePixel = 0
    progressFill.Parent = bar

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 7)
    fillCorner.Parent = progressFill
end

local function updateCopyStatus(total, placed, missing, running, phase)
    createCopyStatusUI()

    copyStatus.total = total or 0
    copyStatus.placed = placed or 0
    copyStatus.missing = missing or 0
    copyStatus.running = running == true

    if copyStatus.total > 0 then
        copyStatus.percent = math.floor((copyStatus.placed / copyStatus.total) * 100 + 0.5)
    else
        copyStatus.percent = 0
    end

    statusText.Text = ("%s\nทั้งหมด: %d | สำเร็จ: %d | ขาด: %d\nความคืบหน้า: %d%%"):format(
        phase or (running and "กำลังทำงาน..." or "พร้อมใช้งาน"),
        copyStatus.total,
        copyStatus.placed,
        copyStatus.missing,
        copyStatus.percent
    )

    progressFill.Size = UDim2.new(math.clamp(copyStatus.percent / 100, 0, 1), 0, 1, 0)
end

local function countKnownBlocks()
    local n = 0
    for _ in pairs(knownBlocks) do
        n += 1
    end
    return n
end

local function runCopyBuild(targetPlayer)
    if copyBusy then
        notifyCustom("Copy", "⚠️ Copy กำลังทำงานอยู่", 3, "⚠️")
        return
    end

    if not targetPlayer or not targetPlayer.Parent or targetPlayer == player then
        notifyCustom("Copy", "⚠️ กรุณาเลือกผู้เล่นอื่นที่ยังอยู่ในเกม", 3, "⚠️")
        return
    end

    local destinationFolder = blocksFolder:FindFirstChild(player.Name)
    if not destinationFolder then
        notifyCustom("Copy", "⚠️ ไม่พบโฟลเดอร์ Build ของเรา", 4, "⚠️")
        return
    end

    copyBusy = true

    local ok, err = pcall(function()
        local build = captureBuild(targetPlayer)
        if #build == 0 then
            notifyCustom("Copy", "⚠️ ไม่พบบล็อกที่คัดลอกได้", 4, "⚠️")
            return
        end

        local existing = captureExistingBlocks(destinationFolder)
        local queue = {}

        for _, expected in ipairs(build) do
            local key = makeBlockKey(expected.Name, expected.Pos, expected.Size)
            if key and not existing[key] then
                table.insert(queue, {data = expected, key = key})
            end
        end

        local total = #queue
        if total == 0 then
            knownBlocks = existing
            knownBlockCount = countKnownBlocks()
            updateCopyStatus(#build, #build, 0, false, "Build ตรงกันแล้ว")
            notifyCustom("Copy", "✅ Build ปลายทางมีบล็อกครบแล้ว", 4, "✅")
            return
        end

        updateCopyStatus(total, 0, total, true, "กำลังวางบล็อก...")
        notifyCustom("Copy", ("🔍 ตรวจพบ %d บล็อกที่ต้องวาง"):format(total), 4, "🏗️")

        local placed = 0
        local failed = {}

        for i, item in ipairs(queue) do
            local block = placeAndVerify(item.data, destinationFolder)

            if block then
                placed += 1
                existing[item.key] = true
                knownBlocks[item.key] = true
            else
                table.insert(failed, item)
            end

            updateCopyStatus(total, placed, #failed, true, "กำลังวางบล็อก...")
            if i % COPY_BATCH_YIELD == 0 then
                task.wait()
            end
        end

        -- Second pass only for failed blocks.
        if #failed > 0 then
            notifyCustom("Copy", ("🔁 กำลังลองซ้ำ %d บล็อก"):format(#failed), 3, "🔁")
            local retry = failed
            failed = {}

            for i, item in ipairs(retry) do
                local block = placeAndVerify(item.data, destinationFolder)
                if block then
                    placed += 1
                    existing[item.key] = true
                    knownBlocks[item.key] = true
                else
                    table.insert(failed, item)
                end

                updateCopyStatus(total, placed, #failed, true, "กำลัง Retry...")
                if i % COPY_BATCH_YIELD == 0 then
                    task.wait()
                end
            end
        end

        -- Apply visual / physical properties after placement.
        updateCopyStatus(total, placed, #failed, true, "กำลังปรับแต่งบล็อก...")

        for i, item in ipairs(queue) do
            local block = findPlacedBlock(destinationFolder, item.data)
            if block then
                customizeBlock(block, item.data)
            end

            if i % COPY_BATCH_YIELD == 0 then
                task.wait()
            end
        end

        knownBlocks = existing
        knownBlockCount = countKnownBlocks()

        updateCopyStatus(total, placed, #failed, false, "เสร็จสิ้น")

        if #failed == 0 then
            notifyCustom("Copy", ("✅ สำเร็จ %d/%d บล็อก"):format(placed, total), 5, "✅")
        else
            notifyCustom("Copy", ("⚠️ สำเร็จ %d/%d | พลาด %d"):format(placed, total, #failed), 5, "⚠️")
        end
    end)

    copyBusy = false

    if not ok then
        updateCopyStatus(0, 0, 0, false, "เกิดข้อผิดพลาด")
        notifyCustom("Copy", "❌ Copy เกิดข้อผิดพลาด: " .. tostring(err), 5, "❌")
    end
end

local function runUpdateBuild()
    if copyBusy then
        notifyCustom("Update", "⚠️ Copy กำลังทำงานอยู่", 3, "⚠️")
        return
    end

    if not selectedPlayer or not selectedPlayer.Parent then
        notifyCustom("Update", "⚠️ ผู้เล่นต้นทางไม่พร้อมใช้งาน", 3, "⚠️")
        return
    end

    local destinationFolder = blocksFolder:FindFirstChild(player.Name)
    if not destinationFolder then
        notifyCustom("Update", "⚠️ ไม่พบ Build ของเรา", 3, "⚠️")
        return
    end

    copyBusy = true

    local ok, err = pcall(function()
        local sourceBuild = captureBuild(selectedPlayer)
        local existing = captureExistingBlocks(destinationFolder)
        local missing = {}

        for _, expected in ipairs(sourceBuild) do
            local key = makeBlockKey(expected.Name, expected.Pos, expected.Size)
            if key and not existing[key] then
                table.insert(missing, {data = expected, key = key})
            end
        end

        if #missing == 0 then
            notifyCustom("Update", "ℹ️ ไม่พบบล็อกใหม่", 3, "ℹ️")
            knownBlocks = existing
            knownBlockCount = countKnownBlocks()
            return
        end

        notifyCustom("Update", ("🔍 พบของใหม่ %d บล็อก"):format(#missing), 3, "🔍")

        local placed = 0
        for i, item in ipairs(missing) do
            local block = placeAndVerify(item.data, destinationFolder)
            if block then
                placed += 1
                existing[item.key] = true
                customizeBlock(block, item.data)
            end

            if i % COPY_BATCH_YIELD == 0 then
                task.wait()
            end
        end

        knownBlocks = existing
        knownBlockCount = countKnownBlocks()

        notifyCustom("Update", ("✅ เพิ่มสำเร็จ %d/%d"):format(placed, #missing), 4, "✅")
    end)

    copyBusy = false

    if not ok then
        notifyCustom("Update", "❌ Update เกิดข้อผิดพลาด: " .. tostring(err), 5, "❌")
    end
end


-- ============================================================
-- 4. VIEW SYSTEM — ADVANCED SPECTATE
-- ============================================================
local viewEnabled = false
local viewDropdown = nil
local viewConnection = nil
local viewDistance = 18
local viewHeight = 6

local function restoreOwnCamera()
    local camera = workspace.CurrentCamera
    local ownHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")

    if camera and ownHumanoid then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = ownHumanoid
    end
end

local function setViewEnabled(enabled)
    viewEnabled = enabled == true

    if viewConnection then
        viewConnection:Disconnect()
        viewConnection = nil
    end

    if not viewEnabled then
        restoreOwnCamera()
        notifyCustom("View", "⏹️ ปิด View แล้ว", 3, "⏹️")
        return
    end

    if not viewSelectedPlayer or not viewSelectedPlayer.Parent then
        viewEnabled = false
        restoreOwnCamera()
        notifyCustom("View", "⚠️ กรุณาเลือกผู้เล่นก่อน", 3, "⚠️")
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then return end

    camera.CameraType = Enum.CameraType.Scriptable

    viewConnection = RunService.RenderStepped:Connect(function()
        if not viewEnabled then return end

        local target = viewSelectedPlayer.Character
        local targetRoot = target and target:FindFirstChild("HumanoidRootPart")

        if not targetRoot then
            return
        end

        local focus = targetRoot.Position + Vector3.new(0, viewHeight, 0)
        local offset = Vector3.new(0, viewHeight * 0.35, viewDistance)
        local cameraPos = focus + offset

        camera.CFrame = CFrame.lookAt(cameraPos, focus)
    end)

    notifyCustom("View", "👁️ กำลังดู: " .. viewSelectedPlayer.DisplayName, 3, "👁️")
end

local function refreshViewTarget()
    if viewEnabled then
        setViewEnabled(false)
        task.wait()
        setViewEnabled(true)
    end
end


-- ============================================================
-- 5. UI — COPY + VIEW ONLY
-- ============================================================
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
    Name = "WAN HUB V3 — Copy & View",
    Icon = 0,
    LoadingTitle = "WAN HUB V3",
    LoadingSubtitle = "Copy & View",
    Theme = "Ocean",
    ToggleUIKeybind = "G",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "WAN_HUB",
        FileName = "CopyViewConfig"
    },
})

local copyTab = Window:CreateTab("📋 Copy", "rewind")

local function getPlayers()
    local result = {}
    for _, p in ipairs(players:GetPlayers()) do
        if p ~= player then
            table.insert(result, p.DisplayName)
        end
    end
    table.sort(result)
    return result
end

local function getRealName(displayName)
    for _, p in ipairs(players:GetPlayers()) do
        if p.DisplayName == displayName then
            return p.Name
        end
    end
    return nil
end

local playerDropdown = copyTab:CreateDropdown({
    Name = "👤 เลือกผู้เล่นต้นทาง",
    Options = getPlayers(),
    CurrentOption = {},
    MultipleOptions = false,
    Callback = function(option)
        local displayName = type(option) == "table" and option[1] or option
        if type(displayName) == "string" then
            local realName = getRealName(displayName)
            selectedPlayer = realName and players:FindFirstChild(realName) or nil
        end
    end,
})

copyTab:CreateButton({
    Name = "🔄 รีเฟรชรายชื่อ",
    Callback = function()
        playerDropdown:Refresh(getPlayers())
        if viewDropdown then
            viewDropdown:Refresh(getPlayers())
        end
        notifyCustom("Players", "🔄 รีเฟรชรายชื่อแล้ว", 2, "🔄")
    end,
})

copyTab:CreateButton({
    Name = "📋 Copy Build",
    Callback = function()
        runCopyBuild(selectedPlayer)
    end,
})

copyTab:CreateButton({
    Name = "➕ Update Build",
    Callback = function()
        runUpdateBuild()
    end,
})

copyTab:CreateButton({
    Name = "📊 สถานะ Copy",
    Callback = function()
        notifyCustom(
            "Copy Status",
            ("วางแล้ว: %d | บล็อกที่รู้จัก: %d"):format(
                copyStatus.placed,
                knownBlockCount
            ),
            4,
            "📊"
        )
    end,
})

local viewTab = Window:CreateTab("👁️ View", "eye")

viewDropdown = viewTab:CreateDropdown({
    Name = "👤 เลือกผู้เล่น",
    Options = getPlayers(),
    CurrentOption = {},
    MultipleOptions = false,
    Callback = function(option)
        local displayName = type(option) == "table" and option[1] or option
        if type(displayName) == "string" then
            local realName = getRealName(displayName)
            viewSelectedPlayer = realName and players:FindFirstChild(realName) or nil
            if viewEnabled then
                refreshViewTarget()
            end
        end
    end,
})

viewTab:CreateToggle({
    Name = "👁️ เปิด/ปิด View",
    Callback = function(value)
        setViewEnabled(value)
    end,
})

viewTab:CreateSlider({
    Name = "📷 ระยะกล้อง",
    Range = {8, 60},
    Increment = 1,
    CurrentValue = 18,
    Callback = function(value)
        viewDistance = value
    end,
})

viewTab:CreateSlider({
    Name = "↕️ ความสูงกล้อง",
    Range = {-5, 30},
    Increment = 1,
    CurrentValue = 6,
    Callback = function(value)
        viewHeight = value
    end,
})

viewTab:CreateButton({
    Name = "🎯 รีเซ็ตกล้องตัวเอง",
    Callback = function()
        setViewEnabled(false)
    end,
})

-- Player lifecycle.
players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function()
        task.wait(0.2)
        if viewEnabled and viewSelectedPlayer == p then
            refreshViewTarget()
        end
    end)

    task.wait(0.5)
    pcall(function()
        playerDropdown:Refresh(getPlayers())
        viewDropdown:Refresh(getPlayers())
    end)
end)

for _, p in ipairs(players:GetPlayers()) do
    if p ~= player then
        p.CharacterAdded:Connect(function()
            task.wait(0.2)
            if viewEnabled and viewSelectedPlayer == p then
                refreshViewTarget()
            end
        end)
    end
end

players.PlayerRemoving:Connect(function(p)
    if selectedPlayer == p then
        selectedPlayer = nil
    end

    if viewSelectedPlayer == p then
        viewSelectedPlayer = nil
        setViewEnabled(false)
        notifyCustom("View", "⚠️ ผู้เล่นที่กำลังดูออกจากเกมแล้ว", 3, "⚠️")
    end

    task.wait(0.2)
    pcall(function()
        playerDropdown:Refresh(getPlayers())
        viewDropdown:Refresh(getPlayers())
    end)
end)

player.CharacterAdded:Connect(function()
    task.wait(0.2)
    if not viewEnabled then
        restoreOwnCamera()
    end
end)

createCopyStatusUI()
updateCopyStatus(0, 0, 0, false, "พร้อมใช้งาน")
notifyCustom("WAN HUB V3", "✅ โหลดเฉพาะระบบ Copy + View แล้ว", 4, "✅")
