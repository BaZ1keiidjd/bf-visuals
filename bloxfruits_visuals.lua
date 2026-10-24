--[[
    Blox Fruits — Visuals
    Клиентские визуальные настройки: всё меняется только у тебя на экране,
    другие игроки ничего не видят, на геймплей не влияет.

    Функции:
      • Fullbright   — светло даже ночью и в пещерах
      • Без тумана   — убирает туман и дымку (Atmosphere)
      • Время суток  — фиксирует утро / день / закат / ночь
      • Шейдеры      — пресеты цветокоррекции, bloom, лучи солнца
      • FOV          — угол обзора камеры
      • FPS Boost    — упрощает графику (действует до перезахода)

    RightShift — показать / скрыть меню (на телефоне — кнопка «–» в заголовке)
]]

local VERSION = "1.2"

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Если скрипт запущен повторно — сначала выгружаем старую копию.
-- В экзекуторах _G бывает своим у каждого запуска, поэтому храним
-- выгрузку в getgenv(), а старое меню на всякий случай ищем по имени.
local sharedEnv = (getgenv and getgenv()) or _G
for _, env in ipairs({ sharedEnv, _G }) do
    if env.BFVisualsUnload then
        pcall(env.BFVisualsUnload)
        env.BFVisualsUnload = nil
    end
end
for _, old in ipairs(playerGui:GetChildren()) do
    if old.Name == "BFVisuals" then
        old:Destroy()
    end
end

local running = true
local connections = {}
local resetters = {}

local function connect(signal, fn)
    local conn = signal:Connect(fn)
    table.insert(connections, conn)
    return conn
end

local function isPointerDown(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isPointerMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

---------------------------------------------------------------------
-- Состояние
---------------------------------------------------------------------
local state = {
    fullbright = false,
    noFog = false,
    clockTime = nil, -- nil = время как в игре
    fov = nil,       -- nil = FOV не трогаем
    fpsBoost = false,
}

local originalFOV = workspace.CurrentCamera.FieldOfView

---------------------------------------------------------------------
-- Fullbright
---------------------------------------------------------------------
local fullbrightSaved

local function setFullbright(on)
    state.fullbright = on
    if on then
        fullbrightSaved = {
            Brightness = Lighting.Brightness,
            Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            GlobalShadows = Lighting.GlobalShadows,
        }
    elseif fullbrightSaved then
        for prop, value in pairs(fullbrightSaved) do
            Lighting[prop] = value
        end
        fullbrightSaved = nil
    end
end

---------------------------------------------------------------------
-- Без тумана
-- Игра может делать туман тремя способами: обычный туман Lighting,
-- объект Atmosphere или полупрозрачные «туманные» детали — убираем все.
---------------------------------------------------------------------
local fogSaved
local hiddenAtmospheres = {} -- Atmosphere, вынутые из Lighting
local hiddenFogParts = setmetatable({}, { __mode = "k" }) -- [деталь] = исходный LocalTransparencyModifier

local function hideFogPart(obj)
    if not obj:IsA("BasePart") or obj.Transparency <= 0 or hiddenFogParts[obj] then
        return false
    end
    local name = string.lower(obj.Name)
    if not (string.find(name, "fog", 1, true) or string.find(name, "mist", 1, true)) then
        return false
    end
    hiddenFogParts[obj] = obj.LocalTransparencyModifier
    obj.LocalTransparencyModifier = 1
    return true
end

-- вызывается каждый кадр, пока включено
local function applyNoFog()
    if Lighting.FogEnd < 1e9 then
        Lighting.FogEnd = 9e9
    end
    -- Atmosphere работает только внутри Lighting. Если просто менять ей Density,
    -- игра перезаписывает значение обратно, поэтому вынимаем её целиком
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("Atmosphere") then
            table.insert(hiddenAtmospheres, child)
            child.Parent = nil
        end
    end
end

-- отчёт в консоль (F9) — пригодится, если туман всё равно остался
local function printFogReport(foundParts)
    local children = {}
    for _, child in ipairs(Lighting:GetChildren()) do
        table.insert(children, child.Name .. " (" .. child.ClassName .. ")")
    end
    print(string.format(
        "[BF Visuals] Без тумана: FogEnd был %.0f, убрано Atmosphere: %d, скрыто туманных деталей: %d",
        fogSaved.FogEnd, #hiddenAtmospheres, foundParts
    ))
    print("[BF Visuals] Lighting: " .. table.concat(children, ", "))
end

local function setNoFog(on)
    state.noFog = on
    if on then
        fogSaved = { FogEnd = Lighting.FogEnd }
        applyNoFog()
        -- ищем туманные детали по всей карте порциями, чтобы не было фриза
        task.spawn(function()
            local found = 0
            for i, obj in ipairs(workspace:GetDescendants()) do
                if not state.noFog then
                    return
                end
                if hideFogPart(obj) then
                    found = found + 1
                end
                if i % 2000 == 0 then
                    task.wait()
                end
            end
            if state.noFog then
                printFogReport(found)
            end
        end)
    elseif fogSaved then
        Lighting.FogEnd = fogSaved.FogEnd
        for _, atmosphere in ipairs(hiddenAtmospheres) do
            atmosphere.Parent = Lighting
        end
        table.clear(hiddenAtmospheres)
        for part, modifier in pairs(hiddenFogParts) do
            part.LocalTransparencyModifier = modifier
        end
        table.clear(hiddenFogParts)
        fogSaved = nil
    end
end

-- если игра меняет туман посреди кадра — сразу возвращаем
connect(Lighting:GetPropertyChangedSignal("FogEnd"), function()
    if state.noFog then
        applyNoFog()
    end
end)

-- туманные детали, которые появляются позже (ивенты, погода)
connect(workspace.DescendantAdded, function(obj)
    if state.noFog then
        hideFogPart(obj)
    end
end)

---------------------------------------------------------------------
-- Время суток
---------------------------------------------------------------------
local timeOptions = {
    { name = "Как в игре" },
    { name = "Утро", clock = 7 },
    { name = "День", clock = 13 },
    { name = "Закат", clock = 18 },
    { name = "Ночь", clock = 0 },
}
local clockSaved

local function setTime(option)
    if option.clock then
        if not state.clockTime then
            clockSaved = Lighting.ClockTime
        end
        state.clockTime = option.clock
    else
        state.clockTime = nil
        if clockSaved then
            Lighting.ClockTime = clockSaved
            clockSaved = nil
        end
    end
end

---------------------------------------------------------------------
-- Шейдеры
---------------------------------------------------------------------
local shaderPresets = {
    { name = "Выкл" },
    {
        name = "Сочные",
        cc = { Saturation = 0.3, Contrast = 0.1, Brightness = 0.02 },
        bloom = { Intensity = 0.5, Size = 24, Threshold = 0.95 },
        rays = { Intensity = 0.05, Spread = 0.7 },
    },
    {
        name = "Кино",
        cc = { Saturation = -0.1, Contrast = 0.2, TintColor = Color3.fromRGB(255, 235, 215) },
        bloom = { Intensity = 0.3, Size = 30, Threshold = 0.9 },
        dof = { FarIntensity = 0.15, FocusDistance = 60, InFocusRadius = 60, NearIntensity = 0 },
    },
    {
        name = "Ч/Б",
        cc = { Saturation = -1, Contrast = 0.15 },
    },
}

local effectClasses = {
    cc = "ColorCorrectionEffect",
    bloom = "BloomEffect",
    rays = "SunRaysEffect",
    dof = "DepthOfFieldEffect",
}
local activeEffects = {}

local function applyShader(preset)
    for _, effect in ipairs(activeEffects) do
        effect:Destroy()
    end
    table.clear(activeEffects)

    for key, className in pairs(effectClasses) do
        local props = preset[key]
        if props then
            local effect = Instance.new(className)
            effect.Name = "BFVisuals"
            for prop, value in pairs(props) do
                effect[prop] = value
            end
            effect.Parent = Lighting
            table.insert(activeEffects, effect)
        end
    end
end

---------------------------------------------------------------------
-- FPS Boost (без отката — чтобы вернуть графику, перезайди в игру)
---------------------------------------------------------------------
local function optimize(obj)
    if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
        or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
        obj.Enabled = false
    elseif obj:IsA("Decal") or obj:IsA("Texture") then
        obj.Transparency = 1
    elseif obj:IsA("BasePart") then
        obj.Material = Enum.Material.SmoothPlastic
        obj.Reflectance = 0
        obj.CastShadow = false
    end
end

local function enableFpsBoost()
    if state.fpsBoost then
        return
    end
    state.fpsBoost = true

    local terrain = workspace.Terrain
    terrain.WaterWaveSize = 0
    terrain.WaterWaveSpeed = 0
    terrain.WaterReflectance = 0

    -- новые объекты (эффекты скиллов, подгружаемые острова)
    connect(workspace.DescendantAdded, function(obj)
        pcall(optimize, obj)
    end)

    -- карта большая, поэтому обрабатываем порциями, чтобы не было фриза
    task.spawn(function()
        for i, obj in ipairs(workspace:GetDescendants()) do
            if not running then
                break
            end
            pcall(optimize, obj)
            if i % 1000 == 0 then
                task.wait()
            end
        end
    end)
end

---------------------------------------------------------------------
-- Каждый кадр поддерживаем выбранные настройки
-- (игра сама меняет освещение — день/ночь, острова, ивенты).
-- Применяем в самом конце рендер-шага, чтобы перебить скрипты игры.
---------------------------------------------------------------------
local RENDER_STEP_NAME = "BFVisuals"

local function enforce()
    if state.fullbright then
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.fromRGB(180, 180, 180)
        Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
    end
    if state.fullbright or state.fpsBoost then
        Lighting.GlobalShadows = false
    end
    if state.noFog then
        applyNoFog()
    end
    if state.clockTime then
        Lighting.ClockTime = state.clockTime
    end
    if state.fov then
        workspace.CurrentCamera.FieldOfView = state.fov
    end
end

connect(RunService.RenderStepped, enforce)
RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Last.Value + 1, enforce)

---------------------------------------------------------------------
-- Интерфейс
---------------------------------------------------------------------
local COLORS = {
    background = Color3.fromRGB(22, 22, 28),
    header = Color3.fromRGB(32, 32, 42),
    off = Color3.fromRGB(46, 46, 58),
    on = Color3.fromRGB(64, 132, 255),
    danger = Color3.fromRGB(170, 60, 60),
    text = Color3.fromRGB(235, 235, 245),
    dim = Color3.fromRGB(150, 150, 165),
}

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = obj
end

local gui = Instance.new("ScreenGui")
gui.Name = "BFVisuals"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 100 -- поверх интерфейса игры
gui.Parent = playerGui

local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0)
main.Position = UDim2.new(0.5, 0, 0.2, 0)
main.Size = UDim2.fromOffset(240, 0)
main.AutomaticSize = Enum.AutomaticSize.Y
main.BackgroundColor3 = COLORS.background
main.BorderSizePixel = 0
main.Parent = gui
corner(main, 8)

local mainLayout = Instance.new("UIListLayout")
mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
mainLayout.Parent = main

local header = Instance.new("TextLabel")
header.LayoutOrder = 1
header.Size = UDim2.new(1, 0, 0, 34)
header.BackgroundColor3 = COLORS.header
header.BorderSizePixel = 0
header.Active = true
header.Font = Enum.Font.GothamBold
header.TextSize = 14
header.TextColor3 = COLORS.text
header.TextXAlignment = Enum.TextXAlignment.Left
header.Text = "  Blox Fruits Visuals v" .. VERSION
header.Parent = main
corner(header, 8)

local minimize = Instance.new("TextButton")
minimize.AnchorPoint = Vector2.new(1, 0.5)
minimize.Position = UDim2.new(1, -6, 0.5, 0)
minimize.Size = UDim2.fromOffset(24, 24)
minimize.BackgroundColor3 = COLORS.off
minimize.BorderSizePixel = 0
minimize.Font = Enum.Font.GothamBold
minimize.TextSize = 16
minimize.TextColor3 = COLORS.text
minimize.Text = "–"
minimize.Parent = header
corner(minimize, 6)

local content = Instance.new("Frame")
content.LayoutOrder = 2
content.Size = UDim2.new(1, 0, 0, 0)
content.AutomaticSize = Enum.AutomaticSize.Y
content.BackgroundTransparency = 1
content.Parent = main

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.Parent = content

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 6)
contentLayout.Parent = content

connect(minimize.MouseButton1Click, function()
    content.Visible = not content.Visible
    minimize.Text = content.Visible and "–" or "+"
end)

-- перетаскивание окна за заголовок
do
    local dragging, dragStart, startPos
    connect(header.InputBegan, function(input)
        if isPointerDown(input) then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and isPointerMove(input) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if isPointerDown(input) then
            dragging = false
        end
    end)
end

connect(UserInputService.InputBegan, function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
    end
end)

---------------------------------------------------------------------
-- Выгрузка: всё выключаем и возвращаем как было
---------------------------------------------------------------------
local function unload()
    if not running then
        return
    end
    running = false
    for _, reset in ipairs(resetters) do
        pcall(reset)
    end
    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
    if state.fov then
        workspace.CurrentCamera.FieldOfView = originalFOV
    end
    gui:Destroy()
    sharedEnv.BFVisualsUnload = nil
end
sharedEnv.BFVisualsUnload = unload

---------------------------------------------------------------------
-- Элементы меню
---------------------------------------------------------------------
local layoutOrder = 0

local function add(obj)
    layoutOrder = layoutOrder + 1
    obj.LayoutOrder = layoutOrder
    obj.Parent = content
    return obj
end

local function makeButton(text, color)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, 30)
    button.BackgroundColor3 = color or COLORS.off
    button.BorderSizePixel = 0
    button.AutoButtonColor = true
    button.Font = Enum.Font.GothamMedium
    button.TextSize = 13
    button.TextColor3 = COLORS.text
    button.Text = text
    corner(button)
    return add(button)
end

local function makeToggle(text, callback)
    local button = makeButton(text .. ": ВЫКЛ")
    local on = false
    local function set(value)
        on = value
        button.Text = text .. (on and ": ВКЛ" or ": ВЫКЛ")
        button.BackgroundColor3 = on and COLORS.on or COLORS.off
        callback(on)
    end
    connect(button.MouseButton1Click, function()
        set(not on)
    end)
    table.insert(resetters, function()
        set(false)
    end)
end

local function makeCycle(text, options, callback)
    local button = makeButton(text .. ": " .. options[1].name)
    local index = 1
    local function set(i)
        index = i
        button.Text = text .. ": " .. options[i].name
        button.BackgroundColor3 = i == 1 and COLORS.off or COLORS.on
        callback(options[i])
    end
    connect(button.MouseButton1Click, function()
        set(index % #options + 1)
    end)
    table.insert(resetters, function()
        set(1)
    end)
end

local function makeSlider(text, min, max, default, callback)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 38)
    holder.BackgroundTransparency = 1
    add(holder)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 18)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextColor3 = COLORS.dim
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = text .. ": " .. default
    label.Parent = holder

    local bar = Instance.new("Frame")
    bar.Position = UDim2.fromOffset(0, 24)
    bar.Size = UDim2.new(1, 0, 0, 10)
    bar.BackgroundColor3 = COLORS.off
    bar.BorderSizePixel = 0
    bar.Active = true
    bar.Parent = holder
    corner(bar, 5)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = COLORS.on
    fill.BorderSizePixel = 0
    fill.Parent = bar
    corner(fill, 5)

    local dragging = false
    local function update(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local value = math.floor(min + (max - min) * rel + 0.5)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        label.Text = text .. ": " .. value
        callback(value)
    end

    connect(bar.InputBegan, function(input)
        if isPointerDown(input) then
            dragging = true
            update(input.Position.X)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and isPointerMove(input) then
            update(input.Position.X)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if isPointerDown(input) then
            dragging = false
        end
    end)
end

local function makeHint(text)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 16)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextColor3 = COLORS.dim
    label.Text = text
    add(label)
end

makeToggle("Fullbright", setFullbright)
makeToggle("Без тумана", setNoFog)
makeCycle("Время", timeOptions, setTime)
makeCycle("Шейдеры", shaderPresets, applyShader)
makeSlider("FOV", 50, 120, math.clamp(math.floor(originalFOV + 0.5), 50, 120), function(value)
    state.fov = value
end)

local fpsButton = makeButton("FPS Boost")
connect(fpsButton.MouseButton1Click, function()
    enableFpsBoost()
    fpsButton.Text = "FPS Boost: ВКЛ (до перезахода)"
    fpsButton.BackgroundColor3 = COLORS.on
end)

local unloadButton = makeButton("Выгрузить скрипт", COLORS.danger)
connect(unloadButton.MouseButton1Click, unload)

makeHint("RightShift — скрыть / показать меню")

print("[BF Visuals] v" .. VERSION .. " загружен")
