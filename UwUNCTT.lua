--[[
UwUNCTT 2.2 | Credits: nctt | Mobile controls first / PC fallback

PHẠM VI THỰC TẾ
  Đây là menu client tự dựng, không tải UI hay thư viện từ bên ngoài.
  Chưa chạy kiểm chứng trong TSB hoặc trên các executor được người dùng liệt kê.
  Tự dò API giúp thoái lui khi API thiếu; không chứng minh tương thích mọi executor.
  Không có anti-ban tuyệt đối. pcall bắt lỗi Lua, KHÔNG chặn kick từ máy chủ.
  Di chuyển nội suy KHÔNG bảo đảm qua kiểm tra vị trí của máy chủ.
  Không giả RemoteEvent, không sửa quyền mua emote, máu hay nhân vật người khác.
  Không có Void All Players, Godmode máy chủ, tàng hình với người khác, hoặc
  reset cooldown dash của TSB. Các giới hạn này được ghi trong menu.

THIẾT LẬP COMBAT
  Tab Farm có nút bắt đầu một lần: tự chọn mục tiêu, tiếp cận và gửi M1.
  Có thể dùng nút M1 thật của game qua firesignal/getconnections nếu API có.
  Trên điện thoại KHÔNG gửi chuột/phím PC: giữ nguyên HUD cảm ứng của game.
  Auto M1 / 1–4 chỉ gửi input hoặc gọi handler nút game; server quyết định
  cooldown, đánh trúng, sát thương và kill. Không tự bỏ qua cooldown server.
  Tab Counter ghi các AnimationId quan sát được: chọn đúng chiêu, gán nhóm
  Block / Counter / Ultimate và tên hiển thị. Danh sách ban đầu RỖNG.
  Tab Combat đọc thuộc tính thực của Player/Character. Để mục tiêu bật nộ rồi
  chọn cờ thể hiện trạng thái ĐANG nộ, không chọn chỉ số thanh tích nộ.
  Dữ liệu thiếu mặc định được coi là chưa rõ; không đoán tên thuộc tính TSB.

ĐIỀU KHIỂN
  RightShift: hiện/ẩn menu. F8 hoặc DỪNG: tắt tính năng, khôi phục thay đổi.
  J: lướt tự tạo nếu đã bật. Fly: WASD / joystick, Space / Ctrl, nút LÊN/XUỐNG.
  Mở menu tạm dừng input và bám mục tiêu; thu gọn menu để tiếp tục.
  X gỡ menu, nhả input, dừng animation, ngắt kết nối và hủy đồ họa do menu tạo.

EMOTE / FPS
  AnimationId phải có quyền sử dụng và đúng rig. Không mở quyền emote trả phí.
  FPS cap chỉ bật nếu đọc được cap gốc và có API đặt cap để có thể khôi phục.
  Không gọi GC cưỡng bức định kỳ hoặc xóa bừa Parts của map.

API references:
  https://create.roblox.com/docs/reference/engine/classes/Animator
  https://create.roblox.com/docs/reference/engine/classes/VirtualInputManager
  https://create.roblox.com/docs/animation/using
  https://create.roblox.com/docs/scripting/security/client-server-boundary
]]

-- 01. Services, capability detection, runtime ownership.
local Players = game:GetService("Players")
local Run = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Tween = game:GetService("TweenService")
local World = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Me = Players.LocalPlayer
assert(Me, "UwUNCTT phải chạy ở phía client.")
local PlayerGui = Me:WaitForChild("PlayerGui", 15)
assert(PlayerGui, "PlayerGui chưa sẵn sàng.")
local Env = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then Env = value end
end
local roots = {Env, _G}
if type(getfenv) == "function" then
    local ok, value = pcall(getfenv, 0)
    if ok and type(value) == "table" then table.insert(roots, value) end
end
local function api(name)
    for _, root in ipairs(roots) do
        local ok, value = pcall(function() return root[name] end)
        if ok and type(value) == "function" then return value end
    end
    return nil
end
local Caps = {
    gethui = api("gethui"), identify = api("identifyexecutor"),
    click = api("mouse1click"), down = api("mouse1press"), up = api("mouse1release"),
    keydown = api("keypress"), keyup = api("keyrelease"),
    fpsset = api("setfpscap"), fpsget = api("getfpscap"), touch = api("firetouchinterest"),
    signal = api("firesignal"), connections = api("getconnections"),
    asset = api("getcustomasset") or api("getsynasset"),
    write = api("writefile"), exists = api("isfile"),
}
local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)
local executor = "Không nhận diện"
if Caps.identify then
    local ok, name = pcall(Caps.identify)
    if ok then executor = tostring(name):sub(1, 42) end
end
local RUNTIME_KEY = "UwUNCTT_Runtime_v2"
for _, key in ipairs({RUNTIME_KEY, "NCTT_MENU_RUNTIME_V1"}) do
    local old = Env[key]
    if type(old) == "table" and type(old.unload) == "function" then pcall(old.unload) end
end
local App = {
    alive = true, connections = {}, watchers = {}, bags = {}, errors = {},
    inputs = {}, rejected = {}, keys = {}, refreshers = {}, owned = {}, esp = {},
    selected = nil, current = nil, saved = nil, lastGround = nil, goal = nil,
    recent = {}, recentOrder = {}, animations = {}, seenTrack = setmetatable({}, {__mode = "k"}),
    activeSkills = {}, binding = nil, queue = {}, queueIndex = 1, scanVersion = 0,
    pauseUntil = 0, reactionAt = 0, lastAttack = 0, lastSkill = 0, skillIndex = 1,
    inputBackend = "Chưa gửi M1", lastInputError = "", inputFailures = {},
    farmPhase = "ĐÃ DỪNG", farmReason = "Bấm BẮT ĐẦU AUTO FARM.", farmSent = 0,
    farmTargetId = nil, farmHealth = nil, farmDamageAt = 0, lastFollowAt = -math.huge,
    guiScanAt = -math.huge, m1Mode = "Tự động", teleMode = "Nhanh",
    platform = "Tự động", actionButtons = {}, autoButtons = {}, buttonModes = {},
    touchDevice = Input.TouchEnabled == true, flyTouches = {up = {}, down = {}},
    lastAction = -math.huge, manualUntil = 0, lastGuiPaint = -math.huge,
    logicAt = 0, groundAt = 0, localAt = 0, espAt = 0, fpsFrames = 0, fpsTime = 0, fps = 0,
    flags = {
        safe = false, anonymous = false, antiVoid = false, hidden = false,
        lock = false, m1 = false, skills = false, switchAwake = false, missingInactive = false,
        farm = false, farmSkills = true, farmPaused = false,
        block = false, dodge = false, ultDodge = false, loopEmote = true,
        speed = false, fly = false, dash = false, stabilize = false,
        esp = false, boxes = true, tracers = false, chams = true,
        potato = false, bright = false, fragments = false, fpsCap = false,
    },
    values = {
        speed = 28, fly = 48, travel = 115, radius = 18, distance = 3.5,
        retreat = 30, voidY = -50, m1Gap = 0.24, skillGap = 0.45,
        espDistance = 500, fpsCap = 120, dashLength = 12,
        targetRange = 500, attackRange = 6.5, teleInterval = 0.2, guiFade = 55,
    },
    targetMode = "Chọn thủ công", ultMode = "Ra xa", aliasSerial = 0, aliases = {},
}
Env[RUNTIME_KEY] = App
local function disconnect(list)
    for _, connection in ipairs(list or {}) do pcall(function() connection:Disconnect() end) end
end
function App.unload()
    if not App.alive then return end
    if App.stopAll then pcall(App.stopAll) end
    App.alive = false
    pcall(function() Run:UnbindFromRenderStep("UwUNCTT_Render_v2") end)
    disconnect(App.connections)
    for _, watcher in pairs(App.watchers) do disconnect(watcher.connections); disconnect(watcher.character) end
    if App.cameraConnection then App.cameraConnection:Disconnect() end
    if App.gui then pcall(function() App.gui:Destroy() end) end
    if App.effects then pcall(function() App.effects:Destroy() end) end
    if Env[RUNTIME_KEY] == App then Env[RUNTIME_KEY] = nil end
end
function App.bind(signal, callback, bucket)
    local connection = signal:Connect(callback)
    table.insert(bucket or App.connections, connection)
    return connection
end
function App.notify(title, message)
    if App.toast then App.toast(tostring(title), tostring(message or ""))
    else warn("[UwUNCTT] " .. tostring(title) .. " " .. tostring(message or "")) end
end
function App.try(label, callback, ...)
    local ok, result = pcall(callback, ...)
    if not ok and os.clock() - (App.errors[label] or -math.huge) > 4 then
        App.errors[label] = os.clock()
        App.notify(label, tostring(result):sub(1, 180))
    end
    return ok, result
end
function App.refresh()
    for _, refresh in ipairs(App.refreshers) do pcall(refresh) end
end
function App.name(player)
    if not App.flags.anonymous then return player.DisplayName .. "  @" .. player.Name end
    if not App.aliases[player.UserId] then
        App.aliasSerial = App.aliasSerial + 1
        App.aliases[player.UserId] = string.format("Player %02d", App.aliasSerial)
    end
    return App.aliases[player.UserId]
end
function App.parts(player)
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if character and character.Parent and humanoid and humanoid.Health > 0
        and root and root:IsA("BasePart") then return character, humanoid, root end
    return nil
end
function App.selectedPlayer()
    return App.selected and Players:GetPlayerByUserId(App.selected) or nil
end

-- Property snapshots are weak-keyed; each group owns its own properties.
function App.patch(group, object, property, value)
    local bag = App.bags[group]
    if not bag then bag = setmetatable({}, {__mode = "k"}); App.bags[group] = bag end
    local record = bag[object]
    if not record then record = {}; bag[object] = record end
    if record[property] == nil then
        local ok, original = pcall(function() return object[property] end)
        if not ok then return false end
        record[property] = {value = original}
    end
    return pcall(function() object[property] = value end)
end
function App.restore(group)
    local bag = App.bags[group]
    if not bag then return end
    for object, record in pairs(bag) do
        for property, entry in pairs(record) do
            pcall(function() object[property] = entry.value end)
        end
    end
    App.bags[group] = nil
end

-- 02. Input adapter. No RemoteEvents or assumed TSB endpoints.
local virtualKeys = {One = 0x31, Two = 0x32, Three = 0x33, Four = 0x34, F = 0x46}
local skillSlots = {One = "1", Two = "2", Three = "3", Four = "4"}
function App.isMobile()
    if App.platform == "Điện thoại" then return true end
    if App.platform == "PC" then return false end
    return App.touchDevice
end
function App.release(key)
    local held = App.inputs[key]
    if not held then return end
    App.inputs[key] = nil
    pcall(held.release)
end
function App.releaseAll(owner)
    local keys = {}
    for key, held in pairs(App.inputs) do
        if not owner or owner == held.owner then table.insert(keys, key) end
    end
    for _, key in ipairs(keys) do App.release(key) end
end
function App.visibleGameButton(button)
    if not button or not button.Parent or not button:IsA("GuiButton") then return false end
    if App.gui and button:IsDescendantOf(App.gui) then return false end
    if not button:IsDescendantOf(PlayerGui) then return false end
    local node = button
    while node and node ~= PlayerGui do
        if node:IsA("GuiObject") and node.Visible == false then return false end
        if node:IsA("ScreenGui") and node.Enabled == false then return false end
        node = node.Parent
    end
    return true
end
function App.gameButtons()
    local buttons = {}
    for _, object in ipairs(PlayerGui:GetDescendants()) do
        if object:IsA("GuiButton") and App.visibleGameButton(object) then table.insert(buttons, object) end
    end
    return buttons
end
function App.punchButton()
    if App.visibleGameButton(App.boundPunch) then return App.boundPunch end
    if App.visibleGameButton(App.autoPunch) then return App.autoPunch end
    if os.clock() - App.guiScanAt < 1 then return nil end
    App.guiScanAt = os.clock()
    local names = {punch=true,punchbutton=true,attack=true,attackbutton=true,m1=true,m1button=true,basicattack=true,mobilepunch=true,mobileattack=true}
    local candidate, count = nil, 0
    for _, button in ipairs(App.gameButtons()) do
        local name = string.lower(button.Name):gsub("[^%w]", "")
        local text = button:IsA("TextButton") and string.lower(button.Text):gsub("%s", "") or ""
        if names[name] or names[text] then candidate, count = button, count + 1 end
    end
    if count == 1 then App.autoPunch = candidate; return candidate end
    return nil
end
function App.actionButton(key)
    if key == "M1" then return App.punchButton() end
    if App.visibleGameButton(App.actionButtons[key]) then return App.actionButtons[key] end
    if App.visibleGameButton(App.autoButtons[key]) then return App.autoButtons[key] end
    local now = os.clock()
    App.actionScan = App.actionScan or {}
    if now - (App.actionScan[key] or -math.huge) < 0.7 then return nil end
    App.actionScan[key] = now
    local slot, best, score, tied = skillSlots[key], nil, 0, false
    for _, button in ipairs(App.gameButtons()) do
        local name = string.lower(button.Name):gsub("[^%w]", "")
        local rank = 0
        if key == "F" then
            if name == "block" or name == "blockbutton" or name == "defend" or name == "mobileblock" then rank = 10 end
        elseif slot then
            if name == "skill" .. slot or name == "ability" .. slot or name == "move" .. slot then rank = 10 end
            local context, parentSlot, parent = false, false, button.Parent
            for _ = 1, 5 do
                if not parent or parent == PlayerGui then break end
                local label = string.lower(parent.Name)
                if label:find("hotbar", 1, true) or label:find("backpack", 1, true)
                    or label:find("skill", 1, true) or label:find("abilit", 1, true) then context = true end
                if parent.Name == slot then parentSlot = true end
                parent = parent.Parent
            end
            if context and parentSlot then rank = math.max(rank, 7) end
            if context and (name == slot or name == "slot" .. slot) then rank = math.max(rank, 9) end
            if context then
                for _, child in ipairs(button:GetDescendants()) do
                    if (child:IsA("TextLabel") or child:IsA("TextButton")) and tostring(child.Text):match("^%s*" .. slot .. "%s*$") then
                        rank = math.max(rank, 8)
                    end
                end
            end
        end
        if rank > score then best, score, tied = button, rank, false
        elseif rank > 0 and rank == score then tied = true end
    end
    if best and not tied then App.autoButtons[key] = best; return best end
    return nil
end
function App.guiHasHandlers(signal)
    if not Caps.connections then return nil end
    local ok, connections = pcall(Caps.connections, signal)
    if not ok or type(connections) ~= "table" then return nil end
    for _, connection in ipairs(connections) do
        local read, enabled = pcall(function() return connection.Enabled end)
        if not read or enabled ~= false then return true end
    end
    return false
end
function App.emitGui(signal, ...)
    if App.guiHasHandlers(signal) == false then return false end
    if Caps.signal then
        local ok, result = pcall(Caps.signal, signal, ...)
        if ok and result ~= false then return true end
        if not ok then App.inputFailures.GUI = tostring(result) end
    end
    if Caps.connections then
        local ok, connections = pcall(Caps.connections, signal)
        if ok and type(connections) == "table" then
            local called = 0
            for _, connection in ipairs(connections) do
                local read, fn, enabled = pcall(function() return connection.Function, connection.Enabled end)
                if read and enabled ~= false and type(fn) == "function" then
                    local worked = pcall(fn, ...)
                    if worked then called = called + 1 end
                end
            end
            if called > 0 then return true end
        end
    end
    return false
end
function App.pressGameButton(key)
    key = key or "M1"
    if not Caps.signal and not Caps.connections then return nil end
    local button = App.actionButton(key)
    if not button then return nil end
    if App.isMobile() then
        local route = App.buttonModes[key]
        if not route or route == "Tự động" then
            if key == "F" and App.guiHasHandlers(button.MouseButton1Down) == true then route = "Nhấn/Thả"
            elseif App.guiHasHandlers(button.Activated) == true then route = "Activated"
            elseif App.guiHasHandlers(button.MouseButton1Click) == true then route = "Click"
            elseif App.guiHasHandlers(button.InputBegan) == true then route = "Touch"
            elseif App.guiHasHandlers(button.TouchTap) == true then route = "TouchTap"
            elseif App.guiHasHandlers(button.MouseButton1Down) == true then route = "Nhấn/Thả"
            else route = (key == "M1" or key == "F") and "Nhấn/Thả" or "Activated" end
        end
        local x, y = button.AbsolutePosition.X + button.AbsoluteSize.X / 2, button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2
        local release, sent
        if route == "Touch" then
            if not App.lastTouch then return nil end
            local touch = App.lastTouch
            sent = App.emitGui(button.InputBegan, touch)
            release = function() App.emitGui(button.InputEnded, touch) end
        elseif route == "Nhấn/Thả" then
            sent = App.emitGui(button.MouseButton1Down, x, y)
            release = function() App.emitGui(button.MouseButton1Up, x, y) end
        elseif route == "TouchTap" then
            sent = App.emitGui(button.TouchTap, {Vector2.new(x, y)})
        elseif route == "Click" then sent = App.emitGui(button.MouseButton1Click)
        else sent = App.emitGui(button.Activated, App.lastTouch, 1) end
        if sent then
            App.inputBackend = "Mobile · " .. key .. " · " .. route
            return release or function() end
        end
        return nil
    end
    local activated = App.m1Mode == "GUI Activated"
    if App.m1Mode == "Tự động" and App.guiHasHandlers(button.MouseButton1Down) == false
        and App.guiHasHandlers(button.Activated) == true then activated = true end
    if activated then
        if App.emitGui(button.Activated, nil, 1) then
            App.inputBackend = "Nút game: Activated"
            return function() end
        end
    else
        local x = button.AbsolutePosition.X + button.AbsoluteSize.X / 2
        local y = button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2
        if App.emitGui(button.MouseButton1Down, x, y) then
            App.inputBackend = "Nút game: nhấn/thả"
            return function() App.emitGui(button.MouseButton1Up, x, y) end
        end
    end
    return nil
end
function App.press(key, duration, owner)
    if App.inputs[key] then return false, "Đang giữ thao tác trước", false end
    if App.focused == false then return false, "Cửa sổ mất focus", false end
    if App.panel and App.panel.Visible then return false, "Menu đang mở", false end
    if App.captureAction then return false, "Đang gán nút cảm ứng", false end
    if Input:GetFocusedTextBox() or GuiService.MenuIsOpen then return false, "Đang dùng giao diện", false end
    if owner == "combat" and os.clock() < App.manualUntil then return false, "Ưu tiên thao tác tay", false end
    if App.isMobile() then
        local button = App.actionButton(key)
        if not button then
            local reason = "Chưa tìm thấy nút " .. key .. ". Mở tab Nút MB rồi gán bằng một lần chạm."
            App.lastInputError = reason
            return false, reason, false
        end
        local release = App.pressGameButton(key)
        if not release then
            local reason = "Nút " .. key .. " chưa nhận handler cảm ứng. Gán lại nút / chọn sự kiện trong Nút MB."
            App.lastInputError = reason
            return false, reason, false
        end
        App.inputs[key] = {release = release, untilTime = os.clock() + duration, owner = owner}
        App.lastInputError = ""
        return true
    end
    local camera = World.CurrentCamera
    if not camera then return false, "Camera chưa sẵn sàng", false end
    local release
    if key == "M1" then
        local viewport, inset = camera.ViewportSize, GuiService:GetGuiInset()
        local x, y = math.floor(viewport.X * 0.5), math.floor(viewport.Y * 0.42 + inset.Y)
        if App.m1Mode ~= "Input" then release = App.pressGameButton() end
        local inputAllowed = App.m1Mode == "Input" or App.m1Mode == "Tự động"
        if not release and inputAllowed and VIM and not App.rejected.mouse then
            local ok, result = pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 0) end)
            if ok and result ~= false then
                release = function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 0) end
                App.inputBackend = "VirtualInputManager"
            else App.rejected.mouse = true; App.inputFailures.VIM = tostring(result) end
        end
        if not release then
            local canClick = inputAllowed and Caps.click and not App.rejected.click
            local canPair = inputAllowed and Caps.down and Caps.up and not App.rejected.mousePair
            if not canClick and not canPair then
                local reason = "Không có input M1 khả dụng. Chọn nút đánh thật của game trong tab Mục tiêu hoặc đổi phương thức M1."
                App.lastInputError = reason
                return false, reason, true
            end
            local pointer = Input:GetMouseLocation()
            if pointer.X < 12 or pointer.X >= viewport.X - 12
                or pointer.Y < inset.Y + 12 or pointer.Y >= viewport.Y + inset.Y - 12 then
                return false, "Đặt con trỏ vào vùng chơi", false
            end
            local ok, objects = pcall(function() return PlayerGui:GetGuiObjectsAtPosition(pointer.X, pointer.Y) end)
            if ok then
                for _, object in ipairs(objects) do
                    if object:IsA("GuiButton") or object:IsA("TextBox") then return false, "Con trỏ trên nút UI", false end
                end
            end
            if canClick then
                local clicked, result = pcall(Caps.click)
                if clicked and result ~= false then App.inputBackend = "mouse1click"; return true
                else App.rejected.click = true; App.inputFailures.click = tostring(result) end
            end
            if canPair then
                local pressed, result = pcall(Caps.down)
                if pressed and result ~= false then release = Caps.up; App.inputBackend = "mouse1press/release"
                else pcall(Caps.up); App.rejected.mousePair = true; App.inputFailures.mousePair = tostring(result) end
            end
        end
    else
        local code = Enum.KeyCode[key]
        if not code then return false, "Phím không hỗ trợ", true end
        if VIM and not App.rejected.keyboard then
            local ok = pcall(function() VIM:SendKeyEvent(true, code, false, game) end)
            if ok then release = function() VIM:SendKeyEvent(false, code, false, game) end
            else App.rejected.keyboard = true end
        end
        if not release and Caps.keydown and Caps.keyup and virtualKeys[key] and not App.rejected.keyPair then
            local vk = virtualKeys[key]
            local ok = pcall(Caps.keydown, vk)
            if ok then release = function() Caps.keyup(vk) end
            else pcall(Caps.keyup, vk); App.rejected.keyPair = true end
        end
    end
    if not release then
        App.lastInputError = "Môi trường chặn hoặc thiếu API mô phỏng input"
        return false, App.lastInputError, true
    end
    App.inputs[key] = {release = release, untilTime = os.clock() + duration, owner = owner}
    return true
end
function App.inputTick(now)
    local expired = {}
    for key, held in pairs(App.inputs) do
        if now >= held.untilTime then table.insert(expired, key) end
    end
    for _, key in ipairs(expired) do App.release(key) end
end

-- 03. Local movement. Interpolation is not an anti-cheat bypass.
function App.rootHeight(character, humanoid, root)
    local offset = root.Size.Y / 2 + humanoid.HipHeight
    if humanoid.RigType == Enum.HumanoidRigType.R6 then
        local leg = character:FindFirstChild("Left Leg") or character:FindFirstChild("Right Leg")
        if leg and leg:IsA("BasePart") then offset = offset + leg.Size.Y end
    end
    return math.max(offset, root.Size.Y / 2) + 0.2
end
function App.ground(position)
    local ignore = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then table.insert(ignore, player.Character) end
    end
    if App.effects then table.insert(ignore, App.effects) end
    local parameters = RaycastParams.new()
    parameters.FilterType = Enum.RaycastFilterType.Exclude
    parameters.FilterDescendantsInstances = ignore
    parameters.RespectCanCollide = true
    parameters.IgnoreWater = true
    local hit = World:Raycast(position + Vector3.new(0, 18, 0), Vector3.new(0, -100, 0), parameters)
    if not hit or hit.Normal.Y < 0.55 then return nil end
    local character, humanoid, root = App.parts(Me)
    if not humanoid then return nil end
    return hit.Position + Vector3.new(0, App.rootHeight(character, humanoid, root), 0)
end
function App.face(position, target)
    local look = Vector3.new(target.X, position.Y, target.Z)
    return (look - position).Magnitude > 0.01 and CFrame.lookAt(position, look) or CFrame.new(position)
end
function App.moveTo(cframe, priority, seconds, instant)
    local _, _, root = App.parts(Me)
    if not root or root.Anchored then return false end
    if App.goal and App.goal.expires > os.clock() and App.goal.priority > priority then return false end
    if instant then
        root.CFrame = cframe
        root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
        App.goal = nil
    else App.goal = {cf = cframe, priority = priority, expires = os.clock() + seconds} end
    return true
end
function App.stopFly()
    if App.flight then
        for _, object in ipairs(App.flight.objects) do pcall(function() object:Destroy() end) end
        pcall(function() App.flight.root.AssemblyLinearVelocity = Vector3.zero end)
        local humanoid = App.flight.humanoid
        App.restore("flight")
        if humanoid.Parent and humanoid.Health > 0 and not humanoid.PlatformStand then
            pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        end
        App.flight = nil
    end
    App.upPointer, App.downPointer = nil, nil
    App.flyTouches = {up = {}, down = {}}
end
function App.startFly()
    local _, humanoid, root = App.parts(Me)
    if not root or root.Anchored then return false, "Nhân vật chưa sẵn sàng" end
    App.goal = nil
    local attachment = Instance.new("Attachment")
    attachment.Name, attachment.Parent = "UwUNCTT_Flight", root
    App.flight = {root = root, humanoid = humanoid, objects = {attachment}}
    local ok, err = pcall(function()
        local velocity = Instance.new("LinearVelocity")
        table.insert(App.flight.objects, velocity)
        velocity.Attachment0 = attachment
        velocity.RelativeTo = Enum.ActuatorRelativeTo.World
        velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        velocity.ForceLimitsEnabled = false
        velocity.VectorVelocity, velocity.Parent = Vector3.zero, root
        local orientation = Instance.new("AlignOrientation")
        table.insert(App.flight.objects, orientation)
        orientation.Attachment0 = attachment
        orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
        orientation.MaxTorque, orientation.Responsiveness = 100000000, 35
        orientation.CFrame, orientation.Parent = root.CFrame.Rotation, root
        App.flight.velocity, App.flight.orientation = velocity, orientation
        App.patch("flight", humanoid, "AutoRotate", false)
        App.patch("flight", humanoid, "PlatformStand", true)
    end)
    if not ok then App.stopFly(); return false, tostring(err) end
    return true
end
function App.flyTick()
    local _, humanoid, root = App.parts(Me)
    if not App.flight or not root or root ~= App.flight.root then
        App.flags.fly = false; App.stopFly(); App.refresh(); return
    end
    local camera = World.CurrentCamera
    if not camera then return end
    local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
    forward = forward.Magnitude > 0.01 and forward.Unit or Vector3.new(0, 0, -1)
    local right = Vector3.new(-forward.Z, 0, forward.X)
    local keyboard = Vector3.zero
    if App.keys[Enum.KeyCode.W] then keyboard = keyboard + forward end
    if App.keys[Enum.KeyCode.S] then keyboard = keyboard - forward end
    if App.keys[Enum.KeyCode.D] then keyboard = keyboard + right end
    if App.keys[Enum.KeyCode.A] then keyboard = keyboard - right end
    local direction = keyboard.Magnitude > 0 and keyboard or humanoid.MoveDirection
    local up = (next(App.flyTouches.up) or App.upPointer or App.keys[Enum.KeyCode.Space]) and 1 or 0
    local down = (next(App.flyTouches.down) or App.downPointer or App.keys[Enum.KeyCode.LeftControl] or App.keys[Enum.KeyCode.RightControl]) and 1 or 0
    direction = Vector3.new(direction.X, up - down, direction.Z)
    if direction.Magnitude > 1 then direction = direction.Unit end
    App.flight.velocity.VectorVelocity = direction * App.values.fly
    App.flight.orientation.CFrame = CFrame.lookAt(Vector3.zero, forward)
end
function App.dash()
    if not App.flags.dash or App.flags.fly then return end
    local _, humanoid, root = App.parts(Me)
    if not root then return end
    local direction = humanoid.MoveDirection
    if direction.Magnitude < 0.1 then direction = root.CFrame.LookVector end
    direction = Vector3.new(direction.X, 0, direction.Z)
    if direction.Magnitude < 0.1 then return end
    local ground = App.ground(root.Position + direction.Unit * App.values.dashLength)
    if ground then App.moveTo(App.face(ground, ground + direction), 70, 0.35, false) end
end
function App.movementTick(dt, now)
    local character, humanoid, root = App.parts(Me)
    if not root then return end
    if App.flags.antiVoid and root.Position.Y < App.values.voidY and App.lastGround then
        App.releaseAll(); App.pauseUntil = now + 1
        App.moveTo(App.lastGround, 1000, 0, true)
        return
    end
    if now - App.groundAt > 0.35 then
        App.groundAt = now
        local ground = App.ground(root.Position)
        if ground and math.abs(ground.Y - root.Position.Y) < 4 and root.Position.Y >= App.values.voidY + 5 then
            App.lastGround = App.face(ground, ground + root.CFrame.LookVector)
        end
    end
    if App.flags.speed then App.patch("speed", humanoid, "WalkSpeed", App.values.speed) end
    if now - App.localAt > 0.25 then
        App.localAt = now
        if App.flags.hidden then
            App.hiddenParts = {}
            for _, object in ipairs(character:GetDescendants()) do
                if object:IsA("BasePart") then
                    table.insert(App.hiddenParts, object)
                    App.patch("hidden", object, "LocalTransparencyModifier", 1)
                end
            end
        end
        if App.flags.anonymous then App.patch("anonymous", humanoid, "DisplayDistanceType", Enum.HumanoidDisplayDistanceType.None) end
    end
    if App.flags.fly then App.flyTick(); return end
    if App.flags.stabilize then
        App.patch("stabilize", humanoid, "PlatformStand", false)
        App.patch("stabilize", humanoid, "AutoRotate", true)
        local status = humanoid:GetState()
        if status == Enum.HumanoidStateType.Ragdoll or status == Enum.HumanoidStateType.FallingDown then
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        local velocity = root.AssemblyLinearVelocity
        if Vector3.new(velocity.X, 0, velocity.Z).Magnitude > math.max(humanoid.WalkSpeed + 70, 100) and not App.goal then
            local move = humanoid.MoveDirection * humanoid.WalkSpeed
            root.AssemblyLinearVelocity = Vector3.new(move.X, math.clamp(velocity.Y, -60, 50), move.Z)
        end
        root.AssemblyAngularVelocity = Vector3.zero
    end
    local goal = App.goal
    if goal then
        if goal.expires < now then App.goal = nil; return end
        if not root.Anchored then
            local distance = (goal.cf.Position - root.Position).Magnitude
            local alpha = distance > 0.01 and math.min(1, App.values.travel * math.min(dt, 0.1) / distance) or 1
            if goal.priority == 10 then
                local position = root.Position
                if distance > 0.65 then
                    position = root.Position + (goal.cf.Position - root.Position) * alpha
                end
                local rotation = root.CFrame.Rotation:Lerp(goal.cf.Rotation, 1 - math.exp(-12 * math.min(dt, 0.1)))
                root.CFrame = CFrame.new(position) * rotation
            else
                root.CFrame = root.CFrame:Lerp(goal.cf, alpha)
                root.AssemblyLinearVelocity = Vector3.zero
            end
            if distance < 0.3 and goal.priority > 10 then App.goal = nil end
        end
    end
end

-- 04. Animation playback. Asset permissions remain enforced by Roblox.
function App.stopEmote()
    if App.emote then
        pcall(function() App.emote.track:Stop(0.1); App.emote.track:Destroy() end)
        pcall(function() App.emote.asset:Destroy() end)
        App.emote = nil
    end
end
function App.playEmote(id)
    local _, humanoid = App.parts(Me)
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator then App.notify("Emote", "Animator chưa sẵn sàng."); return end
    id = tostring(id):match("^%s*(%d+)%s*$") or tostring(id):match("^%s*rbxassetid://(%d+)%s*$")
    if not id then App.notify("Emote", "Nhập AnimationId hợp lệ."); return end
    App.stopEmote()
    local asset = Instance.new("Animation")
    asset.AnimationId = "rbxassetid://" .. id
    local track
    local ok, err = pcall(function()
        track = animator:LoadAnimation(asset)
        track.Priority, track.Looped = Enum.AnimationPriority.Action, App.flags.loopEmote
        track:Play(0.15)
    end)
    if not ok then
        asset:Destroy()
        if track then pcall(function() track:Destroy() end) end
        App.notify("Emote không phát được", tostring(err):sub(1, 160))
        return
    end
    App.emote = {asset = asset, track = track}
    App.notify("Emote", "Đã gửi yêu cầu phát ID " .. id .. "; quyền asset và rig vẫn áp dụng.")
end

-- 05. Observed game data, configurable combat, animation reactions.
function App.animationId(track)
    local animation = track.Animation
    return animation and tostring(animation.AnimationId):match("%d+") or nil
end
function App.awake(player)
    local binding = App.binding
    if not binding then return nil end
    local object = binding.source == "Player" and player or player.Character
    if not object then return nil end
    local value = object:GetAttribute(binding.key)
    if value == nil then
        if App.flags.missingInactive then return false end
        return nil
    end
    return typeof(value) == typeof(binding.value) and value == binding.value
end
function App.farmReport(phase, reason, target, distance)
    App.farmPhase, App.farmReason = phase, reason or ""
    App.farmDisplayTarget = target
    App.farmDistance = distance
    if App.refreshFarmUI then App.refreshFarmUI() end
end
function App.startFarm()
    App.releaseAll(); App.goal = nil; App.stopEmote()
    if App.flags.fly then App.flags.fly = false; App.stopFly() end
    if App.targetMode == "Chọn thủ công" and not App.parts(App.selectedPlayer()) then App.targetMode = "Gần nhất" end
    App.current = App.targetMode == "Chọn thủ công" and App.selected or nil
    App.flags.farm, App.flags.farmPaused = true, false
    App.flags.lock, App.flags.m1, App.flags.skills = true, true, App.flags.farmSkills
    App.lastAttack, App.lastSkill, App.lastFollowAt, App.lastAction = -math.huge, -math.huge, -math.huge, -math.huge
    App.farmSent, App.farmTargetId, App.farmHealth = 0, nil, nil
    App.farmReport("ĐANG TÌM", "Tự chọn mục tiêu và tiếp cận.")
    App.showMenu(false); App.refresh()
    App.notify("Auto Farm đã bật", "MENU để chỉnh · DỪNG để ngừng. Nút cảm ứng của game được giữ nguyên.")
end
function App.stopFarm(reason, failed)
    App.flags.farm, App.flags.farmPaused = false, false
    App.flags.lock, App.flags.m1, App.flags.skills = false, false, false
    App.releaseAll("combat")
    if App.goal and App.goal.priority == 10 then App.goal = nil end
    App.current = nil
    App.farmReport(failed and "INPUT KHÔNG KHẢ DỤNG" or "ĐÃ DỪNG", reason or "Bấm BẮT ĐẦU AUTO FARM.")
    App.refresh()
    if failed then App.showMenu(true); App.notify("Farm đã dừng", reason) end
end
function App.diagnostics()
    local lines = {
        "UwUNCTT 2.2 | " .. executor .. (App.isMobile() and " | MOBILE: không gửi phím/chuột PC" or " | PC"),
        "Farm: " .. App.farmPhase .. " | " .. App.farmReason,
        "M1: " .. App.m1Mode .. " | backend: " .. App.inputBackend,
        "Đã gửi M1: " .. tostring(App.farmSent),
        "VIM bị chặn: " .. tostring(App.rejected.mouse == true),
        "firesignal: " .. tostring(Caps.signal ~= nil) .. " | getconnections: " .. tostring(Caps.connections ~= nil),
        "mouse1click: " .. tostring(Caps.click ~= nil),
        "Nút M1: " .. ((App.boundPunch or App.autoPunch) and (App.boundPunch or App.autoPunch).Name or "Chưa gán / chưa tìm thấy"),
        "Lỗi input: " .. App.lastInputError,
    }
    for _, key in ipairs({"M1", "One", "Two", "Three", "Four", "F"}) do
        local button = App.actionButton(key)
        table.insert(lines, key .. ": " .. (button and button.Name or "Chưa gán") .. " / " .. (App.buttonModes[key] or "Tự động"))
    end
    for key, value in pairs(App.inputFailures) do table.insert(lines, key .. ": " .. tostring(value):sub(1, 180)) end
    return table.concat(lines, "\n")
end
function App.nearest(exclude, requireInactive)
    local _, _, myRoot = App.parts(Me)
    if not myRoot then return nil end
    local best, distance = nil, App.values.targetRange
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Me and player.UserId ~= exclude then
            local _, _, root = App.parts(player)
            local eligible = not requireInactive or App.awake(player) == false
            if root and eligible and root.Position.Y > App.values.voidY + 5 then
                local d = (root.Position - myRoot.Position).Magnitude
                if d < distance then best, distance = player, d end
            end
        end
    end
    return best
end
function App.chooseTarget()
    local target
    if App.targetMode == "Gần nhất" then
        local current = App.current and Players:GetPlayerByUserId(App.current)
        local _, _, currentRoot = App.parts(current)
        local _, _, myRoot = App.parts(Me)
        local inRange = currentRoot and myRoot and (currentRoot.Position - myRoot.Position).Magnitude <= App.values.targetRange
        if inRange and currentRoot.Position.Y > App.values.voidY + 5 then target = current
        else target = App.nearest(nil, App.flags.switchAwake) end
    else
        target = App.current and Players:GetPlayerByUserId(App.current) or App.selectedPlayer()
        if not App.parts(target) and App.current ~= App.selected then target = App.selectedPlayer() end
    end
    if not target or not App.parts(target) then App.current = nil; return nil end
    if App.flags.switchAwake then
        local awakened = App.awake(target)
        if awakened ~= false then
            App.releaseAll("combat"); App.goal = nil
            local nextTarget = App.nearest(target.UserId, true)
            if awakened and App.awakeNotice ~= target.UserId then
                App.awakeNotice = target.UserId
                App.notify("Target Awakened -> Switching!", nextTarget and App.name(nextTarget) or "Chưa có mục tiêu có trạng thái phù hợp.")
            end
            target = nextTarget
        end
    end
    App.current = target and target.UserId or nil
    return target
end
function App.followTarget(target, now)
    if now - App.lastFollowAt < 0.045 and target.UserId == App.followTargetId then return App.followOkay end
    App.lastFollowAt = now
    App.followTargetId = target.UserId
    local _, humanoid, myRoot = App.parts(Me)
    local _, _, root = App.parts(target)
    if not root or not myRoot or myRoot.Anchored or humanoid.PlatformStand then
        App.followOkay = false
        if App.goal and App.goal.priority == 10 then App.goal = nil end
        return false
    end
    local ground = App.ground((root.CFrame * CFrame.new(0, 0, App.values.distance)).Position)
    if not ground then
        App.followOkay = false
        if App.goal and App.goal.priority == 10 then App.goal = nil end
        return false
    end
    local destination = App.face(ground, root.Position)
    local delta = (destination.Position - myRoot.Position).Magnitude
    local mayJump = now - (App.lastWarpAt or -math.huge) >= App.values.teleInterval
    if App.teleMode == "Nhanh" and delta > 12 and mayJump then
        if App.moveTo(destination, 10, 0, true) then App.lastWarpAt = now end
    else App.moveTo(destination, 10, 0.45, false) end
    App.followOkay = true
    return true
end
function App.followTick(now)
    if not (App.flags.lock or App.flags.farm) or App.flags.fly or App.panel.Visible
        or App.flags.farmPaused or App.captureAction or now < App.pauseUntil or App.focused == false then return end
    local target = App.chooseTarget()
    if not target then
        if App.goal and App.goal.priority == 10 then App.goal = nil end
        return
    end
    App.followTarget(target, now)
end
function App.react(player, track, id, now)
    local rule = App.animations[id]
    if not rule or not track.IsPlaying or not App.panel or App.panel.Visible then return end
    if App.focused == false or Input:GetFocusedTextBox() or GuiService.MenuIsOpen then return end
    local _, _, root = App.parts(player)
    local _, _, myRoot = App.parts(Me)
    if not root or not myRoot or (root.Position - myRoot.Position).Magnitude > App.values.radius then return end
    local dodge = (rule.kind == "Counter" and App.flags.dodge) or (rule.kind == "Ultimate" and App.flags.ultDodge)
    if dodge then
        App.pauseUntil = math.max(App.pauseUntil, now + 0.65)
        App.releaseAll()
        if now - App.reactionAt < (App.flags.safe and 1.1 or 0.65) then return end
        App.reactionAt = now
        if App.flags.fly then App.flags.fly = false; App.stopFly(); App.refresh() end
        local position
        if rule.kind == "Ultimate" and App.ultMode == "Sau lưng" then
            position = (root.CFrame * CFrame.new(0, 0, 12)).Position
        else
            local away = myRoot.Position - root.Position
            away = Vector3.new(away.X, 0, away.Z)
            if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
            position = myRoot.Position + away.Unit * App.values.retreat
        end
        local ground = App.ground(position)
        if ground then App.moveTo(App.face(ground, root.Position), 200, 0.85, false) end
        App.notify(rule.kind .. " được nhận diện", ground and "Tạm dừng auto đánh, thử rút khỏi chiêu." or "Đã dừng auto đánh; không thấy chỗ đứng để rút.")
    elseif rule.kind == "Block" and App.flags.block and now >= App.pauseUntil then
        App.releaseAll("combat")
        local ok, reason, fatal = App.press("F", 0.35, "block")
        if not ok and fatal then App.flags.block = false; App.refresh(); App.notify("Auto Block đã tắt", reason) end
    end
end
function App.observe(player, track)
    if not App.alive or player == Me then return end
    local id = App.animationId(track)
    if not id then return end
    if not App.seenTrack[track] then
        App.seenTrack[track] = true
        if not App.recent[id] then
            table.insert(App.recentOrder, 1, id)
            if #App.recentOrder > 24 then App.recent[table.remove(App.recentOrder)] = nil end
        end
        App.recent[id] = {observer = player.UserId, name = track.Animation and track.Animation.Name or "Animation"}
    end
    local current = App.activeSkills[player.UserId]
    if App.animations[id] or not current or not current.track.IsPlaying or not App.animations[current.id] then
        App.activeSkills[player.UserId] = {id = id, track = track}
    end
    App.react(player, track, id, os.clock())
end
function App.watch(player)
    local watcher = {connections = {}, character = {}, animators = setmetatable({}, {__mode = "k"})}
    App.watchers[player.UserId] = watcher
    local function characterReady(character)
        disconnect(watcher.character)
        watcher.character = {}
        watcher.animators = setmetatable({}, {__mode = "k"})
        local function attach(object)
            if object:IsA("Animator") and not watcher.animators[object] then
                watcher.animators[object] = true
                App.bind(object.AnimationPlayed, function(track)
                    App.try("Quan sát hoạt ảnh", App.observe, player, track)
                end, watcher.character)
            end
        end
        for _, object in ipairs(character:GetDescendants()) do attach(object) end
        App.bind(character.DescendantAdded, attach, watcher.character)
    end
    App.bind(player.CharacterAdded, characterReady, watcher.connections)
    App.bind(player.CharacterRemoving, function()
        disconnect(watcher.character); watcher.character = {}
        App.activeSkills[player.UserId] = nil
    end, watcher.connections)
    if player.Character then characterReady(player.Character) end
end
function App.unwatch(player)
    local watcher = App.watchers[player.UserId]
    if watcher then disconnect(watcher.connections); disconnect(watcher.character) end
    App.watchers[player.UserId], App.activeSkills[player.UserId] = nil, nil
    App.removeESP(player.UserId)
    if App.current == player.UserId then App.current = nil; App.goal = nil; App.releaseAll("combat") end
    if App.selected == player.UserId then App.selected = nil end
end
function App.reactionTick(now)
    if not (App.flags.block or App.flags.dodge or App.flags.ultDodge) then return end
    local _, _, myRoot = App.parts(Me)
    if not myRoot then return end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Me then
            local _, humanoid, root = App.parts(player)
            if root and (root.Position - myRoot.Position).Magnitude <= App.values.radius then
                local animator = humanoid:FindFirstChildOfClass("Animator")
                if animator then
                    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do App.observe(player, track) end
                end
            end
        end
    end
end
function App.combatTick(now)
    if not (App.flags.farm or App.flags.lock or App.flags.m1 or App.flags.skills) then return end
    if App.panel.Visible or App.flags.farmPaused or App.captureAction then
        App.releaseAll("combat")
        if App.goal and App.goal.priority == 10 then App.goal = nil end
        if App.flags.farm then App.farmReport("TẠM DỪNG", App.panel.Visible and "Thu gọn menu để tiếp tục." or "Bấm TIẾP TỤC FARM.") end
        return
    end
    if now < App.pauseUntil or App.inputs.F then
        if App.flags.farm then App.farmReport("ĐANG NÉ / BLOCK", "Tạm ngừng gửi đòn đánh.") end
        return
    end
    local _, humanoid, myRoot = App.parts(Me)
    if not myRoot then
        App.releaseAll("combat"); App.current = nil
        if App.goal and App.goal.priority == 10 then App.goal = nil end
        if App.flags.farm then App.farmReport("CHỜ HỒI SINH", "Nhân vật chưa sẵn sàng; sẽ tìm mục tiêu sau khi hồi sinh.") end
        return
    end
    if myRoot.Anchored or humanoid.PlatformStand then
        App.releaseAll("combat")
        if App.goal and App.goal.priority == 10 then App.goal = nil end
        if App.flags.farm then App.farmReport("CHỜ NHÂN VẬT", "Nhân vật đang bị neo hoặc khống chế.") end
        return
    end
    local target = App.chooseTarget()
    local _, targetHumanoid, root = App.parts(target)
    if not root then
        App.releaseAll("combat")
        if App.goal and App.goal.priority == 10 then App.goal = nil end
        if App.flags.farm then App.farmReport("CHỜ MỤC TIÊU", "Chưa có mục tiêu còn sống trong phạm vi / cờ nộ phù hợp.") end
        return
    end
    local distance = (root.Position - myRoot.Position).Magnitude
    if App.flags.lock and not App.flags.fly then
        if not App.followTarget(target, now) then
            if App.flags.farm then App.farmReport("CHỜ MẶT ĐẤT", "Không tìm được vị trí đứng sau mục tiêu.", target) end
            if distance > App.values.attackRange then return end
        end
    end
    distance = (root.Position - myRoot.Position).Magnitude
    if distance > App.values.attackRange then
        if App.flags.farm then App.farmReport("ĐANG TIẾP CẬN", "Chờ vào tầm đánh.", target, distance) end
        return
    end
    if App.farmTargetId ~= target.UserId then
        App.farmTargetId, App.farmHealth, App.farmDamageAt = target.UserId, targetHumanoid.Health, now
    elseif targetHumanoid.Health < (App.farmHealth or targetHumanoid.Health) then App.farmDamageAt = now end
    App.farmHealth = targetHumanoid.Health
    if App.flags.farm then
        local reason = now - App.farmDamageAt > 7 and "Đã gửi M1 nhưng chưa thấy HP giảm; kiểm tra phương thức / trạng thái game." or "Đang gửi M1 trong tầm. Server quyết định damage và kill."
        App.farmReport("TRONG TẦM ĐÁNH", reason, target, distance)
    end
    if now < App.manualUntil or now - App.lastAction < 0.09 then return end
    for _, held in pairs(App.inputs) do if held.owner == "combat" then return end end
    -- Dispatch a single action per tick: do not stomp a skill with M1 in the same frame.
    if App.flags.skills and now - App.lastSkill >= math.max(App.values.skillGap, App.flags.safe and 0.8 or 0.25) then
        App.lastSkill = now
        local keys = {"One", "Two", "Three", "Four"}
        local ok, reason, fatal = App.press(keys[App.skillIndex], 0.065, "combat")
        App.skillIndex = App.skillIndex % 4 + 1
        if ok then App.lastAction = now; return end
        if fatal then App.flags.skills = false; App.refresh(); App.notify("Auto Skill đã tắt", reason) end
    end
    if App.flags.m1 and now - App.lastAttack >= math.max(App.values.m1Gap, App.flags.safe and 0.45 or 0.18) then
        App.lastAttack = now
        local ok, reason, fatal = App.press("M1", 0.065, "combat")
        if ok then App.lastAction = now; App.farmSent = App.farmSent + 1; if App.refreshFarmUI then App.refreshFarmUI() end
        elseif fatal then
            if App.flags.farm then App.stopFarm(reason, true); return
            else App.flags.m1 = false; App.refresh(); App.notify("Auto M1 đã tắt", reason) end
        elseif App.flags.farm then App.farmReport("CHỜ INPUT", reason, target, distance) end
    end
end

-- 06. Local graphics. Bounded work queue; reversible property changes.
function App.refreshLighting()
    App.restore("lighting")
    if App.flags.potato or App.flags.bright then App.patch("lighting", Lighting, "GlobalShadows", false) end
    if App.flags.bright then
        App.patch("lighting", Lighting, "Brightness", 3)
        App.patch("lighting", Lighting, "ClockTime", 14)
        App.patch("lighting", Lighting, "Ambient", Color3.fromRGB(190, 190, 190))
        App.patch("lighting", Lighting, "OutdoorAmbient", Color3.fromRGB(210, 210, 210))
        App.patch("lighting", Lighting, "FogEnd", 100000)
    end
end
function App.fragment(object)
    if not object:IsA("BasePart") or object.Anchored then return false end
    local ancestor = object
    local matched = false
    for _ = 1, 5 do
        if not ancestor or ancestor == World then break end
        if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then return false end
        local name = string.lower(ancestor.Name)
        if name == "debris" or name == "rubble" or name == "fragments" then matched = true end
        ancestor = ancestor.Parent
    end
    return matched
end
function App.optimize(object)
    if not object.Parent or (App.effects and object:IsDescendantOf(App.effects)) then return end
    if App.flags.potato then
        if object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
            or object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Sparkles") or object:IsA("PostEffect") then
            App.patch("opt", object, "Enabled", false)
        elseif object:IsA("BasePart") then
            App.patch("opt", object, "CastShadow", false)
            App.patch("opt", object, "Reflectance", 0)
            App.patch("opt", object, "Material", Enum.Material.SmoothPlastic)
        end
    end
    if App.flags.fragments and App.fragment(object) then App.patch("opt", object, "LocalTransparencyModifier", 1) end
end
function App.queueScan()
    App.restore("opt")
    App.queue, App.queueIndex = {}, 1
    if App.flags.potato or App.flags.fragments then
        for _, object in ipairs(World:GetDescendants()) do table.insert(App.queue, object) end
        for _, object in ipairs(Lighting:GetDescendants()) do table.insert(App.queue, object) end
    end
    App.refreshLighting()
end
function App.workQueue()
    local start, count = os.clock(), 0
    while App.queueIndex <= #App.queue and count < 100 and os.clock() - start < 0.002 do
        local object = App.queue[App.queueIndex]
        App.queueIndex, count = App.queueIndex + 1, count + 1
        App.optimize(object)
    end
    if App.queueIndex > #App.queue then App.queue, App.queueIndex = {}, 1 end
end

-- Native GUI ESP: no Drawing API required.
function App.removeESP(id)
    local bundle = App.esp[id]
    if not bundle then return end
    for _, object in ipairs({bundle.box, bundle.trace, bundle.highlight}) do pcall(function() object:Destroy() end) end
    App.esp[id] = nil
end
function App.clearESP()
    local ids = {}
    for id in pairs(App.esp) do table.insert(ids, id) end
    for _, id in ipairs(ids) do App.removeESP(id) end
end
function App.espBundle(player)
    local bundle = App.esp[player.UserId]
    if bundle then return bundle end
    local box = App.new("Frame", {BackgroundTransparency = 1, Visible = false, BorderSizePixel = 0}, App.overlay)
    local stroke = App.new("UIStroke", {Thickness = 1.5, Color = Color3.fromRGB(197, 89, 255)}, box)
    local label = App.new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(-0.5, 0, 0, -37), Size = UDim2.new(2, 0, 0, 34),
        TextColor3 = Color3.fromRGB(245, 235, 255), TextStrokeTransparency = 0.35,
        Font = Enum.Font.GothamMedium, TextSize = 11, TextWrapped = true, Text = "",
    }, box)
    local trace = App.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(197, 89, 255), Visible = false}, App.overlay)
    local highlight = App.new("Highlight", {
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, FillTransparency = 0.78,
        OutlineTransparency = 0.15, Enabled = false, FillColor = Color3.fromRGB(160, 50, 220),
        OutlineColor = Color3.fromRGB(232, 120, 255),
    }, App.effects)
    bundle = {box = box, stroke = stroke, label = label, trace = trace, highlight = highlight}
    App.esp[player.UserId] = bundle
    return bundle
end
function App.espTick()
    if not App.flags.esp then return end
    local camera = World.CurrentCamera
    local _, _, myRoot = App.parts(Me)
    if not camera or not myRoot then
        for _, bundle in pairs(App.esp) do bundle.box.Visible = false; bundle.trace.Visible = false; bundle.highlight.Enabled = false end
        return
    end
    local viewport = camera.ViewportSize
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Me then
            local bundle = App.espBundle(player)
            local character, _, root = App.parts(player)
            bundle.box.Visible, bundle.trace.Visible, bundle.highlight.Enabled = false, false, false
            if root then
                local distance = (root.Position - myRoot.Position).Magnitude
                if distance <= App.values.espDistance then
                    bundle.highlight.Adornee = character
                    bundle.highlight.Enabled = App.flags.chams
                    local top, onScreen = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 3.5, 0))
                    local bottom = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.5, 0))
                    if onScreen and top.Z > 0 and bottom.Z > 0 then
                        local height = math.clamp(math.abs(bottom.Y - top.Y), 8, viewport.Y * 1.8)
                        local width = height * 0.58
                        bundle.box.Position = UDim2.fromOffset(top.X - width / 2, math.min(top.Y, bottom.Y))
                        bundle.box.Size = UDim2.fromOffset(width, height)
                        bundle.box.Visible = true
                        bundle.stroke.Enabled = App.flags.boxes
                        local skill, suffix = App.activeSkills[player.UserId], ""
                        if skill and skill.track.IsPlaying then
                            local rule = App.animations[skill.id]
                            suffix = "\n" .. (rule and rule.label or ("Anim " .. skill.id))
                        end
                        bundle.label.Text = App.name(player) .. "  " .. math.floor(distance) .. " studs" .. suffix
                        if App.flags.tracers then
                            local start = Vector2.new(viewport.X / 2, viewport.Y - 10)
                            local finish = Vector2.new(bottom.X, bottom.Y)
                            local delta, midpoint = finish - start, (start + finish) / 2
                            bundle.trace.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
                            bundle.trace.Size = UDim2.fromOffset(delta.Magnitude, 1)
                            bundle.trace.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                            bundle.trace.Visible = true
                        end
                    end
                end
            end
        end
    end
end

-- 07. Feature lifecycle, manual actions, complete custom UI library.
function App.stopCombat()
    App.flags.farm, App.flags.farmPaused = false, false
    App.flags.m1, App.flags.skills, App.flags.block, App.flags.lock = false, false, false, false
    App.releaseAll(); App.goal = nil
    App.farmReport("ĐÃ DỪNG", "Thao tác điều khiển khác đã dừng Farm.")
    App.refresh()
end
function App.setFlag(key, enabled)
    if not App.alive then return end
    if not enabled and App.flags.farm and (key == "m1" or key == "lock") then App.stopFarm(); return end
    if key == "switchAwake" and enabled and not App.binding then
        App.notify("Chưa có cờ nộ", "Quét thuộc tính của mục tiêu rồi chọn đúng trạng thái đang nộ."); return
    end
    local needed = ({block = "Block", dodge = "Counter", ultDodge = "Ultimate"})[key]
    if needed and enabled then
        local found = false
        for _, rule in pairs(App.animations) do if rule.kind == needed then found = true end end
        if not found then App.notify("Chưa có ID " .. needed, "Gán hoạt ảnh thực trong tab Counter trước."); return end
    end
    if key == "fly" then
        if enabled then
            App.stopCombat(); App.flags.stabilize = false; App.restore("stabilize")
            local ok, err = App.startFly()
            if not ok then App.notify("Không bật được Fly", err); App.refresh(); return end
        else App.stopFly() end
    elseif key == "stabilize" then
        if enabled and App.flags.fly then App.flags.fly = false; App.stopFly() end
        if not enabled then App.restore("stabilize") end
    elseif key == "speed" and not enabled then App.restore("speed")
    elseif key == "hidden" and not enabled then App.restore("hidden")
    elseif key == "anonymous" and not enabled then App.restore("anonymous")
    elseif key == "lock" and not enabled then
        if App.goal and App.goal.priority == 10 then App.goal = nil end
    elseif key == "m1" and not enabled then App.release("M1")
    elseif key == "skills" and not enabled then App.releaseAll("combat")
    elseif key == "block" and not enabled then App.releaseAll("block")
    elseif key == "fpsCap" then
        if enabled then
            if not Caps.fpsset or not Caps.fpsget then
                App.notify("FPS cap chưa khả dụng", "Cần cả getfpscap và setfpscap để khôi phục cap gốc."); return
            end
            local ok, original = pcall(Caps.fpsget)
            if not ok or type(original) ~= "number" or original ~= original or original < 0 or original == math.huge then
                App.notify("FPS cap chưa khả dụng", "Không đọc được cap gốc hợp lệ."); return
            end
            local applied, err = pcall(Caps.fpsset, App.values.fpsCap)
            if not applied then App.notify("Không đặt được FPS cap", err); return end
            App.originalCap = original
        elseif App.originalCap ~= nil and Caps.fpsset then
            pcall(Caps.fpsset, App.originalCap); App.originalCap = nil
        end
    end
    App.flags[key] = enabled
    if key == "farmSkills" and App.flags.farm then App.flags.skills = enabled end
    if key == "skills" and App.flags.farm then App.flags.farmSkills = enabled end
    if key == "potato" or key == "fragments" then App.queueScan()
    elseif key == "bright" then App.refreshLighting()
    elseif key == "esp" and not enabled then App.clearESP()
    elseif key == "anonymous" and App.updateRoster then App.updateRoster() end
    if enabled and (key == "m1" or key == "skills" or key == "block") then
        App.stopEmote(); App.showMenu(false)
    end
    App.refresh()
    App.notify(enabled and "Đã bật" or "Đã tắt", key == "safe" and "Chỉ giảm tần suất; không có bảo đảm chống ban." or key)
end
function App.stopAll(message)
    for key, value in pairs(App.flags) do
        if type(value) == "boolean" and key ~= "safe" and key ~= "loopEmote" then App.flags[key] = false end
    end
    App.releaseAll(); App.stopFly(); App.stopEmote(); App.goal = nil; App.pauseUntil = 0
    App.queue, App.queueIndex, App.keys = {}, 1, {}
    local groups = {}
    for name in pairs(App.bags) do table.insert(groups, name) end
    for _, name in ipairs(groups) do App.restore(name) end
    if App.originalCap ~= nil and Caps.fpsset then pcall(Caps.fpsset, App.originalCap); App.originalCap = nil end
    App.clearESP(); App.refresh()
    App.farmReport("ĐÃ DỪNG", "Đã tắt điều khiển và nhả input.")
    if message then App.notify("DỪNG", message) end
end
function App.warpTarget()
    local target = App.selectedPlayer()
    local _, _, root = App.parts(target)
    if not root then App.notify("Tele", "Chọn mục tiêu còn sống và đã tải."); return end
    local ground = App.ground((root.CFrame * CFrame.new(0, 0, 6)).Position)
    if not ground then App.notify("Tele", "Không thấy mặt đất cạnh mục tiêu."); return end
    App.stopCombat()
    if App.flags.fly then App.flags.fly = false; App.stopFly(); App.refresh() end
    App.moveTo(App.face(ground, root.Position), 100, 4, false)
end
function App.warpTrash()
    local _, _, myRoot = App.parts(Me)
    if not myRoot then return end
    local candidates = {}
    for _, object in ipairs(World:GetDescendants()) do
        local name = string.lower(object.Name)
        if (string.find(name, "trash", 1, true) or string.find(name, "garbage", 1, true))
            and (object:IsA("BasePart") or (object:IsA("Model") and object:FindFirstChildWhichIsA("BasePart", true))) then
            local ok, cf, size = pcall(function()
                if object:IsA("Model") then return object:GetBoundingBox() end
                return object.CFrame, object.Size
            end)
            if ok and size.Magnitude < 60 then
                table.insert(candidates, {cf = cf, size = size, d = (cf.Position - myRoot.Position).Magnitude})
            end
        end
    end
    table.sort(candidates, function(a, b) return a.d < b.d end)
    for _, item in ipairs(candidates) do
        local ground = App.ground(item.cf.Position + Vector3.new(math.max(item.size.X, item.size.Z) / 2 + 4, 0, 0))
        if ground then
            App.stopCombat()
            if App.flags.fly then App.flags.fly = false; App.stopFly(); App.refresh() end
            App.moveTo(App.face(ground, item.cf.Position), 100, 5, false)
            App.notify("Tele thùng rác", "Đã đặt điểm đến cạnh vật thể gần nhất tìm được."); return
        end
    end
    App.notify("Tele thùng rác", "Không thấy vật thể tên trash/garbage có chỗ đứng trong map đã tải.")
end

local C = {
    bg = Color3.fromRGB(14, 11, 23), card = Color3.fromRGB(29, 22, 43),
    row = Color3.fromRGB(42, 30, 57), red = Color3.fromRGB(255, 64, 109),
    purple = Color3.fromRGB(174, 78, 255), text = Color3.fromRGB(245, 236, 253),
    muted = Color3.fromRGB(176, 161, 193), dark = Color3.fromRGB(24, 9, 31),
}
App.themeItems = setmetatable({}, {__mode = "k"})
function App.new(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties or {}) do object[key] = value end
    object.Parent = parent
    if App.panel and parent and (parent == App.panel or parent:IsDescendantOf(App.panel))
        and properties and properties.BackgroundColor3 and properties.BackgroundTransparency == nil then
        App.themeItems[object] = true
        object.BackgroundTransparency = 0.2 + App.values.guiFade / 200
    end
    return object
end
function App.round(object, radius)
    App.new("UICorner", {CornerRadius = UDim.new(0, radius or 9)}, object)
end
local host = PlayerGui
if Caps.gethui then
    local ok, value = pcall(Caps.gethui)
    if ok and typeof(value) == "Instance" then host = value end
end
App.gui = App.new("ScreenGui", {
    Name = "UwUNCTT", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 120, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, nil)
if not pcall(function() App.gui.Parent = host end) then App.gui.Parent = PlayerGui end
App.overlay = App.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1}, App.gui)
App.effects = App.new("Folder", {Name = "UwUNCTT_LocalVisuals"}, World)
App.panel = App.new("Frame", {
    Size = UDim2.fromOffset(400, 360), AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.bg,
    BackgroundTransparency = 0.55, BorderSizePixel = 0, Active = true,
    ClipsDescendants = true, ZIndex = 10,
}, App.gui)
App.round(App.panel, 14)
App.wallpaper = App.new("ImageLabel", {
    Name = "UserWallpaper", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    Image = "", ImageTransparency = 0.55, ScaleType = Enum.ScaleType.Crop, Active = false,
}, App.panel)
App.round(App.wallpaper, 14)
App.new("Frame", {Name = "ReadabilityTint", Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = C.bg, BackgroundTransparency = 0.7, BorderSizePixel = 0, Active = false}, App.panel)
function App.applyTheme()
    local fade = App.values.guiFade / 100
    App.panel.BackgroundTransparency, App.wallpaper.ImageTransparency = fade, fade
    for object in pairs(App.themeItems) do
        if object.Parent then pcall(function() object.BackgroundTransparency = 0.2 + fade * 0.5 end) end
    end
end
function App.loadWallpaper()
    if not Caps.asset or not Caps.write then App.wallpaperStatus = "Executor thiếu getcustomasset/writefile"; return end
    local filename = "UwUNCTT_background_91442_v1.jpg"
    local ok, result = pcall(function()
        local cached = false
        if Caps.exists then local valid, exists = pcall(Caps.exists, filename); cached = valid and exists == true end
        if not cached then
            local data = game:HttpGet("https://raw.githubusercontent.com/Tuanthinh076/nctt-tsb/refs/heads/main/UwUNCTT-background.jpg?v=2.2")
            assert(type(data) == "string" and #data > 100 and data:sub(1, 2) == string.char(255, 216), "Ảnh tải về không phải JPEG")
            Caps.write(filename, data)
        end
        return Caps.asset(filename)
    end)
    if ok and type(result) == "string" and App.alive then
        App.wallpaper.Image, App.wallpaperStatus = result, "Đã đặt ảnh bạn gửi"
    else App.wallpaperStatus = "Chưa tải được ảnh: " .. tostring(result):sub(1, 100) end
end
local border = App.new("UIStroke", {Thickness = 1.4, Color = C.purple, Transparency = 0.2}, App.panel)
App.new("UIGradient", {Color = ColorSequence.new(C.red, C.purple), Rotation = 35}, border)
local header = App.new("Frame", {Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, Active = true, ZIndex = 2}, App.panel)
App.new("TextLabel", {
    Position = UDim2.fromOffset(12, 7), Size = UDim2.new(1, -158, 0, 25),
    BackgroundTransparency = 1, Text = "UwUNCTT", TextColor3 = C.red,
    Font = Enum.Font.GothamBold, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left,
}, header)
App.new("TextLabel", {
    Position = UDim2.fromOffset(13, 33), Size = UDim2.new(1, -26, 0, 16),
    BackgroundTransparency = 1, Text = "nctt · v2.2 · " .. (App.isMobile() and "Mobile" or "PC") .. " · " .. executor,
    Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
}, header)
local function headerButton(text, x, width, color)
    local button = App.new("TextButton", {
        Position = UDim2.new(1, x, 0, 7), Size = UDim2.fromOffset(width, 44),
        BackgroundColor3 = color or C.row, BorderSizePixel = 0,
        Text = text, TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 14,
    }, header)
    App.round(button, 7); return button
end
local emergency = headerButton("DỪNG", -152, 56, C.red)
App.emergencyButton = emergency
local minimize, close = headerButton("—", -90, 38), headerButton("X", -46, 38)
local tabBar = App.new("Frame", {
    Position = UDim2.fromOffset(8, 61), Size = UDim2.new(1, -16, 0, 94),
    BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2,
}, App.panel)
App.tabBar = tabBar
App.navGrid = App.new("UIGridLayout", {
    CellSize = UDim2.new(0.25, -5, 0, 46), CellPadding = UDim2.fromOffset(6, 6),
    FillDirection = Enum.FillDirection.Horizontal, FillDirectionMaxCells = 4, SortOrder = Enum.SortOrder.LayoutOrder,
}, tabBar)
App.pages, App.tabs = {}, {}
for index, title in ipairs({"Farm", "Mục tiêu", "Bay / Đi", "ESP / FPS", "Counter", "Nhân vật", "Nút MB", "Cài đặt"}) do
    local button = App.new("TextButton", {
        Size = UDim2.fromOffset(100, 46), BackgroundColor3 = index == 1 and C.purple or C.row,
        BorderSizePixel = 0, Text = title, TextColor3 = C.text, TextWrapped = true,
        Font = Enum.Font.GothamMedium, TextSize = 12, LayoutOrder = index,
    }, tabBar)
    App.round(button, 8)
    local page = App.new("ScrollingFrame", {
        Position = UDim2.fromOffset(8, 162), Size = UDim2.new(1, -16, 1, -188),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarImageColor3 = C.purple, Visible = index == 1,
        ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 2,
    }, App.panel)
    App.new("UIPadding", {PaddingRight = UDim.new(0, 7), PaddingBottom = UDim.new(0, 10)}, page)
    App.new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, page)
    App.pages[index], App.tabs[index] = page, button
    button.Activated:Connect(function()
        for other = 1, #App.pages do
            App.pages[other].Visible = other == index
            App.tabs[other].BackgroundColor3 = other == index and C.purple or C.row
        end
    end)
end
App.status = App.new("TextLabel", {
    Position = UDim2.new(0, 12, 1, -22), Size = UDim2.new(1, -24, 0, 17),
    BackgroundTransparency = 1, Text = "F6: Farm  ·  F7: tạm dừng  ·  F8: dừng hết",
    Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = C.text, TextWrapped = true, ZIndex = 2,
    TextXAlignment = Enum.TextXAlignment.Left,
}, App.panel)
App.toasts = {}
App.toastArea = App.new("Frame", {
    AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 15),
    Size = UDim2.new(1, -24, 0, 270), BackgroundTransparency = 1, ZIndex = 30,
}, App.gui)
App.new("UIListLayout", {Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Right}, App.toastArea)
App.toast = function(title, message)
    if not App.alive then return end
    while #App.toasts >= 1 do local old = table.remove(App.toasts, 1); old:Destroy() end
    local viewport = World.CurrentCamera and World.CurrentCamera.ViewportSize or Vector2.new(400, 700)
    local card = App.new("Frame", {
        Size = UDim2.fromOffset(math.min(270, viewport.X - 24), 64), BackgroundColor3 = C.card,
        BorderSizePixel = 0, BackgroundTransparency = 0.35, Active = false,
    }, App.toastArea)
    App.round(card, 10)
    App.new("UIStroke", {Color = C.purple, Transparency = 0.35}, card)
    App.new("TextLabel", {Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 19), BackgroundTransparency = 1, Text = title, TextColor3 = C.red, Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left}, card)
    App.new("TextLabel", {Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 0, 30), BackgroundTransparency = 1, Text = message, TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top}, card)
    local progress = App.new("Frame", {Size = UDim2.new(1, -16, 0, 2), Position = UDim2.new(0, 8, 1, -5), BackgroundColor3 = C.purple, BorderSizePixel = 0}, card)
    Tween:Create(progress, TweenInfo.new(2.5, Enum.EasingStyle.Linear), {Size = UDim2.new(0, 0, 0, 2)}):Play()
    table.insert(App.toasts, card)
    task.delay(2.6, function()
        for i, item in ipairs(App.toasts) do if item == card then table.remove(App.toasts, i); break end end
        pcall(function() card:Destroy() end)
    end)
end

local orderMap = setmetatable({}, {__mode = "k"})
local function nextOrder(parent)
    orderMap[parent] = (orderMap[parent] or 0) + 1
    return orderMap[parent]
end
function App.note(parent, text)
    local label = App.new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 36), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.card, BorderSizePixel = 0, Text = text, TextWrapped = true,
        Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = nextOrder(parent),
    }, parent)
    App.new("UIPadding", {PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10)}, label)
    App.round(label); return label
end
function App.action(parent, text, callback)
    local button = App.new("TextButton", {
        Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = C.row, BorderSizePixel = 0,
        Text = text, TextWrapped = true, TextColor3 = C.text, TextSize = 13,
        Font = Enum.Font.GothamMedium, LayoutOrder = nextOrder(parent),
    }, parent)
    App.round(button)
    button.Activated:Connect(function() App.try(text, callback) end)
    return button
end
function App.toggle(parent, text, key)
    local button = App.action(parent, text, function() App.setFlag(key, not App.flags[key]) end)
    local function refresh()
        button.Text = text .. (App.flags[key] and "  [BẬT]" or "  [TẮT]")
        button.BackgroundColor3 = App.flags[key] and C.purple or C.row
    end
    table.insert(App.refreshers, refresh); refresh(); return button
end
function App.entry(parent, title, initial)
    local frame = App.new("Frame", {Size = UDim2.new(1, 0, 0, 82), BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = nextOrder(parent)}, parent)
    App.round(frame)
    App.new("TextLabel", {Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -20, 0, 23), BackgroundTransparency = 1, Text = title, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Left}, frame)
    local box = App.new("TextBox", {Position = UDim2.fromOffset(9, 33), Size = UDim2.new(1, -18, 0, 40), BackgroundColor3 = C.row, BorderSizePixel = 0, ClearTextOnFocus = false, Text = initial or "", Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = C.text}, frame)
    App.round(box, 6); return box
end
function App.slider(parent, title, key, low, high, step, callback)
    local frame = App.new("Frame", {Size = UDim2.new(1, 0, 0, 84), BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = nextOrder(parent)}, parent)
    App.round(frame)
    App.new("TextLabel", {Position = UDim2.fromOffset(11, 7), Size = UDim2.new(1, -105, 0, 28), BackgroundTransparency = 1, Text = title, TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left}, frame)
    local box = App.new("TextBox", {Position = UDim2.new(1, -90, 0, 5), Size = UDim2.fromOffset(78, 36), BackgroundColor3 = C.row, BorderSizePixel = 0, ClearTextOnFocus = false, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.red}, frame)
    App.round(box, 6)
    local hit = App.new("Frame", {Position = UDim2.new(0, 13, 0, 45), Size = UDim2.new(1, -26, 0, 34), BackgroundTransparency = 1, Active = true}, frame)
    local bar = App.new("Frame", {Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = C.row, BorderSizePixel = 0, Active = true}, hit)
    App.round(bar, 4)
    local fill = App.new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.purple, BorderSizePixel = 0}, bar)
    App.round(fill, 4)
    local thumb = App.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(24, 24), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = C.red, BorderSizePixel = 0, Active = true}, bar)
    App.round(thumb, 9)
    local function paint()
        local alpha = (App.values[key] - low) / (high - low)
        fill.Size, thumb.Position = UDim2.fromScale(alpha, 1), UDim2.fromScale(alpha, 0.5)
        if not box:IsFocused() then box.Text = tostring(App.values[key]) end
    end
    local function set(value)
        if not value or value ~= value or value == math.huge or value == -math.huge then paint(); return end
        local updated = math.clamp(low + math.floor((value - low) / step + 0.5) * step, low, high)
        updated = math.floor(updated * 100 + 0.5) / 100
        App.values[key] = updated; box.Text = tostring(updated); paint()
        if callback then App.try(title, callback, updated) end
    end
    local function fromX(x)
        local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        set(low + alpha * (high - low))
    end
    local function began(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            App.sliderDrag = {input = input, update = fromX}; fromX(input.Position.X)
        end
    end
    hit.InputBegan:Connect(began); bar.InputBegan:Connect(began); thumb.InputBegan:Connect(began)
    box.FocusLost:Connect(function() set(tonumber(box.Text)) end)
    table.insert(App.refreshers, paint); paint()
end
function App.cycle(parent, title, choices, getter, setter)
    local button
    local function refresh() button.Text = title .. ": " .. tostring(getter()) end
    button = App.action(parent, title, function()
        local index = 0
        for i, choice in ipairs(choices) do if choice == getter() then index = i; break end end
        setter(choices[index % #choices + 1]); refresh()
    end)
    table.insert(App.refreshers, refresh); refresh(); return button
end
function App.list(parent)
    local frame = App.new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder(parent)}, parent)
    App.new("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, frame)
    return frame
end
function App.emptyList(parent)
    for _, child in ipairs(parent:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
    orderMap[parent] = 0
end

App.quickDock = App.new("Frame", {Name = "MobileQuickDock", Size = UDim2.fromOffset(280, 44), BackgroundTransparency = 1, ZIndex = 20}, App.gui)
local function quickButton(text, x, width, color)
    local button = App.new("TextButton", {Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(width, 44),
        BackgroundColor3 = color or C.row, BackgroundTransparency = 0.35, BorderSizePixel = 0,
        Text = text, TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 12}, App.quickDock)
    App.round(button); return button
end
function App.hudHandle(handle, frame, kind)
    App.bind(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            App.hudDrag = {input = input, start = input.Position, position = frame.Position, frame = frame, kind = kind}
        end
    end)
end
local dockHandle = quickButton("⋮⋮", 0, 26)
local floating = quickButton("MENU", 30, 52, C.purple)
local floatingFarm = quickButton("FARM", 86, 68)
local floatingFly = quickButton("BAY", 158, 52)
local floatingStop = quickButton("DỪNG", 214, 62, C.red)
App.hudHandle(dockHandle, App.quickDock, "dock")
App.quickFly, App.quickFarm = floatingFly, floatingFarm
App.farmBadge = App.new("TextLabel", {
    AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46),
    Size = UDim2.fromOffset(280, 32), BackgroundColor3 = C.card, BackgroundTransparency = 0.5, BorderSizePixel = 0,
    Text = "", TextWrapped = true, TextColor3 = C.text, Font = Enum.Font.GothamMedium,
    TextSize = 11, Visible = false, ZIndex = 19, Active = false,
}, App.gui)
App.round(App.farmBadge)
App.flightHud = App.new("Frame", {Name = "DraggableFlightPad", Size = UDim2.fromOffset(160, 142), BackgroundTransparency = 1, Visible = false, ZIndex = 20}, App.gui)
local flyHandle = App.new("TextButton", {Size = UDim2.fromOffset(160, 24), BackgroundColor3 = C.card, BackgroundTransparency = 0.4, BorderSizePixel = 0, Text = "⋮⋮  KÉO CỤM BAY", TextColor3 = C.text, TextSize = 10, Font = Enum.Font.GothamBold}, App.flightHud)
App.round(flyHandle); App.hudHandle(flyHandle, App.flightHud, "fly")
App.flyButtons = {}
for index, title in ipairs({"▲ LÊN", "▼ XUỐNG", "TẮT BAY"}) do
    local position = index == 3 and UDim2.fromOffset(0, 98) or UDim2.fromOffset((index - 1) * 84, 28)
    local size = index == 3 and UDim2.fromOffset(160, 44) or UDim2.fromOffset(76, 64)
    local button = App.new("TextButton", {Position = position, Size = size, BackgroundColor3 = index == 3 and C.red or C.row, BackgroundTransparency = 0.25, BorderSizePixel = 0, Text = title, TextColor3 = C.text, TextSize = 13, Font = Enum.Font.GothamBold}, App.flightHud)
    App.flyButtons[index] = button
    App.round(button)
    if index == 3 then button.Activated:Connect(function() App.setFlag("fly", false) end)
    else
        local direction = index == 1 and "up" or "down"
        button.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                App.flyTouches[direction][input] = true
            end
        end)
        button.InputEnded:Connect(function(input) App.flyTouches[direction][input] = nil end)
    end
end
function App.showMenu(visible)
    App.panel.Visible = visible
    App.flightHud.Visible = App.flags.fly
    floating.Text = visible and "ẨN" or "MENU"
    if visible then
        App.captureAction = nil
        if App.goal and App.goal.priority == 10 then App.goal = nil end
        App.releaseAll()
        if App.flags.farm then App.farmReport("TẠM DỪNG", "Thu gọn menu hoặc bấm TIẾP TỤC để chạy lại.") end
    end
    App.refresh()
    if App.refreshFarmUI then App.refreshFarmUI() end
end
table.insert(App.refreshers, function()
    App.flightHud.Visible = App.flags.fly
    floatingFly.Text = App.flags.fly and "BAY ✓" or "BAY"
    floatingFly.BackgroundColor3 = App.flags.fly and C.purple or C.row
end)
floatingFarm.Activated:Connect(function() if App.flags.farm then App.stopFarm() else App.startFarm() end end)
floating.Activated:Connect(function() App.showMenu(not App.panel.Visible) end)
floatingFly.Activated:Connect(function() App.setFlag("fly", not App.flags.fly); if App.flags.fly then App.showMenu(false) end end)
floatingStop.Activated:Connect(function() App.stopAll("Đã tắt và khôi phục thay đổi.") end)
emergency.Activated:Connect(function() App.stopAll("Đã tắt và khôi phục thay đổi.") end)
minimize.Activated:Connect(function() App.showMenu(false) end)
close.Activated:Connect(App.unload)

local homePage = App.pages[1]
local combatPage, movePage, optimizePage = App.pages[2], App.pages[3], App.pages[4]
local counterPage, characterPage, mobilePage, protect = App.pages[5], App.pages[6], App.pages[7], App.pages[8]
local emotePage = characterPage
App.primaryFarm = App.action(homePage, "BẮT ĐẦU AUTO FARM", function()
    if App.flags.farm then App.stopFarm() else App.startFarm() end
end)
App.primaryFarm.Size, App.primaryFarm.TextSize = UDim2.new(1, 0, 0, 52), 15
App.resumeFarm = App.action(homePage, "TIẾP TỤC • THU GỌN MENU", function()
    if not App.flags.farm then App.startFarm()
    else App.flags.farmPaused = false; App.showMenu(false); App.refresh() end
end)
App.farmStatusLabel = App.note(homePage, "Bấm BẮT ĐẦU AUTO FARM. Mặc định tự chọn người gần nhất nếu chưa chọn ai.")
App.farmStatusLabel.TextColor3, App.farmStatusLabel.Size = C.text, UDim2.new(1, 0, 0, 72)
function App.refreshFarmUI()
    if not App.alive then return end
    local now = os.clock()
    if App.flags.farm and now - App.lastGuiPaint < 0.12 then return end
    App.lastGuiPaint = now
    local target = App.farmDisplayTarget
    local targetText = target and App.name(target) or "—"
    local distance = App.farmDistance and string.format(" · %.1f studs", App.farmDistance) or ""
    App.primaryFarm.Text = App.flags.farm and "DỪNG AUTO FARM" or "BẮT ĐẦU AUTO FARM"
    App.primaryFarm.BackgroundColor3 = App.flags.farm and C.red or C.purple
    App.resumeFarm.Text = App.flags.farm and "TIẾP TỤC • THU GỌN MENU" or "BẮT ĐẦU VỚI CÀI ĐẶT HIỆN TẠI"
    App.farmStatusLabel.Text = App.farmPhase .. "\n" .. App.farmReason .. "\nMục tiêu: " .. targetText .. distance .. "\nM1 đã gửi: " .. tostring(App.farmSent) .. " · " .. App.inputBackend
    floatingFarm.Text = App.flags.farm and "FARM ✓" or "FARM"
    floatingFarm.BackgroundColor3 = App.flags.farm and C.red or C.row
    App.farmBadge.Visible = App.flags.farm and not App.panel.Visible
    App.farmBadge.Text = App.farmPhase .. " · " .. targetText .. distance
end
table.insert(App.refreshers, App.refreshFarmUI)
App.note(homePage, "FARM: tự tìm và bám mục tiêu. MENU tạm dừng. Mobile không nhận nút → tab Nút MB để gán bằng chạm.")
App.cycle(homePage, "Chọn mục tiêu", {"Gần nhất", "Chọn thủ công"}, function() return App.targetMode end, function(value)
    App.releaseAll("combat"); App.goal = nil; App.current = nil; App.targetMode = value
end)
App.cycle(homePage, "Auto tele", {"Nhanh", "Êm"}, function() return App.teleMode end, function(value)
    App.teleMode = value; App.lastFollowAt = -math.huge
end)
App.cycle(homePage, "Cách gửi M1 trên PC", {"Tự động", "Input", "GUI Nhấn/Thả", "GUI Activated"}, function() return App.m1Mode end, function(value)
    App.releaseAll("combat"); App.m1Mode = value; App.rejected = {}; App.lastInputError = ""
    App.inputBackend = "Chưa gửi M1"; App.refreshFarmUI()
end)
App.toggle(homePage, "Kèm Skill 1–4 khi Farm", "farmSkills")
App.slider(homePage, "Phạm vi tìm mục tiêu", "targetRange", 50, 1000, 25)
App.slider(homePage, "Khoảng đứng sau lưng", "distance", 3, 8, 0.5)
App.slider(homePage, "Tầm bắt đầu M1", "attackRange", 4, 8, 0.5)
App.slider(homePage, "Khoảng nghỉ giữa tele xa", "teleInterval", 0.15, 1, 0.05)
local gameButtonList = App.list(homePage)
local scanGameButtons = App.action(homePage, "CHỌN NÚT ĐÁNH THẬT CỦA GAME", function()
    App.emptyList(gameButtonList)
    local buttons = App.gameButtons()
    table.sort(buttons, function(a, b) return a.Name < b.Name end)
    for index, button in ipairs(buttons) do
        if index > 50 then break end
        local candidate = button
        App.action(gameButtonList, (button.Parent and button.Parent.Name or "") .. " / " .. button.Name, function()
            App.boundPunch = candidate; App.rejected.mouse = nil
            App.notify("Đã chọn nút M1", "Chỉ chọn nút đánh thường, không chọn nút nhảy hoặc skill. Thử GUI Nhấn/Thả hoặc GUI Activated.")
        end)
    end
    if #buttons == 0 then App.note(gameButtonList, "Không có nút game đang hiển thị. Trên PC, dùng Input nếu executor hỗ trợ.") end
end)
scanGameButtons.LayoutOrder, gameButtonList.LayoutOrder = gameButtonList.LayoutOrder, scanGameButtons.LayoutOrder
App.action(homePage, "KIỂM TRA LẠI API INPUT", function()
    Caps.signal, Caps.connections = api("firesignal"), api("getconnections")
    Caps.click, Caps.down, Caps.up = api("mouse1click"), api("mouse1press"), api("mouse1release")
    App.rejected, App.inputFailures, App.lastInputError = {}, {}, ""
    App.notify("Đã xóa trạng thái lỗi cũ", "Lần gửi M1 tiếp theo sẽ thử lại API. Không bảo đảm executor cấp quyền.")
end)
App.diagnosticLabel = App.note(homePage, "CHẨN ĐOÁN: bấm nút bên dưới nếu Farm không đánh được.")
App.action(homePage, "XEM / SAO CHÉP CHẨN ĐOÁN", function()
    local report = App.diagnostics()
    App.diagnosticLabel.Text = report
    local clipboard = api("setclipboard") or api("toclipboard")
    if clipboard then pcall(clipboard, report); App.notify("Chẩn đoán", "Đã thử sao chép log để bạn gửi khi báo lỗi.") end
end)
App.note(mobilePage, "Nút điện thoại được giữ nguyên. Nếu auto không nhận đúng nút: bấm GÁN rồi chạm nút thật của game một lần. Không dùng phím 1–4 giả trên mobile.")
App.cycle(mobilePage, "Thiết bị", {"Tự động", "Điện thoại", "PC"}, function() return App.platform end, function(value)
    App.releaseAll(); App.platform = value; App.rejected = {}; App.fit(true)
end)
App.mobileBindingStatus = App.note(mobilePage, "")
function App.refreshBindings()
    local lines = {App.isMobile() and "MOBILE · phím/chuột PC đã khóa" or "PC · input theo executor"}
    for _, key in ipairs({"M1", "One", "Two", "Three", "Four", "F"}) do
        local button = App.actionButton(key)
        table.insert(lines, key .. ": " .. (button and button.Name or "chưa nhận diện"))
    end
    App.mobileBindingStatus.Text = table.concat(lines, "\n")
end
for _, definition in ipairs({{"M1", "ĐẤM"}, {"One", "CHIÊU 1"}, {"Two", "CHIÊU 2"}, {"Three", "CHIÊU 3"}, {"Four", "CHIÊU 4"}, {"F", "BLOCK"}}) do
    local key, title = definition[1], definition[2]
    App.action(mobilePage, "GÁN " .. title .. " → chạm nút game", function()
        App.showMenu(false); App.captureAction = key; App.releaseAll("combat")
        App.notify("Gán " .. title, "Chạm nút thật của game. MENU để hủy.")
    end)
    App.cycle(mobilePage, title .. " • sự kiện", {"Tự động", "Activated", "Click", "Touch", "Nhấn/Thả", "TouchTap"},
        function() return App.buttonModes[key] or "Tự động" end,
        function(value) App.release(key); App.buttonModes[key] = value end)
end
App.action(mobilePage, "TỰ DÒ LẠI CÁC NÚT", function()
    App.autoPunch, App.autoButtons, App.actionScan, App.guiScanAt = nil, {}, {}, -math.huge
    App.refreshBindings()
end)
function App.handleTouch(input)
    if input.UserInputType ~= Enum.UserInputType.Touch then return end
    App.lastTouch = input
    local ok, objects = pcall(function() return PlayerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y) end)
    if not ok then return end
    if App.captureAction then
        for _, object in ipairs(objects) do
            local button = object
            while button and button ~= PlayerGui and not button:IsA("GuiButton") do button = button.Parent end
            if App.visibleGameButton(button) then
                local key = App.captureAction
                if key == "M1" then App.boundPunch = button else App.actionButtons[key] = button end
                App.captureAction = nil; App.refreshBindings()
                App.notify("Đã gán " .. key, button.Name .. " · dùng nút game, không gửi phím PC.")
                return
            end
        end
        return
    end
    if not App.flags.farm or App.panel.Visible then return end
    for _, key in ipairs({"M1", "One", "Two", "Three", "Four", "F"}) do
        local button = App.actionButton(key)
        if button then
            for _, object in ipairs(objects) do
                if object == button or object:IsDescendantOf(button) then
                    App.manualUntil = os.clock() + (key == "M1" and 0.25 or 0.65)
                    App.releaseAll("combat")
                    return
                end
            end
        end
    end
end
App.note(protect, "UwUNCTT · nctt\nMenu client độc lập. Nhận diện API không đồng nghĩa đã kiểm chứng mọi executor. Không có anti-ban tuyệt đối.")
App.slider(protect, "Độ trong của menu (%)", "guiFade", 25, 85, 5, App.applyTheme)
App.action(protect, "Đặt lại vị trí thanh nổi / cụm bay", function()
    App.dockMoved, App.flyMoved = false, false; App.fit(true)
end)
App.action(protect, "Tải lại ảnh nền", function() task.spawn(App.loadWallpaper) end)
App.toggle(protect, "Safe Mode: chỉ giảm tần suất", "safe")
App.toggle(protect, "Anonymizer: tên giả trong menu / ESP", "anonymous")
App.slider(protect, "Tốc độ nội suy (studs/giây)", "travel", 20, 200, 5)
App.note(protect, "Nội suy không phải Teleport Bypass. pcall chỉ bắt lỗi Lua; không chặn lệnh kick hoặc phát hiện từ máy chủ. Anonymizer chỉ đổi hình ảnh phía bạn.")
App.action(protect, "Xem API đã nhận diện", function()
    local lines = {"Executor: " .. executor, "getgenv: " .. tostring(type(getgenv) == "function"), "gethui: " .. tostring(Caps.gethui ~= nil), "VirtualInputManager: " .. tostring(VIM ~= nil)}
    for _, name in ipairs({"click", "down", "up", "keydown", "keyup", "signal", "connections", "fpsset", "fpsget", "touch"}) do
        table.insert(lines, name .. ": " .. tostring(Caps[name] ~= nil))
    end
    local synAvailable = false
    for _, root in ipairs(roots) do
        pcall(function() if type(root.syn) == "table" then synAvailable = true end end)
    end
    table.insert(lines, "syn: " .. tostring(synAvailable))
    App.apiLabel.Text = table.concat(lines, "\n")
end)
App.apiLabel = App.note(protect, "Bấm Xem API để kiểm tra khả năng hiện có. Có API chưa chứng minh API được phép gọi hoặc thực hiện được hành động.")

App.note(characterPage, "Không có Void Target / All Players, Godmode máy chủ hoặc tàng hình với người khác trong bản này. Client không có sẵn quyền kiểm soát máu, quyền mua hay vị trí người chơi khác.")
App.toggle(characterPage, "Anti-Void Self: về điểm đứng đã ghi", "antiVoid")
App.slider(characterPage, "Ngưỡng Y chống rơi", "voidY", -500, 0, 5)
App.action(characterPage, "Về điểm mặt đất đã ghi", function()
    if not App.lastGround then App.notify("Anti-Void", "Chưa ghi được điểm đứng trên mặt đất."); return end
    App.stopCombat()
    App.moveTo(App.lastGround, 1000, 0, true)
end)
App.toggle(characterPage, "Ẩn nhân vật CHỈ TRÊN MÁY BẠN", "hidden")
App.note(characterPage, "Anti-Void cần ghi được một điểm đứng trước khi rơi. Chỉnh ngưỡng dưới mặt đất của map. Ẩn cục bộ không đổi hitbox hoặc làm đối thủ mất dấu.")

App.targetLabel = App.note(combatPage, "Chưa chọn người chơi.")
local search = App.entry(combatPage, "Tìm người chơi / tên giả", "")
local roster = App.list(combatPage)
function App.updateRoster()
    App.emptyList(roster)
    local filter, list = string.lower(search.Text), Players:GetPlayers()
    table.sort(list, function(a, b) return a.Name < b.Name end)
    for _, player in ipairs(list) do
        local display = App.name(player)
        if player ~= Me and (filter == "" or string.find(string.lower(display), filter, 1, true)) then
            local candidate = player
            local button = App.action(roster, display, function()
                App.releaseAll("combat"); App.goal = nil; App.selected, App.current = candidate.UserId, nil
                App.targetMode = "Chọn thủ công"; App.awakeNotice = nil
                App.updateRoster(); App.refresh()
            end)
            if App.selected == candidate.UserId then button.BackgroundColor3 = C.purple end
        end
    end
    local selected = App.selectedPlayer()
    App.targetLabel.Text = selected and ("Đã chọn: " .. App.name(selected)) or "Chưa chọn người chơi."
end
search:GetPropertyChangedSignal("Text"):Connect(App.updateRoster)
App.cycle(combatPage, "Mục tiêu", {"Chọn thủ công", "Gần nhất"}, function() return App.targetMode end, function(value)
    App.releaseAll("combat"); App.goal = nil; App.targetMode, App.current = value, nil
end)
App.action(combatPage, "Di chuyển cạnh người đã chọn", App.warpTarget)
App.toggle(combatPage, "Behind Target Lock (nội suy)", "lock")
App.slider(combatPage, "Khoảng cách sau lưng", "distance", 3, 10, 0.5)
App.toggle(combatPage, "Auto M1 (input mô phỏng)", "m1")
App.toggle(combatPage, "Auto Skill 1–4 (input mô phỏng)", "skills")
App.slider(combatPage, "Khoảng cách giữa M1 (giây)", "m1Gap", 0.2, 1.5, 0.05)
App.slider(combatPage, "Khoảng cách giữa phím skill", "skillGap", 0.25, 2, 0.05)
App.note(combatPage, "Chọn mục tiêu hoặc chế độ Gần nhất. Auto input tự ẩn menu. Mouse API trên PC cần con trỏ ở vùng chơi. Cooldown, damage và kill do máy chủ quyết định.")
App.toggle(combatPage, "Đổi mục tiêu khi cờ nộ khớp", "switchAwake")
App.toggle(combatPage, "Cờ thiếu = không nộ (tự lựa chọn)", "missingInactive")
App.bindingLabel = App.note(combatPage, "Chưa cấu hình cờ nộ. Để mục tiêu bật nộ, quét và chọn thuộc tính thể hiện ĐANG nộ; không chọn thanh tích nộ.")
local attributes = App.list(combatPage)
local scanAttributes = App.action(combatPage, "Quét thuộc tính thực của người đã chọn", function()
    App.emptyList(attributes)
    local target = App.selectedPlayer()
    if not target then App.notify("Thuộc tính", "Chọn người chơi trước."); return end
    local count = 0
    for _, source in ipairs({"Player", "Character"}) do
        local object = source == "Player" and target or target.Character
        if object then
            local attrs, names = object:GetAttributes(), {}
            for key in pairs(attrs) do table.insert(names, key) end
            table.sort(names)
            for _, key in ipairs(names) do
                local value = attrs[key]
                local kind = typeof(value)
                if count < 40 and (kind == "boolean" or kind == "number" or kind == "string") then
                    count = count + 1
                    local observedSource, observedKey, observedValue = source, key, value
                    App.action(attributes, source .. " · " .. key .. " = " .. tostring(value):sub(1, 55), function()
                        App.flags.switchAwake = false
                        App.binding = {source = observedSource, key = observedKey, value = observedValue}
                        App.bindingLabel.Text = "Cờ đang nộ: " .. observedSource .. "." .. observedKey .. " = " .. tostring(observedValue)
                        App.refresh(); App.notify("Đã gán cờ nộ", "Bật đổi mục tiêu sau khi xác nhận đúng trạng thái.")
                    end)
                end
            end
        end
    end
    if count == 0 then App.note(attributes, "Không có thuộc tính đơn giản có thể đọc. Không có cơ chế tự nhận nộ được cấu hình.") end
end)
scanAttributes.LayoutOrder, attributes.LayoutOrder = attributes.LayoutOrder, scanAttributes.LayoutOrder

App.note(counterPage, "Chưa có AnimationId mặc định. Chọn đúng ID quan sát được rồi gán Block / Counter / Ultimate. Không bảo đảm phản ứng đúng mọi chiêu hoặc né 100%.")
App.toggle(counterPage, "Auto Block theo ID đã gán", "block")
App.toggle(counterPage, "Dodge Counter theo ID đã gán", "dodge")
App.toggle(counterPage, "Dodge Ultimate theo ID đã gán", "ultDodge")
App.slider(counterPage, "Bán kính phản ứng (studs)", "radius", 5, 30, 1)
App.slider(counterPage, "Khoảng rút lui (studs)", "retreat", 15, 80, 1)
App.cycle(counterPage, "Né Ultimate", {"Ra xa", "Sau lưng"}, function() return App.ultMode end, function(value) App.ultMode = value end)
local animationIdBox = App.entry(counterPage, "AnimationId (số hoặc rbxassetid://ID)", "")
local animationLabel = App.entry(counterPage, "Tên chiêu hiển thị trên ESP", "")
App.animationKind = "Block"
App.cycle(counterPage, "Nhóm của ID", {"Block", "Counter", "Ultimate"}, function() return App.animationKind end, function(value) App.animationKind = value end)
local function enteredAnimationId()
    return animationIdBox.Text:match("^%s*(%d+)%s*$") or animationIdBox.Text:match("^%s*rbxassetid://(%d+)%s*$")
end
App.rulesLabel = App.note(counterPage, "Chưa gán ID.")
local function rulesSummary()
    local ids, lines = {}, {}
    for id in pairs(App.animations) do table.insert(ids, id) end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local rule = App.animations[id]
        table.insert(lines, rule.kind .. " · " .. id .. " · " .. rule.label)
    end
    App.rulesLabel.Text = #lines > 0 and table.concat(lines, "\n") or "Chưa gán ID."
    for flag, category in pairs({block = "Block", dodge = "Counter", ultDodge = "Ultimate"}) do
        local found = false
        for _, rule in pairs(App.animations) do if rule.kind == category then found = true end end
        if not found then App.flags[flag] = false; if flag == "block" then App.releaseAll("block") end end
    end
    App.refresh()
end
App.action(counterPage, "Lưu / cập nhật quy tắc ID", function()
    local id = enteredAnimationId()
    if not id then App.notify("AnimationId", "Nhập một ID hợp lệ."); return end
    local label = animationLabel.Text:sub(1, 50)
    App.animations[id] = {kind = App.animationKind, label = label ~= "" and label or ("ID " .. id)}
    rulesSummary(); App.notify("Đã lưu ID", id .. " → " .. App.animationKind)
end)
App.action(counterPage, "Bỏ quy tắc ID trong ô", function()
    local id = enteredAnimationId()
    if id then App.animations[id] = nil; rulesSummary() end
end)
local observedList = App.list(counterPage)
local observedButton = App.action(counterPage, "Xem hoạt ảnh đã quan sát gần đây", function()
    App.emptyList(observedList)
    for _, id in ipairs(App.recentOrder) do
        local candidateId = id
        local data = App.recent[id]
        App.action(observedList, id .. " · " .. tostring(data and data.name or "Animation"), function()
            animationIdBox.Text = candidateId
            local existing = App.animations[candidateId]
            animationLabel.Text = existing and existing.label or ""
            App.notify("Đã chọn ID", "Chọn nhóm, đặt tên rồi bấm Lưu.")
        end)
    end
    if #App.recentOrder == 0 then App.note(observedList, "Chưa thấy hoạt ảnh. Đứng gần mục tiêu đang dùng chiêu rồi xem lại.") end
end)
observedButton.LayoutOrder, observedList.LayoutOrder = observedList.LayoutOrder, observedButton.LayoutOrder

App.note(emotePage, "Phát animation bằng ID có quyền sử dụng. Bản này không mở khóa quyền sở hữu emote VIP, Robux hay sự kiện; không có danh sách emote TSB giả định.")
local emoteId = App.entry(emotePage, "AnimationId", "")
local emoteName = App.entry(emotePage, "Tên lưu cho phiên chơi", "")
App.emoteCategory, App.favorites, App.favoriteIndex = "Dance", {}, 0
App.toggle(emotePage, "Lặp animation", "loopEmote")
App.cycle(emotePage, "Nhóm lưu thủ công", {"Dance", "Troll", "Flex", "Victory", "Special"}, function() return App.emoteCategory end, function(value) App.emoteCategory = value; App.favoriteIndex = 0 end)
App.action(emotePage, "Phát ID trong ô", function() App.playEmote(emoteId.Text) end)
App.action(emotePage, "DỪNG EMOTE", App.stopEmote)
App.favoriteLabel = App.note(emotePage, "Chưa chọn animation yêu thích.")
App.action(emotePage, "Lưu ID vào nhóm hiện tại", function()
    local id = emoteId.Text:match("^%s*(%d+)%s*$") or emoteId.Text:match("^%s*rbxassetid://(%d+)%s*$")
    if not id then App.notify("Emote", "Nhập một AnimationId hợp lệ."); return end
    if #App.favorites >= 50 then App.notify("Emote", "Đã đủ 50 mục cho phiên này."); return end
    table.insert(App.favorites, {id = id, kind = App.emoteCategory, name = emoteName.Text ~= "" and emoteName.Text:sub(1, 45) or id})
    App.notify("Đã lưu cho phiên chơi", App.emoteCategory .. " · " .. id)
end)
App.action(emotePage, "Chọn mục tiếp theo trong nhóm", function()
    local matching = {}
    for _, item in ipairs(App.favorites) do if item.kind == App.emoteCategory then table.insert(matching, item) end end
    if #matching == 0 then App.notify("Emote", "Nhóm này chưa có ID đã lưu."); return end
    App.favoriteIndex = App.favoriteIndex % #matching + 1
    local item = matching[App.favoriteIndex]
    emoteId.Text, emoteName.Text = item.id, item.name
    App.favoriteLabel.Text = item.kind .. " · " .. item.name .. " · " .. item.id
end)

App.toggle(movePage, "WalkSpeed (client)", "speed")
App.slider(movePage, "Tốc độ chạy", "speed", 16, 200, 1)
App.toggle(movePage, "Fly: WASD / joystick", "fly")
App.slider(movePage, "Tốc độ bay", "fly", 10, 150, 5)
App.toggle(movePage, "Bật lướt tự tạo", "dash")
App.action(movePage, "LƯỚT NGAY (hoặc phím J)", function() App.dash() end)
App.slider(movePage, "Khoảng lướt tự tạo", "dashLength", 5, 25, 1)
App.toggle(movePage, "Ổn định ragdoll / knockback (thử)", "stabilize")
App.note(movePage, "Các thay đổi chuyển động có thể bị server ghi đè hoặc xử lý. Lướt tự tạo không reset cooldown, không có iframe của dash TSB. Ẩn menu để dùng nút bay trên điện thoại.")
App.action(movePage, "Lưu vị trí hiện tại", function()
    local _, _, root = App.parts(Me)
    if root then App.saved = root.CFrame; App.notify("Điểm đã lưu", "Chỉ lưu trong phiên chơi này.") end
end)
App.action(movePage, "Di chuyển về điểm đã lưu", function()
    if not App.saved then App.notify("Di chuyển", "Chưa lưu điểm."); return end
    App.stopCombat()
    if App.flags.fly then App.flags.fly = false; App.stopFly(); App.refresh() end
    App.moveTo(App.saved, 100, 5, false)
end)
App.action(movePage, "Di chuyển cạnh thùng rác gần nhất", App.warpTrash)
App.toggle(movePage, "Bật ESP", "esp")
App.toggle(movePage, "Box ESP", "boxes")
App.toggle(movePage, "Tracers", "tracers")
App.toggle(movePage, "Chams Highlight xuyên tường", "chams")
App.slider(movePage, "Khoảng cách ESP tối đa", "espDistance", 50, 1000, 25)
App.note(movePage, "Tên chiêu trên ESP lấy từ nhãn AnimationId bạn đã gán. ID chưa gán chỉ hiển thị số, không đoán tên chiêu.")

App.toggle(optimizePage, "Potato: giảm bóng / vật liệu / effect", "potato")
App.toggle(optimizePage, "Fullbright cục bộ", "bright")
App.toggle(optimizePage, "Ẩn mảnh vỡ tên Debris/Rubble/Fragments", "fragments")
App.note(optimizePage, "Đổi đồ họa phía máy bạn, có khôi phục. Ẩn mảnh vỡ theo tên không xóa dữ liệu server hoặc giải phóng vật thể của server. FPS tăng hay giảm phụ thuộc máy và cảnh.")
App.toggle(optimizePage, "Dùng FPS cap của executor", "fpsCap")
App.slider(optimizePage, "FPS cap (0 tùy API: không giới hạn)", "fpsCap", 0, 360, 1, function(value)
    if App.flags.fpsCap and Caps.fpsset then
        local ok = pcall(Caps.fpsset, value)
        if not ok then App.setFlag("fpsCap", false); App.notify("FPS cap", "API từ chối giá trị; đã thử khôi phục cap gốc.") end
    end
end)
App.note(optimizePage, "Không ép GC định kỳ vì có thể gây khựng và Roblox thường giới hạn lệnh này. Menu tự dọn đối tượng của mình và ngắt kết nối khi gỡ.")
App.action(optimizePage, "Thử yêu cầu GC một lần", function()
    if type(collectgarbage) ~= "function" then App.notify("GC", "Môi trường không cung cấp collectgarbage."); return end
    local ok = pcall(collectgarbage, "collect")
    App.notify("GC", ok and "API đã nhận yêu cầu; không bảo đảm cải thiện FPS." or "Môi trường không cho phép ép thu gom bộ nhớ.")
end)
App.action(optimizePage, "Dừng và khôi phục toàn bộ", function() App.stopAll("Đã tắt các thay đổi và nhả input.") end)

-- 08. Responsive layout, input routing and bounded main loops.
function App.fit(recenter)
    local camera = World.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local top, bottom = GuiService:GetGuiInset()
    local mobile, landscape = App.isMobile(), viewport.X > viewport.Y
    local width = math.max(260, math.min(mobile and (landscape and 400 or 360) or 560, viewport.X - 24))
    local availableHeight = viewport.Y - top.Y - bottom.Y - 18
    local height = math.max(240, math.min(mobile and (landscape and 360 or 440) or 540, availableHeight))
    App.panel.Size = UDim2.fromOffset(width, height)
    local columns, navigationHeight = 4, 94
    App.navGrid.FillDirectionMaxCells = columns
    App.navGrid.CellSize = UDim2.new(1 / columns, -5, 0, 44)
    App.tabBar.Size = UDim2.new(1, -16, 0, navigationHeight)
    local pageTop = 61 + navigationHeight + 7
    for _, page in ipairs(App.pages) do
        page.Position = UDim2.fromOffset(8, pageTop)
        page.Size = UDim2.new(1, -16, 1, -pageTop - 26)
    end
    local function keepHud(frame, wantedX, wantedY)
        local size = frame.Size
        frame.Position = UDim2.fromOffset(math.clamp(wantedX, 6, math.max(6, viewport.X - size.X.Offset - 6)),
            math.clamp(wantedY, top.Y + 4, math.max(top.Y + 4, viewport.Y - bottom.Y - size.Y.Offset - 6)))
    end
    keepHud(App.quickDock, App.dockMoved and App.quickDock.Position.X.Offset or (viewport.X - 280) / 2,
        App.dockMoved and App.quickDock.Position.Y.Offset or top.Y + 6)
    keepHud(App.flightHud, App.flyMoved and App.flightHud.Position.X.Offset or viewport.X * (landscape and 0.73 or 0.53) - 80,
        App.flyMoved and App.flightHud.Position.Y.Offset or viewport.Y * 0.36)
    App.farmBadge.Size = UDim2.fromOffset(math.min(280, viewport.X - 24), 32)
    App.farmBadge.Position = UDim2.fromOffset(App.quickDock.Position.X.Offset + 140, App.quickDock.Position.Y.Offset + 48)
    local wantedX = recenter and viewport.X / 2 or App.panel.Position.X.Scale * viewport.X + App.panel.Position.X.Offset
    local wantedY = recenter and (viewport.Y + top.Y - bottom.Y) / 2 or App.panel.Position.Y.Scale * viewport.Y + App.panel.Position.Y.Offset
    local x = math.clamp(wantedX, width / 2 + 6, math.max(width / 2 + 6, viewport.X - width / 2 - 6))
    local y = math.clamp(wantedY, top.Y + height / 2 + 6, math.max(top.Y + height / 2 + 6, viewport.Y - bottom.Y - height / 2 - 6))
    App.panel.Position = UDim2.fromOffset(x, y)
end
function App.pauseControls(message)
    local wasActive = App.flags.farm or App.flags.fly or App.flags.speed or App.flags.lock or App.flags.m1 or App.flags.skills or App.flags.block
    App.releaseAll(); App.goal = nil
    if not App.flags.farm then App.flags.lock, App.flags.m1, App.flags.skills = false, false, false end
    App.flags.block = false
    App.flags.fly, App.flags.speed, App.flags.stabilize = false, false, false
    App.stopFly(); App.restore("speed"); App.restore("stabilize"); App.stopEmote()
    App.keys, App.upPointer, App.downPointer = {}, nil, nil
    App.refresh()
    if App.flags.farm then App.farmReport("TẠM DỪNG", message or "Chờ nhân vật sẵn sàng để tiếp tục.") end
    if wasActive and message then App.notify("Tạm dừng điều khiển", message) end
end
App.focused = true
local drag
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        if input.Position.X > header.AbsolutePosition.X + header.AbsoluteSize.X - 156 then return end
        drag = {input = input, start = input.Position, position = App.panel.Position}
    end
end)
App.bind(Input.InputChanged, function(input)
    local slider = App.sliderDrag
    local hud = App.hudDrag
    if hud and (input == hud.input or (hud.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
        local delta = input.Position - hud.start
        hud.frame.Position = UDim2.fromOffset(hud.position.X.Offset + delta.X, hud.position.Y.Offset + delta.Y)
        App[hud.kind .. "Moved"] = true
        App.fit(false)
    elseif slider and (input == slider.input or (slider.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
        slider.update(input.Position.X)
    elseif drag and (input == drag.input or (drag.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
        local delta = input.Position - drag.start
        App.panel.Position = UDim2.fromOffset(drag.position.X.Offset + delta.X, drag.position.Y.Offset + delta.Y)
    end
end)
App.bind(Input.InputEnded, function(input)
    App.keys[input.KeyCode] = nil
    if input == App.upPointer then App.upPointer = nil end
    if input == App.downPointer then App.downPointer = nil end
    App.flyTouches.up[input], App.flyTouches.down[input] = nil, nil
    if App.hudDrag and input == App.hudDrag.input then App.hudDrag = nil end
    if App.sliderDrag and input == App.sliderDrag.input then App.sliderDrag = nil end
    if drag and input == drag.input then drag = nil; App.fit(false) end
end)
App.bind(Input.InputBegan, function(input, processed)
    App.handleTouch(input)
    if Input:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.F8 then App.stopAll("Đã dừng và khôi phục."); App.showMenu(true); return end
    if not processed and input.KeyCode == Enum.KeyCode.F6 then
        if App.flags.farm then App.stopFarm() else App.startFarm() end
        return
    end
    if not processed and input.KeyCode == Enum.KeyCode.F7 and App.flags.farm then
        App.flags.farmPaused = not App.flags.farmPaused
        App.releaseAll("combat"); App.goal = nil
        App.farmReport(App.flags.farmPaused and "TẠM DỪNG" or "ĐANG TÌM", App.flags.farmPaused and "F7 hoặc nút TIẾP TỤC để chạy lại." or "Đang tiếp tục Farm.")
        return
    end
    if not processed and input.KeyCode == Enum.KeyCode.RightShift then App.showMenu(not App.panel.Visible); return end
    if not processed then
        App.keys[input.KeyCode] = true
        if input.KeyCode == Enum.KeyCode.J then App.try("Lướt", App.dash) end
    end
end)
App.bind(Input.WindowFocusReleased, function() App.focused = false; App.pauseControls("Cửa sổ mất focus; input tự động đã nhả.") end)
App.bind(Input.WindowFocused, function() App.focused = true end)
App.bind(Me.CharacterRemoving, function()
    App.pauseControls()
    App.lastGround, App.current, App.hiddenParts = nil, nil, {}
    App.farmTargetId, App.farmHealth = nil, nil
    if App.flags.farm then App.farmReport("CHỜ HỒI SINH", "Farm vẫn bật, chờ nhân vật mới.") end
    App.restore("hidden"); App.restore("anonymous")
end)
App.bind(Players.PlayerAdded, function(player) App.watch(player); App.updateRoster() end)
App.bind(Players.PlayerRemoving, function(player)
    App.unwatch(player)
    task.defer(function() if App.alive then App.updateRoster() end end)
end)
for _, player in ipairs(Players:GetPlayers()) do App.watch(player) end
App.bind(World.DescendantAdded, function(object)
    if (App.flags.potato or App.flags.fragments) and #App.queue < 20000 then table.insert(App.queue, object) end
end)
App.bind(Lighting.DescendantAdded, function(object)
    if App.flags.potato then table.insert(App.queue, object) end
end)
local function watchCamera()
    if App.cameraConnection then App.cameraConnection:Disconnect() end
    local camera = World.CurrentCamera
    if camera then App.cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() App.fit(true) end) end
    App.fit(true)
end
App.bind(World:GetPropertyChangedSignal("CurrentCamera"), watchCamera)
App.hiddenParts = {}
local function renderStep(dt)
    if not App.alive then return end
    App.fpsFrames, App.fpsTime = App.fpsFrames + 1, App.fpsTime + dt
    if App.fpsTime >= 1 then
        App.fps = math.floor(App.fpsFrames / App.fpsTime + 0.5)
        App.fpsFrames, App.fpsTime = 0, 0
    end
    if App.flags.hidden then
        for _, object in ipairs(App.hiddenParts) do
            if object.Parent then App.patch("hidden", object, "LocalTransparencyModifier", 1) end
        end
    end
    local now = os.clock()
    if App.flags.esp and now - App.espAt > 0.075 then
        App.espAt = now; App.try("ESP", App.espTick)
    end
end
App.renderBound = pcall(function()
    Run:BindToRenderStep("UwUNCTT_Render_v2", Enum.RenderPriority.Camera.Value + 1, function(dt)
        App.try("Đồ họa client", renderStep, dt)
    end)
end)
if not App.renderBound then App.bind(Run.RenderStepped, function(dt) App.try("Đồ họa client", renderStep, dt) end) end
App.bind(Run.Heartbeat, function(dt)
    if not App.alive then return end
    local now = os.clock()
    App.try("Nhả input", App.inputTick, now)
    local suspended = not App.focused or GuiService.MenuIsOpen
    if suspended and not App.suspended then App.pauseControls("Đang dùng menu Roblox hoặc mất focus.") end
    App.suspended = suspended
    if not suspended then
        local followOk, followError = App.try("Bám mục tiêu", App.followTick, now)
        if not followOk and App.flags.farm then App.stopFarm("Lỗi bám mục tiêu: " .. tostring(followError):sub(1, 140), true) end
        local moveOk, moveError = App.try("Di chuyển client", App.movementTick, dt, now)
        if not moveOk and App.flags.farm then App.stopFarm("Lỗi di chuyển: " .. tostring(moveError):sub(1, 140), true) end
    end
    if now - App.logicAt >= 0.04 then
        App.logicAt = now
        if not suspended then
            if now - (App.lastReactionScan or -math.huge) >= 0.15 then
                App.lastReactionScan = now; App.try("Counter / Block", App.reactionTick, now)
            end
            local combatOk, combatError = App.try("Combat", App.combatTick, now)
            if not combatOk and App.flags.farm then App.stopFarm("Lỗi combat: " .. tostring(combatError):sub(1, 140), true) end
        end
        local target = App.current and Players:GetPlayerByUserId(App.current)
        App.status.Text = string.format("%d FPS · %s · %s", App.fps, App.isMobile() and "MOBILE" or "PC", App.flags.farm and App.farmPhase or "FARM / BAY trên thanh nổi")
    end
    App.try("Tối ưu đồ họa", App.workQueue)
end)
watchCamera(); App.updateRoster(); App.refreshBindings(); App.refresh(); App.applyTheme(); App.showMenu(false)
task.spawn(App.loadWallpaper)
App.notify("UwUNCTT 2.2 · nctt", "MENU: cài đặt · FARM: chạy · BAY: lên/xuống. Kéo ⋮⋮ để đổi chỗ.")
