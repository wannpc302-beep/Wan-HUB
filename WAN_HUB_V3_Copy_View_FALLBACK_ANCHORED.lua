-- ============================================================
-- 0. SERVICES & INITIALIZATION
-- ============================================================
local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
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
local copyEnabled = true
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

local function makeBlockKey(name, cf)
    if not name or not cf then return nil end
    return string.format(
        "%s|%s",
        tostring(name),
        cframeKey(cf)
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
            local key = makeBlockKey(block.Name, pp.CFrame)
            if key and not map[key] then
                map[key] = true
                count += 1
            end
        end
    end

    return map, count
end

local function findMatchingBuildBlock(folder, expected, used)
    if not folder or not expected or not expected.Pos then
        return nil, math.huge
    end

    used = used or {}
    local wantedPos = expected.Pos.Position
    local wantedLook = expected.Pos.LookVector
    local best, bestScore, bestDist = nil, math.huge, math.huge

    for _, block in ipairs(folder:GetChildren()) do
        if not used[block] and block:IsA("Model") and block.Name == expected.Name then
            local pp = block:FindFirstChild("PPart")
            if pp and pp:IsA("BasePart") then
                local dist = (pp.Position - wantedPos).Magnitude
                if dist <= COPY_VERIFY_TOLERANCE then
                    local dot = math.clamp(pp.CFrame.LookVector:Dot(wantedLook), -1, 1)
                    local rotationPenalty = 1 - dot
                    local score = dist + rotationPenalty * 2

                    if score < bestScore then
                        best = block
                        bestScore = score
                        bestDist = dist
                    end
                end
            end
        end
    end

    if best then
        return best, bestDist
    end

    return nil, math.huge
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


-- ============================================================
-- FALLBACK BLOCK SELECTION
-- If the exact block type is unavailable, choose an available
-- destination block type with the closest physical properties.
-- ============================================================
local function getBlockFeatures(block)
    if not block or not block:FindFirstChild("PPart") then
        return nil
    end

    local pp = block.PPart
    if not pp:IsA("BasePart") then
        return nil
    end

    return {
        Size = pp.Size,
        Color = pp.Color,
        Transparency = pp.Transparency,
        Anchored = pp.Anchored,
        Material = pp.Material,
    }
end

local function blockFeatureScore(expected, candidateBlock)
    local f = getBlockFeatures(candidateBlock)
    if not f or not expected then
        return math.huge
    end

    local expectedSize = expected.Size or Vector3.one
    local sizeDelta =
        math.abs(f.Size.X - expectedSize.X) +
        math.abs(f.Size.Y - expectedSize.Y) +
        math.abs(f.Size.Z - expectedSize.Z)

    local colorDelta =
        math.abs(f.Color.R - (expected.Color and expected.Color.R or f.Color.R)) +
        math.abs(f.Color.G - (expected.Color and expected.Color.G or f.Color.G)) +
        math.abs(f.Color.B - (expected.Color and expected.Color.B or f.Color.B))

    local transparencyDelta =
        math.abs(f.Transparency - (expected.Transparency or f.Transparency))

    local anchoredPenalty = 0
    if expected.Anchored ~= nil and f.Anchored ~= expected.Anchored then
        anchoredPenalty = 0.5
    end

    local materialPenalty = 0
    if expected.Source and expected.Source:FindFirstChild("PPart") then
        local sourcePart = expected.Source.PPart
        if sourcePart:IsA("BasePart") and sourcePart.Material ~= f.Material then
            materialPenalty = 0.35
        end
    end

    return sizeDelta + colorDelta * 4 + transparencyDelta * 2
        + anchoredPenalty + materialPenalty
end

local function getFallbackBlockName(expected, destinationFolder)
    if not expected or not destinationFolder then
        return nil
    end

    local bestName = nil
    local bestScore = math.huge
    local checkedNames = {}

    -- Prefer block types that are already present in the player's build.
    -- Their actual properties are known, so the fallback is based on
    -- real in-game properties rather than guessed names.
    for _, block in ipairs(destinationFolder:GetChildren()) do
        if block:IsA("Model") and block.Name ~= expected.Name and not checkedNames[block.Name] then
            checkedNames[block.Name] = true

            local score = blockFeatureScore(expected, block)
            if score < bestScore then
                bestScore = score
                bestName = block.Name
            end
        end
    end

    return bestName
end

local function preparePlacementData(expected, destinationFolder)
    if not expected then
        return nil
    end

    local exactValue = blockData:FindFirstChild(expected.Name)
    if exactValue then
        return expected
    end

    local fallbackName = getFallbackBlockName(expected, destinationFolder)
    if not fallbackName then
        return expected
    end

    local copy = {}
    for k, v in pairs(expected) do
        copy[k] = v
    end
    copy.Name = fallbackName
    copy.FallbackFrom = expected.Name
    return copy
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
    if not folder or not expected or not expected.Pos then
        return nil, math.huge
    end

    local best, bestScore, bestDist = nil, math.huge, math.huge
    local wanted = expected.Pos.Position
    local wantedLook = expected.Pos.LookVector
    local maxTolerance = tolerance or COPY_VERIFY_TOLERANCE

    for _, block in ipairs(folder:GetChildren()) do
        if block:IsA("Model") and block.Name == expected.Name then
            local pp = block:FindFirstChild("PPart")
            if pp and pp:IsA("BasePart") then
                local dist = (pp.Position - wanted).Magnitude
                if dist <= maxTolerance then
                    local dot = math.clamp(pp.CFrame.LookVector:Dot(wantedLook), -1, 1)
                    local score = dist + (1 - dot) * 2
                    if score < bestScore then
                        best = block
                        bestScore = score
                        bestDist = dist
                    end
                end
            end
        end
    end

    if best then
        return best, bestDist
    end

    return nil, math.huge
end

local function placeAndVerify(expected, destinationFolder)
    local placementData = preparePlacementData(expected, destinationFolder)

    for attempt = 1, COPY_MAX_ATTEMPTS do
        if attempt > 1 then
            task.wait(0.12 * attempt)
        end

        placeBlock(placementData)

        local deadline = os.clock() + COPY_VERIFY_TIMEOUT
        repeat
            local block = findPlacedBlock(destinationFolder, placementData)
            if block then
                -- Lock the block immediately after it appears. This is
                -- intentionally done before returning to the main copy loop,
                -- so a floating build piece does not get time to fall.
                if placementData.Anchored ~= nil then
                    for _ = 1, 3 do
                        if setAnchored(block, placementData.Anchored) then
                            break
                        end
                        task.wait(0.04)
                    end
                end

                return block, placementData
            end
            task.wait(0.06)
        until os.clock() >= deadline
    end

    return nil, placementData
end

local function setTransparency(transparencyWanted, block)
    if not block or not block:FindFirstChild("PPart") then return false end

    local pp = block.PPart
    if math.abs(pp.Transparency - transparencyWanted) <= 0.001 then
        return true
    end

    local tool = equipTool("PropertiesTool")
    if not tool or not tool:FindFirstChild("SetPropertieRF") then
        return false
    end

    -- Cycle the property and verify the actual result after every call.
    local maxSteps = 12
    local lastValue = pp.Transparency

    for _ = 1, maxSteps do
        local ok = pcall(function()
            tool.SetPropertieRF:InvokeServer("Transparency", {block})
        end)

        task.wait(0.06)

        if math.abs(pp.Transparency - transparencyWanted) <= 0.001 then
            return true
        end

        if not ok or math.abs(pp.Transparency - lastValue) <= 0.0001 then
            break
        end

        lastValue = pp.Transparency
    end

    return math.abs(pp.Transparency - transparencyWanted) <= 0.001
end

local function setAnchored(block, wanted)
    if not block or not block:FindFirstChild("PPart") or wanted == nil then return false end

    local pp = block.PPart
    if pp.Anchored == wanted then
        return true
    end

    local tool = equipTool("PropertiesTool")
    if not tool or not tool:FindFirstChild("SetPropertieRF") then
        return false
    end

    local ok = pcall(function()
        tool.SetPropertieRF:InvokeServer("Anchored", {block})
    end)

    task.wait(0.06)
    return ok and pp.Anchored == wanted
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

    -- IMPORTANT:
    -- Set Anchored first, especially for blocks copied into the air.
    -- This prevents the newly placed block from falling while the other
    -- properties are being applied.
    if expected.Anchored ~= nil then
        for _ = 1, 3 do
            if setAnchored(block, expected.Anchored) then
                break
            end
            task.wait(0.05)
        end
    end

    -- For a fallback block, preserve its own physical properties because
    -- those properties are why it was selected as the closest substitute.
    if not expected.FallbackFrom then
        rescaleBlock(block, expected.Pos, expected.Size)
        task.wait(0.03)

        paintBlock(block, expected.Color)
        task.wait(0.03)

        if expected.Transparency ~= nil then
            setTransparency(expected.Transparency, block)
            task.wait(0.03)
        end

        -- Verify Anchored again after scaling/properties have been applied.
        if expected.Anchored ~= nil then
            setAnchored(block, expected.Anchored)
        end
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
    if not copyEnabled then
        notifyCustom("Copy", "⛔ ระบบ Copy ถูกปิดอยู่", 3, "⛔")
        return
    end

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
            local key = makeBlockKey(expected.Name, expected.Pos)
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
            local block, placementData = placeAndVerify(item.data, destinationFolder)

            if block then
                placed += 1
                existing[item.key] = true
                knownBlocks[item.key] = true
                if placementData and placementData.FallbackFrom then
                    notifyCustom(
                        "Copy",
                        ("🔁 %s หมด → ใช้ %s ที่คุณสมบัติใกล้เคียง"):format(
                            placementData.FallbackFrom,
                            placementData.Name
                        ),
                        2.5,
                        "🔁"
                    )
                end
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
    if not copyEnabled then
        notifyCustom("Update", "⛔ ระบบ Copy/Update ถูกปิดอยู่", 3, "⛔")
        return
    end

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
        local used = {}
        local updates = {}
        local missing = {}

        -- Match existing blocks by name + nearest position, not by size.
        -- This allows Update to detect changes to size/color/transparency/etc.
        for _, expected in ipairs(sourceBuild) do
            local block = findMatchingBuildBlock(destinationFolder, expected, used)

            if block then
                used[block] = true
                table.insert(updates, {block = block, data = expected})
            else
                table.insert(missing, expected)
            end
        end

        if #updates == 0 and #missing == 0 then
            notifyCustom("Update", "ℹ️ ไม่พบข้อมูล Build ต้นทาง", 3, "ℹ️")
            return
        end

        notifyCustom(
            "Update",
            ("🔍 พบ %d บล็อกเดิม | %d บล็อกใหม่"):format(#updates, #missing),
            4,
            "🔍"
        )

        local updated = 0
        local placed = 0
        local failed = 0
        local done = 0
        local totalWork = #updates + #missing

        for _, item in ipairs(updates) do
            customizeBlock(item.block, item.data)
            updated += 1
            done += 1

            if done % COPY_BATCH_YIELD == 0 then
                task.wait()
            end
        end

        for _, expected in ipairs(missing) do
            local block, placementData = placeAndVerify(expected, destinationFolder)

            if block then
                placed += 1
                customizeBlock(block, placementData or expected)
            else
                failed += 1
            end

            done += 1
            if done % COPY_BATCH_YIELD == 0 then
                task.wait()
            end
        end

        local existing = captureExistingBlocks(destinationFolder)
        knownBlocks = existing
        knownBlockCount = countKnownBlocks()

        if failed == 0 then
            notifyCustom(
                "Update",
                ("✅ อัปเดต %d | เพิ่มใหม่ %d | สำเร็จ %d/%d"):format(
                    updated, placed, updated + placed, totalWork
                ),
                5,
                "✅"
            )
        else
            notifyCustom(
                "Update",
                ("⚠️ อัปเดต %d | เพิ่ม %d | พลาด %d"):format(
                    updated, placed, failed
                ),
                5,
                "⚠️"
            )
        end
    end)

    copyBusy = false

    if not ok then
        notifyCustom("Update", "❌ Update เกิดข้อผิดพลาด: " .. tostring(err), 5, "❌")
    end
end


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
        local backward = -targetRoot.CFrame.LookVector
        local offset = backward * viewDistance + Vector3.new(0, viewHeight * 0.35, 0)
        local cameraPos = targetRoot.Position + offset
        local wantedCFrame = CFrame.lookAt(cameraPos, focus)

        camera.CFrame = camera.CFrame:Lerp(wantedCFrame, 0.22)
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
            table.insert(result, ("%s (@%s)"):format(p.DisplayName, p.Name))
        end
    end
    table.sort(result)
    return result
end

local function getRealName(displayName)
    if type(displayName) ~= "string" then
        return nil
    end

    local username = displayName:match("@([%w_]+)%)")
    if username then
        local direct = players:FindFirstChild(username)
        if direct then
            return direct.Name
        end
    end

    for _, p in ipairs(players:GetPlayers()) do
        if p.DisplayName == displayName or p.Name == displayName then
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

copyTab:CreateToggle({
    Name = "📋 เปิด/ปิดการก็อปปี้",
    CurrentValue = true,
    Callback = function(value)
        copyEnabled = value
        if value then
            notifyCustom("Copy", "✅ เปิดระบบ Copy / Update แล้ว", 3, "📋")
        else
            notifyCustom("Copy", "⛔ ปิดระบบ Copy / Update แล้ว", 3, "⛔")
        end
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
    Name = "📊 สถานะ Copy / Fallback",
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
