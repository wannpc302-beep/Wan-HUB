-- ============================================================
-- WAN HUB V5 — Modular Build Copier
-- UI: Thai | Variables: English
-- Features:
--   • Deep fallback selection by block properties
--   • Placement + verification + retry
--   • Scale / Paint / Anchor verification
--   • Missing block counter + names
--   • Target player list with refresh
--   • Draggable status window + reopen button
--   • View target camera
--   • Separate Copy target / View target selectors
--   • Binding/cannon control is intentionally not included
--   • Defensive pcall/timeouts
-- ============================================================

-- Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Local player
local LocalPlayer = Players.LocalPlayer
local Character, Humanoid, HRP

local function RefreshCharacter()
    Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    Humanoid = Character:FindFirstChildOfClass("Humanoid") or Character:WaitForChild("Humanoid")
    HRP = Character:FindFirstChild("HumanoidRootPart") or Character:WaitForChild("HumanoidRootPart")
end

RefreshCharacter()
LocalPlayer.CharacterAdded:Connect(function()
    task.wait()
    pcall(RefreshCharacter)
end)

-- Color scheme
local COLORS = {
    -- Dark charcoal theme with cyan/blue accents
    Mint      = Color3.fromRGB(45, 155, 255),
    LightBlue = Color3.fromRGB(20, 24, 32),
    Soft      = Color3.fromRGB(35, 41, 52),
    Working   = Color3.fromRGB(90, 190, 255),
    Error     = Color3.fromRGB(255, 105, 120),
    Text      = Color3.fromRGB(230, 238, 250),
    White     = Color3.fromRGB(245, 248, 255),
    Dark      = Color3.fromRGB(13, 16, 23)
}

-- Clean old UI
pcall(function()
    local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if PlayerGui then
        for _, Name in ipairs({"WAN_HUB_UI", "WAN_HUB_Notify"}) do
            local Old = PlayerGui:FindFirstChild(Name)
            if Old then Old:Destroy() end
        end
    end
end)

-- State
local CopyBusy = false
local CopyEnabled = true
local CopyPaused = false
local CopyCancelRequested = false
local TargetPlayer = nil -- Copy target
local TargetSelectMode = "copy"
local ViewEnabled = false
local ViewTargetPlayer = nil
local ViewConnection = nil
local ViewDistance = 18
local ViewHeight = 6

local BlockData = nil
local BlocksFolder = nil

local StatusGui = nil
local StatusFrame = nil
local StatusText = nil
local ProgressFill = nil
local MissingText = nil
local TargetListFrame = nil
local ReopenButton = nil

local StatusState = {
    Total = 0,
    Placed = 0,
    Missing = 0,
    Phase = "พร้อมใช้งาน",
    CurrentName = nil,
    FailedList = {},
}

local Dragging = false
local DragStartPos = Vector2.new()
local FrameStartPos = Vector2.new()

-- Config
local CONFIG = {
    MaxAttempts = 3,
    VerifyTimeout = 1.0,
    VerifyInterval = 0.04,
    PositionTolerance = 4.5,
    SizeTolerance = 0.18,
    ColorTolerance = 0.12,
    PropertyVerifyTimeout = 0.65,
    RetryBaseDelay = 0.08,
    YieldEvery = 10,
    MaxFallbackScore = 75,
    ShowMissingLimit = 8,
}

-- ============================================================
-- Notification
-- ============================================================
local function Notify(Title, Message, Color)
    Color = Color or COLORS.Mint
    local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not PlayerGui then return end

    local Gui = PlayerGui:FindFirstChild("WAN_HUB_Notify")
    if not Gui then
        Gui = Instance.new("ScreenGui")
        Gui.Name = "WAN_HUB_Notify"
        Gui.ResetOnSpawn = false
        Gui.IgnoreGuiInset = true
        Gui.Parent = PlayerGui
    end

    local Card = Instance.new("Frame")
    Card.Size = UDim2.new(0, 0, 0, 60)
    Card.Position = UDim2.new(0.5, -150, 0.05, 0)
    Card.BackgroundColor3 = Color
    Card.BackgroundTransparency = 0.1
    Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 10)

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Size = UDim2.new(1, -20, 0, 25)
    TitleLabel.Position = UDim2.new(0, 10, 0, 5)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.TextSize = 14
    TitleLabel.Text = tostring(Title)
    TitleLabel.TextColor3 = COLORS.Text
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.Parent = Card

    local MsgLabel = Instance.new("TextLabel")
    MsgLabel.Size = UDim2.new(1, -20, 0, 25)
    MsgLabel.Position = UDim2.new(0, 10, 0, 30)
    MsgLabel.BackgroundTransparency = 1
    MsgLabel.Font = Enum.Font.Gotham
    MsgLabel.TextSize = 12
    MsgLabel.Text = tostring(Message)
    MsgLabel.TextColor3 = COLORS.Text
    MsgLabel.TextXAlignment = Enum.TextXAlignment.Left
    MsgLabel.TextTruncate = Enum.TextTruncate.AtEnd
    MsgLabel.Parent = Card

    Card.Parent = Gui
    TweenService:Create(Card, TweenInfo.new(0.2), {
        Size = UDim2.new(0, 300, 0, 60)
    }):Play()

    task.delay(3, function()
        if not Card or not Card.Parent then return end
        pcall(function()
            TweenService:Create(Card, TweenInfo.new(0.2), {
                BackgroundTransparency = 1,
                Size = UDim2.new(0, 300, 0, 0)
            }):Play()
        end)
        task.wait(0.25)
        if Card and Card.Parent then Card:Destroy() end
    end)
end

-- ============================================================
-- UI helpers
-- ============================================================
local function SafeSetText(Label, Text)
    if Label and Label.Parent then
        Label.Text = tostring(Text or "")
    end
end

local function CreateButton(Parent, Text, Position, Size)
    local Btn = Instance.new("TextButton")
    Btn.Size = Size or UDim2.new(1, -20, 0, 32)
    Btn.Position = Position
    Btn.BackgroundColor3 = COLORS.Soft
    Btn.BackgroundTransparency = 0.15
    Btn.Font = Enum.Font.GothamBold
    Btn.TextSize = 13
    Btn.Text = Text
    Btn.TextColor3 = COLORS.Text
    Btn.AutoButtonColor = true
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 8)
    Btn.Parent = Parent
    return Btn
end

local function DestroyTargetList()
    if TargetListFrame then
        TargetListFrame:Destroy()
        TargetListFrame = nil
    end
end

local function GetOtherPlayers()
    local Result = {}
    for _, Player in ipairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer then
            table.insert(Result, Player)
        end
    end
    table.sort(Result, function(A, B)
        return string.lower(A.DisplayName) < string.lower(B.DisplayName)
    end)
    return Result
end

local function RefreshTargetList(Mode)
    if not StatusFrame then return end
    TargetSelectMode = Mode or TargetSelectMode or "copy"
    DestroyTargetList()

    TargetListFrame = Instance.new("ScrollingFrame")
    TargetListFrame.Name = "TargetList"
    TargetListFrame.Size = UDim2.new(0, 280, 0, 180)
    TargetListFrame.Position = UDim2.new(0.5, -140, 0, 42)
    TargetListFrame.BackgroundColor3 = COLORS.White
    TargetListFrame.BackgroundTransparency = 0.05
    TargetListFrame.BorderSizePixel = 0
    TargetListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    TargetListFrame.ScrollBarThickness = 5
    TargetListFrame.ZIndex = 50
    Instance.new("UICorner", TargetListFrame).CornerRadius = UDim.new(0, 8)
    TargetListFrame.Parent = StatusFrame

    local Header = Instance.new("TextLabel")
    Header.Size = UDim2.new(1, -12, 0, 28)
    Header.Position = UDim2.new(0, 6, 0, 4)
    Header.BackgroundTransparency = 1
    Header.Font = Enum.Font.GothamBold
    Header.TextSize = 12
    Header.TextColor3 = COLORS.Text
    Header.Text = TargetSelectMode == "copy" and "📋 เลือกผู้เล่นสำหรับคัดลอก" or "👁️ เลือกผู้เล่นสำหรับมุมมอง"
    Header.TextXAlignment = Enum.TextXAlignment.Left
    Header.ZIndex = 51
    Header.Parent = TargetListFrame

    local ListFrame = Instance.new("Frame")
    ListFrame.Size = UDim2.new(1, 0, 0, 0)
    ListFrame.Position = UDim2.new(0, 0, 0, 34)
    ListFrame.BackgroundTransparency = 1
    ListFrame.AutomaticSize = Enum.AutomaticSize.Y
    ListFrame.ZIndex = 50
    ListFrame.Parent = TargetListFrame

    local Layout = Instance.new("UIListLayout")
    Layout.Padding = UDim.new(0, 5)
    Layout.SortOrder = Enum.SortOrder.LayoutOrder
    Layout.Parent = ListFrame

    local Padding = Instance.new("UIPadding")
    Padding.PaddingLeft = UDim.new(0, 6)
    Padding.PaddingRight = UDim.new(0, 6)
    Padding.Parent = ListFrame

    local PlayersList = GetOtherPlayers()
    if #PlayersList == 0 then
        local Empty = Instance.new("TextLabel")
        Empty.Size = UDim2.new(1, -12, 0, 34)
        Empty.BackgroundTransparency = 1
        Empty.Font = Enum.Font.Gotham
        Empty.TextSize = 12
        Empty.TextColor3 = COLORS.Text
        Empty.Text = "ไม่มีผู้เล่นอื่นในเซิร์ฟเวอร์"
        Empty.ZIndex = 51
        Empty.Parent = ListFrame
    else
        for _, Player in ipairs(PlayersList) do
            local Current = (TargetSelectMode == "copy" and TargetPlayer == Player) or
                            (TargetSelectMode == "view" and ViewTargetPlayer == Player)
            local Prefix = Current and "✓ " or "👤 "
            local Btn = CreateButton(ListFrame, Prefix .. Player.DisplayName .. "  (" .. Player.Name .. ")", UDim2.new(), UDim2.new(1, -12, 0, 30))
            Btn.TextSize = 11
            Btn.TextXAlignment = Enum.TextXAlignment.Left
            Btn.ZIndex = 51
            Btn.MouseButton1Click:Connect(function()
                if TargetSelectMode == "copy" then
                    TargetPlayer = Player
                    Notify("เป้าหมายคัดลอก", "เลือก: " .. Player.DisplayName, COLORS.Mint)
                else
                    ViewTargetPlayer = Player
                    Notify("เป้าหมายมุมมอง", "เลือก: " .. Player.DisplayName, COLORS.LightBlue)
                end
                DestroyTargetList()
            end)
        end
    end

    task.defer(function()
        if TargetListFrame and ListFrame then
            local H = math.max(40, ListFrame.AbsoluteSize.Y + 42)
            TargetListFrame.CanvasSize = UDim2.new(0, 0, 0, H)
            TargetListFrame.Size = UDim2.new(0, 280, 0, math.min(180, H))
        end
    end)
end

local function CreateCopyToggle(Parent, Position)
    local Holder = Instance.new("Frame")
    Holder.Name = "CopyToggle"
    Holder.Size = UDim2.new(0, 145, 0, 38)
    Holder.Position = Position
    Holder.BackgroundTransparency = 1
    Holder.Parent = Parent

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0, 62, 1, 0)
    Label.Position = UDim2.new(0, 0, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = "📋 คัดลอก"
    Label.Font = Enum.Font.GothamSemibold
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextColor3 = COLORS.Text
    Label.Parent = Holder

    local Track = Instance.new("TextButton")
    Track.Name = "Track"
    Track.Size = UDim2.new(0, 58, 0, 28)
    Track.Position = UDim2.new(1, -58, 0.5, -14)
    Track.AutoButtonColor = false
    Track.Text = ""
    Track.BorderSizePixel = 0
    Track.Parent = Holder
    Instance.new("UICorner", Track).CornerRadius = UDim.new(1, 0)

    local Knob = Instance.new("Frame")
    Knob.Name = "Knob"
    Knob.Size = UDim2.new(0, 22, 0, 22)
    Knob.BorderSizePixel = 0
    Knob.Parent = Track
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)

    local StateLabel = Instance.new("TextLabel")
    StateLabel.Size = UDim2.new(0, 34, 1, 0)
    StateLabel.Position = UDim2.new(0, 5, 0, 0)
    StateLabel.BackgroundTransparency = 1
    StateLabel.Font = Enum.Font.GothamBold
    StateLabel.TextSize = 10
    StateLabel.TextColor3 = COLORS.Text
    StateLabel.ZIndex = 3
    StateLabel.Parent = Track

    local function Render()
        if CopyEnabled then
            Track.BackgroundColor3 = Color3.fromRGB(45, 155, 255)
            Knob.Position = UDim2.new(1, -26, 0.5, -11)
            StateLabel.Text = "เปิด"
            StateLabel.TextXAlignment = Enum.TextXAlignment.Left
        else
            Track.BackgroundColor3 = Color3.fromRGB(76, 84, 98)
            Knob.Position = UDim2.new(0, 4, 0.5, -11)
            StateLabel.Text = "ปิด"
            StateLabel.TextXAlignment = Enum.TextXAlignment.Right
        end
    end

    Track.MouseButton1Click:Connect(function()
        CopyEnabled = not CopyEnabled
        if not CopyEnabled and CopyBusy then
            -- Stop after the currently executing block operation returns.
            CopyCancelRequested = true
            CopyPaused = false
        end
        Render()
        if CopyEnabled then
            Notify("ระบบคัดลอก", "เปิดแล้ว — ใช้เริ่มงานคัดลอกครั้งถัดไป", COLORS.Mint)
        else
            if CopyBusy then
                Notify("ระบบคัดลอก", "ปิดแล้ว — กำลังหยุดงานหลังบล็อกปัจจุบัน", COLORS.Working)
            else
                Notify("ระบบคัดลอก", "ปิดแล้ว", COLORS.Working)
            end
        end
    end)

    Render()
    return Holder
end

local function CreateStatusUI()
    if StatusGui and StatusGui.Parent and StatusFrame then return end

    local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not PlayerGui then return end

    StatusGui = Instance.new("ScreenGui")
    StatusGui.Name = "WAN_HUB_UI"
    StatusGui.ResetOnSpawn = false
    StatusGui.IgnoreGuiInset = true
    StatusGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    StatusGui.Parent = PlayerGui

    StatusFrame = Instance.new("Frame")
    StatusFrame.Name = "StatusFrame"
    StatusFrame.Size = UDim2.new(0, 320, 0, 488)
    StatusFrame.Position = UDim2.new(0.5, -160, 0, 50)
    StatusFrame.BackgroundColor3 = COLORS.LightBlue
    StatusFrame.BackgroundTransparency = 0.05
    StatusFrame.BorderSizePixel = 0
    Instance.new("UICorner", StatusFrame).CornerRadius = UDim.new(0, 12)
    StatusFrame.Parent = StatusGui

    local TitleBar = Instance.new("Frame")
    TitleBar.Name = "TitleBar"
    TitleBar.Size = UDim2.new(1, 0, 0, 38)
    TitleBar.BackgroundColor3 = Color3.fromRGB(24, 36, 54)
    TitleBar.BorderSizePixel = 0
    Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 12)
    TitleBar.Parent = StatusFrame

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Size = UDim2.new(1, -50, 1, 0)
    TitleLabel.Position = UDim2.new(0, 12, 0, 0)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = "WAN HUB V5 • COPY / VIEW"
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.TextSize = 15
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.TextColor3 = COLORS.Text
    TitleLabel.Parent = TitleBar

    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size = UDim2.new(0, 35, 0, 35)
    CloseBtn.Position = UDim2.new(1, -40, 0, 1.5)
    CloseBtn.BackgroundTransparency = 1
    CloseBtn.Text = "✕"
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.TextSize = 20
    CloseBtn.TextColor3 = COLORS.Text
    CloseBtn.Parent = TitleBar
    CloseBtn.MouseButton1Click:Connect(function()
        DestroyTargetList()
        if StatusFrame then StatusFrame.Visible = false end
        if ReopenButton then ReopenButton.Visible = true end
    end)

    StatusText = Instance.new("TextLabel")
    StatusText.Name = "StatusText"
    StatusText.Size = UDim2.new(1, -20, 0, 88)
    StatusText.Position = UDim2.new(0, 10, 0, 45)
    StatusText.BackgroundTransparency = 1
    StatusText.Text = "พร้อมใช้งาน"
    StatusText.Font = Enum.Font.Gotham
    StatusText.TextSize = 13
    StatusText.TextWrapped = true
    StatusText.TextXAlignment = Enum.TextXAlignment.Left
    StatusText.TextYAlignment = Enum.TextYAlignment.Top
    StatusText.TextColor3 = COLORS.Text
    StatusText.Parent = StatusFrame

    local BarBg = Instance.new("Frame")
    BarBg.Name = "ProgressBg"
    BarBg.Size = UDim2.new(1, -20, 0, 14)
    BarBg.Position = UDim2.new(0, 10, 0, 135)
    BarBg.BackgroundColor3 = COLORS.Soft
    BarBg.BackgroundTransparency = 0.3
    BarBg.BorderSizePixel = 0
    Instance.new("UICorner", BarBg).CornerRadius = UDim.new(0, 7)
    BarBg.Parent = StatusFrame

    ProgressFill = Instance.new("Frame")
    ProgressFill.Name = "ProgressFill"
    ProgressFill.Size = UDim2.new(0, 0, 1, 0)
    ProgressFill.BackgroundColor3 = COLORS.Mint
    ProgressFill.BorderSizePixel = 0
    Instance.new("UICorner", ProgressFill).CornerRadius = UDim.new(0, 7)
    ProgressFill.Parent = BarBg

    MissingText = Instance.new("TextLabel")
    MissingText.Name = "MissingText"
    MissingText.Size = UDim2.new(1, -20, 0, 62)
    MissingText.Position = UDim2.new(0, 10, 0, 155)
    MissingText.BackgroundTransparency = 1
    MissingText.Font = Enum.Font.Gotham
    MissingText.TextSize = 11
    MissingText.TextWrapped = true
    MissingText.TextXAlignment = Enum.TextXAlignment.Left
    MissingText.TextYAlignment = Enum.TextYAlignment.Top
    MissingText.TextColor3 = COLORS.Text
    MissingText.Text = "❌ บล็อกที่ขาด: ไม่มี"
    MissingText.Parent = StatusFrame

    -- Two-column layout: คัดลอก | มอง
    local RefreshBtn = CreateButton(StatusFrame, "🔄 รีเฟรชรายชื่อ", UDim2.new(0, 10, 0, 225), UDim2.new(1, -20, 0, 32))
    RefreshBtn.MouseButton1Click:Connect(function()
        if TargetListFrame then DestroyTargetList() end
        Notify("รีเฟรช", "รายชื่อผู้เล่นอัปเดตแล้ว")
    end)

    local ColumnHeaderCopy = CreateButton(StatusFrame, "📋 คัดลอก", UDim2.new(0, 10, 0, 263), UDim2.new(0.5, -15, 0, 28))
    ColumnHeaderCopy.Name = "CopyColumnHeader"
    ColumnHeaderCopy.Active = false
    ColumnHeaderCopy.AutoButtonColor = false
    ColumnHeaderCopy.BackgroundColor3 = COLORS.Mint
    ColumnHeaderCopy.TextSize = 13

    local ColumnHeaderView = CreateButton(StatusFrame, "👁 มอง", UDim2.new(0.5, 5, 0, 263), UDim2.new(0.5, -15, 0, 28))
    ColumnHeaderView.Name = "ViewColumnHeader"
    ColumnHeaderView.Active = false
    ColumnHeaderView.AutoButtonColor = false
    ColumnHeaderView.BackgroundColor3 = COLORS.Mint
    ColumnHeaderView.TextSize = 13

    local CopyTargetBtn = CreateButton(StatusFrame, "เลือกชื่อ", UDim2.new(0, 10, 0, 297), UDim2.new(0.5, -15, 0, 34))
    CopyTargetBtn.MouseButton1Click:Connect(function()
        if TargetListFrame and TargetSelectMode == "copy" then
            DestroyTargetList()
        else
            RefreshTargetList("copy")
        end
    end)

    local ViewTargetBtn = CreateButton(StatusFrame, "เลือกชื่อ", UDim2.new(0.5, 5, 0, 297), UDim2.new(0.5, -15, 0, 34))
    ViewTargetBtn.MouseButton1Click:Connect(function()
        if TargetListFrame and TargetSelectMode == "view" then
            DestroyTargetList()
        else
            RefreshTargetList("view")
        end
    end)

    local CopyBtn = CreateButton(StatusFrame, "เริ่มคัดลอก", UDim2.new(0, 10, 0, 337), UDim2.new(0.5, -15, 0, 34))
    CopyBtn.MouseButton1Click:Connect(function()
        if not TargetPlayer then
            Notify("แจ้งเตือน", "กรุณาเลือกชื่อสำหรับคัดลอกก่อน", COLORS.Working)
            return
        end
        RunCopyBuild(TargetPlayer)
    end)

    local ViewBtn = CreateButton(StatusFrame, "เปิด/ปิดมอง", UDim2.new(0.5, 5, 0, 337), UDim2.new(0.5, -15, 0, 34))
    ViewBtn.MouseButton1Click:Connect(function()
        if not ViewTargetPlayer then
            Notify("แจ้งเตือน", "กรุณาเลือกชื่อสำหรับมุมมองก่อน", COLORS.Working)
            return
        end
        SetViewEnabled(not ViewEnabled)
    end)

    CreateCopyToggle(StatusFrame, UDim2.new(0, 10, 0, 377))

    -- Drag
    TitleBar.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
            Dragging = true
            DragStartPos = Input.Position
            -- Use the actual on-screen position (not UDim2 offsets only); this
            -- prevents the first drag from jumping off-screen when X uses Scale.
            FrameStartPos = StatusFrame.AbsolutePosition
        end
    end)

    TitleBar.InputEnded:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
            Dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(Input)
        if not Dragging then return end
        if Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch then
            local Delta = Input.Position - DragStartPos
            local Camera = Workspace.CurrentCamera
            local Viewport = Camera and Camera.ViewportSize or Vector2.new(800, 600)
            local MaxX = math.max(0, Viewport.X - StatusFrame.AbsoluteSize.X)
            local MaxY = math.max(0, Viewport.Y - StatusFrame.AbsoluteSize.Y)
            local X = math.clamp(FrameStartPos.X + Delta.X, 0, MaxX)
            local Y = math.clamp(FrameStartPos.Y + Delta.Y, 0, MaxY)
            StatusFrame.Position = UDim2.fromOffset(X, Y)
        end
    end)

    UserInputService.InputEnded:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
            Dragging = false
        end
    end)

    ReopenButton = Instance.new("TextButton")
    ReopenButton.Name = "ReopenButton"
    ReopenButton.Size = UDim2.new(0, 58, 0, 36)
    ReopenButton.AnchorPoint = Vector2.new(0.5, 0.5)
    ReopenButton.Position = UDim2.fromScale(0.5, 0.5)
    ReopenButton.BackgroundColor3 = COLORS.Dark
    ReopenButton.Text = "WAN"
    ReopenButton.Font = Enum.Font.GothamBold
    ReopenButton.TextSize = 14
    ReopenButton.TextColor3 = Color3.fromRGB(90, 190, 255)
    ReopenButton.Visible = false
    Instance.new("UICorner", ReopenButton).CornerRadius = UDim.new(0, 10)
    ReopenButton.Parent = StatusGui
    ReopenButton.MouseButton1Click:Connect(function()
        if StatusFrame then StatusFrame.Visible = true end
        ReopenButton.Visible = false
    end)

    -- WAN reopen button can be dragged on mouse/touch.
    local ReopenDragging = false
    local ReopenDragStart = Vector2.new()
    local ReopenStart = Vector2.new()
    ReopenButton.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
            ReopenDragging = true
            ReopenDragStart = Input.Position
            -- AbsolutePosition avoids the scale/offset mismatch that made WAN vanish.
            ReopenStart = ReopenButton.AbsolutePosition
        end
    end)
    ReopenButton.InputEnded:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
            ReopenDragging = false
        end
    end)
    UserInputService.InputEnded:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
            ReopenDragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(Input)
        if not ReopenDragging then return end
        if Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch then
            local Delta = Input.Position - ReopenDragStart
            local Camera = Workspace.CurrentCamera
            local Viewport = Camera and Camera.ViewportSize or Vector2.new(800, 600)
            local MaxX = math.max(0, Viewport.X - ReopenButton.AbsoluteSize.X)
            local MaxY = math.max(0, Viewport.Y - ReopenButton.AbsoluteSize.Y)
            local X = math.clamp(ReopenStart.X + Delta.X, 0, MaxX)
            local Y = math.clamp(ReopenStart.Y + Delta.Y, 0, MaxY)
            ReopenButton.Position = UDim2.fromOffset(X, Y)
        end
    end)
end

-- ============================================================
-- Status system
-- ============================================================
local function FormatMissing(FailedList)
    if not FailedList or #FailedList == 0 then
        return "❌ บล็อกที่ขาด: ไม่มี"
    end

    local Names = {}
    local Counts = {}
    for _, Data in ipairs(FailedList) do
        local Name = tostring(Data.FallbackFrom or Data.Name or "ไม่ทราบชื่อ")
        Counts[Name] = (Counts[Name] or 0) + 1
    end

    for Name, Count in pairs(Counts) do
        table.insert(Names, "• " .. Name .. (Count > 1 and (" ×" .. Count) or ""))
    end
    table.sort(Names)

    local Limit = math.min(#Names, CONFIG.ShowMissingLimit)
    local Lines = {"❌ บล็อกที่ขาด: " .. tostring(#FailedList)}
    for Index = 1, Limit do
        table.insert(Lines, Names[Index])
    end
    if #Names > Limit then
        table.insert(Lines, "• และอีก " .. tostring(#Names - Limit) .. " ชนิด")
    end
    return table.concat(Lines, "\n")
end

local function RenderStatus()
    CreateStatusUI()
    if not StatusText or not ProgressFill then return end

    local Total = StatusState.Total
    local Placed = StatusState.Placed
    local Missing = StatusState.Missing
    local Percent = Total > 0 and math.floor((Placed / Total) * 100 + 0.5) or 0
    Percent = math.max(0, math.min(100, Percent))
    local Phase = StatusState.Phase or "พร้อมใช้งาน"
    local Current = StatusState.CurrentName and ("\n🔎 " .. tostring(StatusState.CurrentName)) or ""

    SafeSetText(StatusText, string.format(
        "%s%s\nรวม: %d | สำเร็จ: %d | ขาด: %d\nความคืบหน้า: %d%%",
        Phase, Current, Total, Placed, Missing, Percent
    ))

    ProgressFill.Size = UDim2.new(Percent / 100, 0, 1, 0)
    SafeSetText(MissingText, FormatMissing(StatusState.FailedList or {}))
end

local function UpdateStatus(Total, Placed, Missing, PhaseText, CurrentName, FailedList)
    StatusState.Total = Total or 0
    StatusState.Placed = Placed or 0
    StatusState.Missing = Missing or 0
    StatusState.Phase = PhaseText or "พร้อมใช้งาน"
    StatusState.CurrentName = CurrentName
    StatusState.FailedList = FailedList or {}
    RenderStatus()
end

local function UpdateStatusPhase(PhaseText, CurrentName)
    StatusState.Phase = PhaseText or StatusState.Phase
    StatusState.CurrentName = CurrentName
    RenderStatus()
end

-- ============================================================
-- Generic helpers
-- ============================================================
local function Distance3(A, B)
    return (A - B).Magnitude
end

local function NumberOrZero(Value)
    return tonumber(Value) or 0
end

local function GetBlockID(Name)
    if not BlockData then return nil end
    local Entry = BlockData:FindFirstChild(Name)
    if not Entry then return nil end
    local Ok, Value = pcall(function() return Entry.Value end)
    if not Ok or type(Value) ~= "number" then return nil end
    return Value
end

local function EquipTool(ToolName)
    if not Character or not Humanoid then
        pcall(RefreshCharacter)
    end
    if not Character or not Humanoid then return nil end

    local Tool = Character:FindFirstChild(ToolName)
    if Tool and Tool:IsA("Tool") then return Tool end

    local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    Tool = Backpack and Backpack:FindFirstChild(ToolName)
    if not Tool or not Tool:IsA("Tool") then return nil end

    local Equipped = pcall(function()
        Humanoid:EquipTool(Tool)
    end)
    if not Equipped then return nil end

    for _ = 1, 30 do
        local Current = Character:FindFirstChild(ToolName)
        if Current and Current:IsA("Tool") then
            return Current
        end
        task.wait(0.05)
    end
    return nil
end

local function InvokeRemote(Remote, ...)
    if not Remote or not Remote:IsA("RemoteFunction") then
        return false, "remote-not-found"
    end
    local Ok, A, B, C = pcall(function(...)
        return Remote:InvokeServer(...)
    end, ...)
    if not Ok then
        return false, tostring(A)
    end
    -- Some game remotes return no value on success; pcall success is accepted.
    if A == false then
        return false, tostring(B or "server-rejected")
    end
    return true, A, B, C
end

local function WaitUntil(Timeout, Condition)
    local Deadline = os.clock() + Timeout
    repeat
        local Ok, Result = pcall(Condition)
        if Ok and Result then return true end
        task.wait(CONFIG.VerifyInterval)
    until os.clock() >= Deadline
    return false
end

-- ============================================================
-- Player zone / build capture
-- ============================================================
local function GetPlayerZone(PlayerObj)
    if not PlayerObj then return nil end

    local function MatchesOwner(Zone)
        if not Zone then return false end
        local NameLower = string.lower(PlayerObj.Name)
        local DisplayLower = string.lower(PlayerObj.DisplayName or PlayerObj.Name)

        for _, Key in ipairs({"Owner", "Player", "User", "OwnerUserId", "UserId"}) do
            local Obj = Zone:FindFirstChild(Key, true)
            if Obj then
                local Ok, Value = pcall(function() return Obj.Value end)
                if Ok and Value ~= nil then
                    if typeof(Value) == "Instance" and Value == PlayerObj then
                        return true
                    end
                    if tostring(Value) == tostring(PlayerObj.UserId) or
                       string.lower(tostring(Value)) == NameLower or
                       string.lower(tostring(Value)) == DisplayLower then
                        return true
                    end
                end
            end
        end

        local AttrUserId = Zone:GetAttribute("UserId") or Zone:GetAttribute("OwnerUserId")
        if AttrUserId and tostring(AttrUserId) == tostring(PlayerObj.UserId) then
            return true
        end
        local AttrName = Zone:GetAttribute("Owner") or Zone:GetAttribute("Player")
        if AttrName and (string.lower(tostring(AttrName)) == NameLower or string.lower(tostring(AttrName)) == DisplayLower) then
            return true
        end
        return false
    end

    -- Prefer explicit ownership. TeamColor is only a final fallback because
    -- multiple zones can share the same team color.
    for _, Zone in ipairs(Workspace:GetDescendants()) do
        if MatchesOwner(Zone) then
            return Zone
        end
    end

    local TargetColor = PlayerObj.TeamColor
    for _, Zone in ipairs(Workspace:GetDescendants()) do
        local TeamColor = Zone:FindFirstChild("TeamColor")
        if TeamColor then
            local Ok, Value = pcall(function() return TeamColor.Value end)
            if Ok and Value == TargetColor then
                return Zone
            end
        end
    end
    return nil
end

local function FindPlayerBlockFolder(PlayerObj)
    if not BlocksFolder or not PlayerObj then return nil end
    return BlocksFolder:FindFirstChild(PlayerObj.Name)
end

local function GetPartProfile(PPart)
    if not PPart or not PPart:IsA("BasePart") then return nil end
    local Profile = {
        ClassName = PPart.ClassName,
        Shape = nil,
        MeshId = nil,
        TextureId = nil,
        Size = PPart.Size,
        Color = PPart.Color,
        Material = PPart.Material,
        MaterialVariant = PPart.MaterialVariant,
        Transparency = PPart.Transparency,
        Reflectance = PPart.Reflectance,
        CanCollide = PPart.CanCollide,
        CastShadow = PPart.CastShadow,
        Anchored = PPart.Anchored,
    }

    pcall(function()
        if PPart:IsA("Part") then
            Profile.Shape = PPart.Shape.Name
        end
    end)

    pcall(function()
        if PPart:IsA("MeshPart") then
            Profile.MeshId = PPart.MeshId
            Profile.TextureId = PPart.TextureID
        end
    end)

    pcall(function()
        local Mesh = PPart:FindFirstChildOfClass("SpecialMesh")
        if Mesh then
            Profile.MeshId = Mesh.MeshId
            Profile.TextureId = Mesh.TextureId
        end
    end)

    return Profile
end

local function CaptureBuild(PlayerObj)
    local SourceZone = GetPlayerZone(PlayerObj)
    local DestZone = GetPlayerZone(LocalPlayer)
    local SourceFolder = FindPlayerBlockFolder(PlayerObj)
    if not SourceFolder or not SourceZone or not DestZone then
        return {}
    end

    local Result = {}
    for _, Block in ipairs(SourceFolder:GetChildren()) do
        local PPart = Block:FindFirstChild("PPart")
        if PPart and PPart:IsA("BasePart") then
            table.insert(Result, {
                Name = Block.Name,
                Pos = DestZone.CFrame * SourceZone.CFrame:ToObjectSpace(PPart.CFrame),
                Relative = DestZone,
                Anchored = PPart.Anchored,
                Size = PPart.Size,
                Color = PPart.Color,
                Material = PPart.Material,
                MaterialVariant = PPart.MaterialVariant,
                Transparency = PPart.Transparency,
                Reflectance = PPart.Reflectance,
                CanCollide = PPart.CanCollide,
                CastShadow = PPart.CastShadow,
                Profile = GetPartProfile(PPart),
            })
        end
    end

    table.sort(Result, function(A, B)
        return A.Pos.Position.Y < B.Pos.Position.Y
    end)
    return Result
end

-- ============================================================
-- Existing / support
-- ============================================================
local function FindSupportBlock(DestFolder, Position)
    local BestBlock = nil
    local MinDistance = 6
    if not DestFolder then return nil end

    for _, Block in ipairs(DestFolder:GetChildren()) do
        if Block:IsA("Model") then
            local PPart = Block:FindFirstChild("PPart")
            if PPart and PPart:IsA("BasePart") and PPart.Anchored then
                local Distance = Distance3(PPart.Position, Position)
                if Distance < MinDistance then
                    MinDistance = Distance
                    BestBlock = Block
                end
            end
        end
    end
    return BestBlock
end

local function ShouldAnchor(ExportData, DestFolder)
    if ExportData.Anchored == true then
        return true, "ยึดตามต้นฉบับ"
    end

    local CheckPos = ExportData.Pos.Position - Vector3.new(0, 2.6, 0)
    local HasSupport = FindSupportBlock(DestFolder, CheckPos)
    if HasSupport then
        return false, "มีส่วนรองรับ → ปล่อยแรงโน้มถ่วง"
    end
    return true, "ไม่มีส่วนรองรับ → ยึดอัตโนมัติ"
end

local function BuildPositionKey(CF)
    if not CF then return nil end
    local X, Y, Z = CF.Position.X, CF.Position.Y, CF.Position.Z
    local R1, R2, R3 = CF:ToOrientation()
    return string.format("%.2f;%.2f;%.2f;%.3f;%.3f;%.3f", X, Y, Z, R1, R2, R3)
end

local function BuildKey(Name, CF)
    if not Name or not CF then return nil end
    return tostring(Name) .. "|" .. tostring(BuildPositionKey(CF))
end

local function GetExistingMap(Folder)
    local Map = {}
    if not Folder then return Map end
    for _, Block in ipairs(Folder:GetChildren()) do
        local PPart = Block:FindFirstChild("PPart")
        if PPart and PPart:IsA("BasePart") then
            local Key = BuildKey(Block.Name, PPart.CFrame)
            if Key then Map[Key] = true end
        end
    end
    return Map
end

-- ============================================================
-- Deep Fallback selection
-- ============================================================
local function ColorDistance(A, B)
    if not A or not B then return 1 end
    local DR = A.R - B.R
    local DG = A.G - B.G
    local DB = A.B - B.B
    return math.sqrt(DR * DR + DG * DG + DB * DB)
end

local function VectorDiffNormalized(A, B)
    if not A or not B then return 1 end
    local Den = math.max(A.Magnitude, B.Magnitude, 0.001)
    return (A - B).Magnitude / Den
end

local function StringSimilarity(A, B)
    A = string.lower(tostring(A or ""))
    B = string.lower(tostring(B or ""))
    if A == B then return 1 end
    if A == "" or B == "" then return 0 end
    if string.find(A, B, 1, true) or string.find(B, A, 1, true) then return 0.75 end

    local function Tokens(S)
        local Set = {}
        for Token in string.gmatch(S, "[%w_]+") do
            Set[Token] = true
        end
        return Set
    end

    local TA, TB = Tokens(A), Tokens(B)
    local Common, Total = 0, 0
    for K in pairs(TA) do
        Total = Total + 1
        if TB[K] then Common = Common + 1 end
    end
    for K in pairs(TB) do
        if not TA[K] then Total = Total + 1 end
    end
    return Total > 0 and (Common / Total) or 0
end

local function CalcFeatureScore(Export, CandidateProfile, CandidateName)
    if not Export or not CandidateProfile then return math.huge end
    local P = CandidateProfile
    local S = Export.Size or Vector3.one

    local Score = 0

    -- Shape/class are strong indicators.
    if Export.Profile and Export.Profile.ClassName and P.ClassName ~= Export.Profile.ClassName then
        Score = Score + 8
    end

    if Export.Profile and Export.Profile.Shape and P.Shape then
        if Export.Profile.Shape ~= P.Shape then Score = Score + 6 end
    end

    -- Mesh identity, when available, is very important.
    if Export.Profile and Export.Profile.MeshId and P.MeshId then
        if Export.Profile.MeshId == P.MeshId then
            Score = Score - 10
        else
            Score = Score + 10
        end
    end

    -- Material and visual properties.
    if Export.Material and P.Material ~= Export.Material then Score = Score + 18 end
    if tostring(Export.MaterialVariant or "") ~= tostring(P.MaterialVariant or "") then Score = Score + 6 end
    Score = Score + ColorDistance(Export.Color, P.Color) * 18
    Score = Score + math.abs(NumberOrZero(Export.Transparency) - NumberOrZero(P.Transparency)) * 8
    Score = Score + math.abs(NumberOrZero(Export.Reflectance) - NumberOrZero(P.Reflectance)) * 4

    if Export.CanCollide ~= nil and P.CanCollide ~= Export.CanCollide then
        Score = Score + 4
    end
    if Export.CastShadow ~= nil and P.CastShadow ~= Export.CastShadow then
        Score = Score + 3
    end

    -- Size is normalized so large blocks do not dominate the score.
    Score = Score + VectorDiffNormalized(S, P.Size) * 24

    if CandidateName then
        -- Name is deliberately only a weak tie-breaker.
        Score = Score + (1 - StringSimilarity(Export.Name, CandidateName)) * 4
    end

    return Score
end

local function FindSampleByName(BlockName, PreferredFolder)
    if PreferredFolder then
        local Exact = PreferredFolder:FindFirstChild(BlockName)
        if Exact then
            local PPart = Exact:FindFirstChild("PPart")
            if PPart and PPart:IsA("BasePart") then
                return GetPartProfile(PPart)
            end
        end
    end

    if not BlocksFolder then return nil end

    -- Search player folders first (fast path).
    for _, PlayerFolder in ipairs(BlocksFolder:GetChildren()) do
        if PlayerFolder:IsA("Folder") or PlayerFolder:IsA("Model") then
            local Block = PlayerFolder:FindFirstChild(BlockName)
            if Block then
                local PPart = Block:FindFirstChild("PPart")
                if PPart and PPart:IsA("BasePart") then
                    return GetPartProfile(PPart)
                end
            end
        end
    end
    return nil
end

local function BuildCandidateCatalog(PreferredFolder)
    local Catalog = {}
    if not BlockData then return Catalog end

    for _, Entry in ipairs(BlockData:GetChildren()) do
        local ID = nil
        pcall(function() ID = tonumber(Entry.Value) end)
        if ID ~= nil then
            local Name = Entry.Name
            Catalog[Name] = {
                ID = ID,
                Profile = FindSampleByName(Name, PreferredFolder),
            }
        end
    end
    return Catalog
end

local function FindFallbackName(Export, DestFolder, CandidateCatalog)
    local BestName = nil
    local BestScore = math.huge

    for Name, Candidate in pairs(CandidateCatalog or {}) do
        if Name ~= Export.Name and Candidate.ID ~= nil and Candidate.Profile then
            local Score = CalcFeatureScore(Export, Candidate.Profile, Name)
            if Score < BestScore then
                BestScore = Score
                BestName = Name
            end
        end
    end

    -- Never fall back to a name-only match. A replacement is accepted only
    -- when there is a real sampled block profile and it passes the threshold.
    if BestName and BestScore <= CONFIG.MaxFallbackScore then
        return BestName, BestScore
    end

    return nil, BestScore
end

local function PreparePlacementData(Export, DestFolder, CandidateCatalog)
    if GetBlockID(Export.Name) ~= nil then
        return Export
    end

    local FallbackName, Score = FindFallbackName(Export, DestFolder, CandidateCatalog)
    if not FallbackName or GetBlockID(FallbackName) == nil then
        return nil, "ไม่พบบล็อกทดแทนที่มี ID"
    end

    local Data = {}
    for K, V in pairs(Export) do Data[K] = V end
    Data.Name = FallbackName
    Data.FallbackFrom = Export.Name
    Data.FallbackScore = Score
    Data.OriginalName = Export.Name
    return Data
end

-- ============================================================
-- Placement / verification
-- ============================================================
local function PlaceSingleBlock(Data)
    local Tool = EquipTool("BuildingTool")
    if not Tool then return false, "ไม่พบ BuildingTool" end

    local RF = Tool:FindFirstChild("RF")
    if not RF or not RF:IsA("RemoteFunction") then
        return false, "ไม่พบ BuildingTool.RF"
    end

    local Relative = Data.Relative or GetPlayerZone(LocalPlayer)
    local BlockID = GetBlockID(Data.Name)
    if not Relative then return false, "ไม่พบโซนปลายทาง" end
    if BlockID == nil then return false, "ไม่พบ Block ID: " .. tostring(Data.Name) end

    return InvokeRemote(
        RF,
        Data.Name,
        BlockID,
        Relative,
        Relative.CFrame:ToObjectSpace(Data.Pos),
        Data.Anchored,
        Data.Pos,
        false
    )
end

local function IsSimilarSize(A, B, Tolerance)
    if not A or not B then return false end
    local D = VectorDiffNormalized(A, B)
    return D <= Tolerance
end

local function FindPlacedBlock(Folder, Data, BaselineInstances)
    if not Folder or not Data then return nil end
    local BestBlock = nil
    local BestScore = math.huge

    for _, Block in ipairs(Folder:GetChildren()) do
        if Block.Name == Data.Name then
            local PPart = Block:FindFirstChild("PPart")
            if PPart and PPart:IsA("BasePart") then
                local IsBaseline = BaselineInstances and BaselineInstances[Block] == true
                if not IsBaseline then
                    local Dist = Distance3(PPart.Position, Data.Pos.Position)
                    if Dist <= CONFIG.PositionTolerance then
                        local Profile = GetPartProfile(PPart)
                        local Score = Dist
                        if Profile then
                            Score = Score + VectorDiffNormalized(Profile.Size, Data.Size or PPart.Size) * 10
                            Score = Score + ColorDistance(Profile.Color, Data.Color) * 4
                        end
                        if Score < BestScore then
                            BestScore = Score
                            BestBlock = Block
                        end
                    end
                end
            end
        end
    end
    return BestBlock
end

local function SetAnchoredState(Block, WantAnchored)
    local PPart = Block and Block:FindFirstChild("PPart")
    if not PPart or not PPart:IsA("BasePart") then return false, "PPart ไม่พบ" end
    if PPart.Anchored == WantAnchored then return true end

    local Tool = EquipTool("PropertiesTool")
    if not Tool then return false, "ไม่พบ PropertiesTool" end

    local Remote = Tool:FindFirstChild("SetPropertieRF")
    if not Remote or not Remote:IsA("RemoteFunction") then
        return false, "ไม่พบ PropertiesTool.SetPropertieRF"
    end

    local Ok, Err = InvokeRemote(Remote, "Anchored", {Block})
    if not Ok then return false, Err end

    local Verified = WaitUntil(CONFIG.PropertyVerifyTimeout, function()
        return PPart.Anchored == WantAnchored
    end)
    return Verified, Verified and "ok" or "ตรวจ Anchored ไม่ผ่าน"
end

local function VerifyColor(PPart, Expected)
    if not PPart or not Expected then return true end
    return ColorDistance(PPart.Color, Expected) <= CONFIG.ColorTolerance
end

local function VerifySize(PPart, Expected)
    if not PPart or not Expected then return true end
    return IsSimilarSize(PPart.Size, Expected, CONFIG.SizeTolerance)
end

local function SetBooleanProperty(Block, PropertyName, ExpectedValue, ActualGetter)
    local Current = ActualGetter()
    if Current == ExpectedValue then
        return true, "ok"
    end

    local Tool = EquipTool("PropertiesTool")
    if not Tool then return false, "ไม่พบ PropertiesTool" end
    local Remote = Tool:FindFirstChild("SetPropertieRF")
    if not Remote or not Remote:IsA("RemoteFunction") then
        return false, "ไม่พบ PropertiesTool.SetPropertieRF"
    end

    local Ok, Err = InvokeRemote(Remote, PropertyName, {Block})
    if not Ok then return false, Err end

    local Verified = WaitUntil(CONFIG.PropertyVerifyTimeout, function()
        return ActualGetter() == ExpectedValue
    end)
    return Verified, Verified and "ok" or ("ตรวจ " .. tostring(PropertyName) .. " ไม่ผ่าน")
end

local function SetTransparencyProperty(Block, ExpectedValue)
    local PPart = Block and Block:FindFirstChild("PPart")
    if not PPart or not PPart:IsA("BasePart") then return false, "PPart ไม่พบ" end
    ExpectedValue = math.max(0, math.min(1, tonumber(ExpectedValue) or 0))
    if math.abs(PPart.Transparency - ExpectedValue) <= 0.01 then
        return true, "ok"
    end

    local Tool = EquipTool("PropertiesTool")
    if not Tool then return false, "ไม่พบ PropertiesTool" end
    local Remote = Tool:FindFirstChild("SetPropertieRF")
    if not Remote or not Remote:IsA("RemoteFunction") then
        return false, "ไม่พบ PropertiesTool.SetPropertieRF"
    end

    -- BABFT's documented transparency options are 0%, 25%, 50%, and 100%.
    -- The live tool cycles through supported options, so verify after every call
    -- and stop as soon as the requested value is reached.
    local Allowed = {0, 0.25, 0.5, 1}
    local TargetIndex = 1
    local BestDiff = math.huge
    for Index, Value in ipairs(Allowed) do
        local Diff = math.abs(Value - ExpectedValue)
        if Diff < BestDiff then
            BestDiff = Diff
            TargetIndex = Index
        end
    end

    for _ = 1, #Allowed + 1 do
        if math.abs(PPart.Transparency - Allowed[TargetIndex]) <= 0.01 then
            return true, "ok"
        end
        local Ok, Err = InvokeRemote(Remote, "Transparency", {Block})
        if not Ok then return false, Err end
        task.wait(0.05)
    end

    return math.abs(PPart.Transparency - Allowed[TargetIndex]) <= 0.01,
        "ตรวจ Transparency ไม่ผ่าน (ค่าปัจจุบัน " .. string.format("%.2f", PPart.Transparency) .. ")"
end

local function CustomizeBlock(Block, Data)
    if not Block or not Data then return false, "ข้อมูลไม่ครบ" end
    local PPart = Block:FindFirstChild("PPart")
    if not PPart or not PPart:IsA("BasePart") then return false, "PPart ไม่พบ" end

    -- Anchor
    UpdateStatusPhase("⚓ กำลังตั้งค่าการยึด...", Data.Name)
    local AnchorOk, AnchorErr = SetAnchoredState(Block, Data.Anchored)
    if not AnchorOk then
        return false, "⚓ " .. tostring(AnchorErr)
    end

    -- Scale
    UpdateStatusPhase("📏 กำลังปรับขนาด...", Data.Name)
    local ScalingTool = EquipTool("ScalingTool")
    if ScalingTool then
        local Remote = ScalingTool:FindFirstChild("RF")
        if Remote and Remote:IsA("RemoteFunction") then
            InvokeRemote(Remote, Block, Data.Size, Data.Pos)
        end
    end

    local SizeOk = WaitUntil(CONFIG.PropertyVerifyTimeout, function()
        return VerifySize(PPart, Data.Size)
    end)
    if Data.Size and not SizeOk then
        return false, "📏 ตรวจขนาดไม่ผ่าน"
    end

    -- Paint
    UpdateStatusPhase("🎨 กำลังระบายสี...", Data.Name)
    local PaintingTool = EquipTool("PaintingTool")
    if PaintingTool then
        local Remote = PaintingTool:FindFirstChild("RF")
        if Remote and Remote:IsA("RemoteFunction") then
            InvokeRemote(Remote, {{Block, Data.Color}})
        end
    end

    local ColorOk = WaitUntil(CONFIG.PropertyVerifyTimeout, function()
        return VerifyColor(PPart, Data.Color)
    end)
    if Data.Color and not ColorOk then
        return false, "🎨 ตรวจสีไม่ผ่าน"
    end

    -- Collision
    if Data.CanCollide ~= nil then
        UpdateStatusPhase("🧱 กำลังตั้งค่าการชน...", Data.Name)
        local CollisionOk, CollisionErr = SetBooleanProperty(
            Block,
            "Collision",
            Data.CanCollide,
            function() return PPart.CanCollide end
        )
        if not CollisionOk then
            -- Some block types may not expose this property. Treat that as a
            -- customization warning rather than destroying the whole copy.
            Notify("คำเตือน", "ตั้งค่าการชนไม่สำเร็จ: " .. tostring(CollisionErr), COLORS.Working)
        end
    end

    -- Cast shadow
    if Data.CastShadow ~= nil then
        UpdateStatusPhase("🌑 กำลังตั้งค่าเงา...", Data.Name)
        local ShadowOk, ShadowErr = SetBooleanProperty(
            Block,
            "CastShadow",
            Data.CastShadow,
            function() return PPart.CastShadow end
        )
        if not ShadowOk then
            Notify("คำเตือน", "ตั้งค่าเงาไม่สำเร็จ: " .. tostring(ShadowErr), COLORS.Working)
        end
    end

    -- Transparency
    if Data.Transparency ~= nil then
        UpdateStatusPhase("👻 กำลังตั้งค่าความโปร่งใส...", Data.Name)
        local TransparencyOk, TransparencyErr = SetTransparencyProperty(Block, Data.Transparency)
        if not TransparencyOk then
            Notify("คำเตือน", tostring(TransparencyErr), COLORS.Working)
        end
    end

    return true, "ok"
end

local function PlaceAndVerify(Export, DestFolder, CandidateCatalog, BaselineInstances)
    local Data, PrepErr = PreparePlacementData(Export, DestFolder, CandidateCatalog)
    if not Data then
        return nil, Export, PrepErr
    end

    local AnchorState, Reason = ShouldAnchor(Data, DestFolder)
    Data.Anchored = AnchorState

    local Prefix = Data.FallbackFrom and (Data.FallbackFrom .. " → " .. Data.Name) or Data.Name
    Notify(Data.FallbackFrom and "เปลี่ยนบล็อก" or "วางบล็อก", Prefix .. "\n" .. Reason, Data.FallbackFrom and COLORS.Working or COLORS.Mint)

    for Attempt = 1, CONFIG.MaxAttempts do
        if Attempt > 1 then
            UpdateStatus(0, 0, 1, "🔄 กำลังลองวางใหม่ ครั้งที่ " .. tostring(Attempt), Data.Name)
            task.wait(CONFIG.RetryBaseDelay * Attempt)
        end

        local PlaceOk = PlaceSingleBlock(Data)
        if PlaceOk then
            local Deadline = os.clock() + CONFIG.VerifyTimeout
            repeat
                local Block = FindPlacedBlock(DestFolder, Data, BaselineInstances)
                if Block then
                    local AnchorOk = SetAnchoredState(Block, AnchorState)
                    if AnchorOk then
                        return Block, Data, "ok"
                    end
                end
                task.wait(CONFIG.VerifyInterval)
            until os.clock() >= Deadline
        end
    end

    return nil, Data, "วางหรือยืนยันบล็อกไม่สำเร็จ"
end

-- ============================================================
-- Missing / final validation
-- ============================================================
local function FindEquivalentExistingBlock(DestFolder, Data)
    if not DestFolder or not Data then return nil end
    local Best = nil
    local BestScore = math.huge

    for _, Block in ipairs(DestFolder:GetChildren()) do
        local PPart = Block:FindFirstChild("PPart")
        if PPart and PPart:IsA("BasePart") then
            local Dist = Distance3(PPart.Position, Data.Pos.Position)
            if Dist <= CONFIG.PositionTolerance then
                local Profile = GetPartProfile(PPart)
                local Score = Dist
                if Block.Name == Data.Name then Score = Score - 3 end
                if Profile then
                    Score = Score + CalcFeatureScore(Data, Profile, Block.Name) * 0.2
                end
                if Score < BestScore then
                    BestScore = Score
                    Best = Block
                end
            end
        end
    end
    return Best
end

local function ReconcileExisting(BuildList, DestFolder, CandidateCatalog)
    local Queue = {}
    local Existing = GetExistingMap(DestFolder)

    for _, Data in ipairs(BuildList) do
        local ExactKey = BuildKey(Data.Name, Data.Pos)
        local Exact = ExactKey and Existing[ExactKey]
        if not Exact then
            local Prepared = PreparePlacementData(Data, DestFolder, CandidateCatalog)
            if Prepared then
                local Equivalent = FindEquivalentExistingBlock(DestFolder, Prepared)
                if not Equivalent then
                    table.insert(Queue, Data)
                end
            else
                table.insert(Queue, Data)
            end
        end
    end
    return Queue
end

-- ============================================================
-- Main copy
-- ============================================================
local function WaitIfCopyPaused()
    while CopyBusy and CopyPaused do
        UpdateStatusPhase("⏸️ หยุดชั่วคราว — กดปุ่มต่อเพื่อทำงานต่อ")
        task.wait(0.1)
    end
end

local function ToggleCopyPause()
    if not CopyBusy then
        Notify("สถานะการคัดลอก", "ยังไม่มีงานที่กำลังทำงาน", COLORS.Working)
        return
    end
    CopyPaused = not CopyPaused
    if CopyPaused then
        Notify("⏸️ หยุดชั่วคราว", "หยุดหลังจากบล็อกปัจจุบันเสร็จ", COLORS.Working)
        UpdateStatusPhase("⏸️ หยุดชั่วคราว — กำลังรอคำสั่งต่อ")
    else
        Notify("▶️ ทำงานต่อ", "ระบบคัดลอกทำงานต่อแล้ว", COLORS.Mint)
        UpdateStatusPhase("▶️ ทำงานต่อ")
    end
end

function RunCopyBuild(PlayerObj)
    if CopyBusy then
        Notify("แจ้งเตือน", "กำลังทำงานอยู่แล้ว", COLORS.Working)
        return
    end
    if not CopyEnabled then
        Notify("แจ้งเตือน", "ระบบถูกปิด", COLORS.Working)
        return
    end
    if not PlayerObj or PlayerObj == LocalPlayer then
        Notify("แจ้งเตือน", "เลือกผู้เล่นอื่น", COLORS.Working)
        return
    end

    CopyBusy = true
    CopyPaused = false
    CopyCancelRequested = false
    local WasCancelled = false
    local Success, ErrorMsg = pcall(function()
        pcall(RefreshCharacter)
        BlockData = LocalPlayer:FindFirstChild("Data")
        BlocksFolder = Workspace:FindFirstChild("Blocks")

        if not BlockData or not BlocksFolder then
            error("ไม่พบ Data หรือ Blocks ของเกม")
        end

        local DestFolder = FindPlayerBlockFolder(LocalPlayer)
        if not DestFolder then
            error("ไม่พบโฟลเดอร์บล็อกของคุณ")
        end

        UpdateStatus(0, 0, 0, "📡 กำลังอ่านข้อมูลต้นฉบับ...", PlayerObj.DisplayName, {})
        local BuildList = CaptureBuild(PlayerObj)
        if #BuildList == 0 then
            Notify("แจ้งเตือน", "ไม่พบบล็อกที่จะคัดลอก", COLORS.Working)
            UpdateStatus(0, 0, 0, "ไม่พบบล็อก", nil, {})
            return
        end

        UpdateStatus(#BuildList, 0, 0, "🔎 กำลังวิเคราะห์บล็อก...", nil, {})
        local CandidateCatalog = BuildCandidateCatalog(DestFolder)
        local PlaceQueue = ReconcileExisting(BuildList, DestFolder, CandidateCatalog)

        if #PlaceQueue == 0 then
            Notify("เสร็จสิ้น", "สิ่งปลูกสร้างตรงกันแล้ว")
            UpdateStatus(#BuildList, #BuildList, 0, "✅ เสร็จสิ้น — ไม่ต้องวางเพิ่ม", nil, {})
            return
        end

        Notify("เริ่มคัดลอก", "ต้องดำเนินการ " .. tostring(#PlaceQueue) .. " บล็อก", COLORS.Working)

        local PlacedCount = 0
        local FailedList = {}

        -- Snapshot current instances so verification can prefer newly created blocks.
        local BaselineInstances = {}
        for _, Block in ipairs(DestFolder:GetChildren()) do
            BaselineInstances[Block] = true
        end

        for Index, Data in ipairs(PlaceQueue) do
            if CopyCancelRequested or not CopyEnabled then
                WasCancelled = true
                break
            end
            WaitIfCopyPaused()
            if CopyCancelRequested or not CopyEnabled then
                WasCancelled = true
                break
            end
            UpdateStatus(#PlaceQueue, PlacedCount, #FailedList, "🔨 กำลังดำเนินการ...", Data.Name, FailedList)

            local Block, FinalData, PlaceErr = PlaceAndVerify(Data, DestFolder, CandidateCatalog, BaselineInstances)
            if Block then
                local Customized, CustomizeErr = CustomizeBlock(Block, FinalData)
                if Customized then
                    PlacedCount = PlacedCount + 1
                    BaselineInstances[Block] = true
                else
                    table.insert(FailedList, FinalData or Data)
                    Notify("ปรับแต่งไม่สำเร็จ", tostring(CustomizeErr), COLORS.Error)
                end
            else
                table.insert(FailedList, FinalData or Data)
                Notify("วางไม่สำเร็จ", tostring(PlaceErr or "ไม่ทราบสาเหตุ"), COLORS.Error)
            end

            UpdateStatus(#PlaceQueue, PlacedCount, #FailedList, "🔨 กำลังทำงาน...", Data.Name, FailedList)
            if Index % CONFIG.YieldEvery == 0 then
                task.wait()
            end
        end

        -- If the toggle was switched off, do not continue into retry work.
        if CopyCancelRequested or not CopyEnabled then
            WasCancelled = true
        end

        -- Retry phase: only accepts a newly-created matching instance; never repurposes an unrelated old block.
        if not WasCancelled and #FailedList > 0 then
            local RetryList = FailedList
            FailedList = {}
            Notify("ลองใหม่", "กำลังตรวจและลองใหม่ " .. tostring(#RetryList) .. " บล็อก", COLORS.Working)

            for Index, Data in ipairs(RetryList) do
                if CopyCancelRequested or not CopyEnabled then
                    WasCancelled = true
                    break
                end
                WaitIfCopyPaused()
                if CopyCancelRequested or not CopyEnabled then
                    WasCancelled = true
                    break
                end
                UpdateStatus(#PlaceQueue, PlacedCount, #RetryList, "🔄 กำลัง Retry...", Data.Name, RetryList)
                local FinalData = Data

                -- Do not grab an arbitrary nearby old block during retry.
                -- PlaceAndVerify searches for a block created after the baseline
                -- snapshot, preventing an unrelated block from being customized.
                local Block, ReturnedData = PlaceAndVerify(
                    Data, DestFolder, CandidateCatalog, BaselineInstances
                )
                FinalData = ReturnedData or FinalData

                if Block then
                    local Customized = CustomizeBlock(Block, FinalData)
                    if Customized then
                        PlacedCount = PlacedCount + 1
                        BaselineInstances[Block] = true
                    else
                        table.insert(FailedList, FinalData)
                    end
                else
                    table.insert(FailedList, FinalData)
                end

                UpdateStatus(#PlaceQueue, PlacedCount, #RetryList, "🔄 กำลัง Retry...", FinalData.Name, RetryList)
                if Index % 3 == 0 then task.wait() end
            end
        end

        if WasCancelled or CopyCancelRequested or not CopyEnabled then
            WasCancelled = true
            Notify("หยุดคัดลอกแล้ว", "หยุดตามคำสั่งปิดระบบ | ทำไปแล้ว " .. tostring(PlacedCount) .. " บล็อก", COLORS.Working)
            UpdateStatus(#PlaceQueue, PlacedCount, #FailedList, "⏹️ หยุดคัดลอกตามคำสั่ง", nil, FailedList)
        elseif #FailedList == 0 then
            Notify("สำเร็จ", "ดำเนินการครบ " .. tostring(PlacedCount) .. " บล็อก", COLORS.Mint)
            UpdateStatus(#PlaceQueue, PlacedCount, 0, "✅ เสร็จสิ้น — ครบทั้งหมด", nil, {})
        else
            Notify("เสร็จบางส่วน", "สำเร็จ: " .. tostring(PlacedCount) .. " | ขาด: " .. tostring(#FailedList), COLORS.Working)
            UpdateStatus(#PlaceQueue, PlacedCount, #FailedList, "⚠️ เสร็จบางส่วน", nil, FailedList)
        end
    end)

    CopyBusy = false
    CopyPaused = false
    CopyCancelRequested = false
    if not Success then
        Notify("ผิดพลาด", tostring(ErrorMsg), COLORS.Error)
        UpdateStatus(0, 0, 0, "❌ เกิดข้อผิดพลาด", tostring(ErrorMsg), {})
    end
end

-- ============================================================
-- Camera view
-- ============================================================
local function RestoreOwnCamera()
    local Camera = Workspace.CurrentCamera
    if Camera and Humanoid then
        Camera.CameraType = Enum.CameraType.Custom
        Camera.CameraSubject = Humanoid
    end
end

function SetViewEnabled(Enable)
    ViewEnabled = Enable
    if ViewConnection then
        ViewConnection:Disconnect()
        ViewConnection = nil
    end

    if not Enable then
        RestoreOwnCamera()
        Notify("ปิด View", "กล้องกลับมาที่ตัวคุณแล้ว")
        return
    end

    if not ViewTargetPlayer or not ViewTargetPlayer.Parent then
        Notify("แจ้งเตือน", "กรุณาเลือกผู้เล่นก่อน", COLORS.Working)
        ViewEnabled = false
        return
    end

    local Camera = Workspace.CurrentCamera
    if not Camera then
        ViewEnabled = false
        return
    end

    -- Delta-style View: use Roblox's normal camera to spectate the selected player.
    local function FollowTargetCharacter()
        if not ViewEnabled then return end
        local TargetChar = ViewTargetPlayer and ViewTargetPlayer.Character
        local TargetHumanoid = TargetChar and TargetChar:FindFirstChildOfClass("Humanoid")
        local CurrentCamera = Workspace.CurrentCamera
        if CurrentCamera and TargetHumanoid then
            CurrentCamera.CameraType = Enum.CameraType.Custom
            CurrentCamera.CameraSubject = TargetHumanoid
        end
    end

    FollowTargetCharacter()
    ViewConnection = RunService.RenderStepped:Connect(function()
        if not ViewEnabled then return end
        if not ViewTargetPlayer or not ViewTargetPlayer.Parent then
            SetViewEnabled(false)
            return
        end
        -- Re-apply after the target respawns or the camera subject changes.
        FollowTargetCharacter()
    end)

    Notify("เปิด View", "กำลังติดตาม: " .. ViewTargetPlayer.DisplayName)
end

-- ============================================================
-- Player list maintenance
-- ============================================================
Players.PlayerRemoving:Connect(function(Player)
    if TargetPlayer == Player then TargetPlayer = nil end
    if ViewTargetPlayer == Player then
        ViewTargetPlayer = nil
        if ViewEnabled then SetViewEnabled(false) end
    end
    DestroyTargetList()
end)

-- ============================================================
-- Initialize
-- ============================================================
CreateStatusUI()
UpdateStatus(0, 0, 0, "พร้อมใช้งาน", nil, {})
Notify("พร้อมใช้งาน", "WAN HUB V5 โหลดเสร็จสมบูรณ์", COLORS.Mint)
