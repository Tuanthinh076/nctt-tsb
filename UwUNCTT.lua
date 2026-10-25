--[[
UwUNCTT 2.0 | Credits: nctt | Luau client | PC / touch

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
  Chọn người ở tab Combat. Auto M1 / 1–4 chỉ mô phỏng input; server quyết định
  cooldown, đánh trúng, sát thương và kill. Không tự bỏ qua cooldown server.
  Tab Counter ghi các AnimationId quan sát được: chọn đúng chiêu, gán nhóm
  Block / Counter / Ultimate và tên hiển thị. Danh sách ban đầu RỖNG.
  Tab Combat đọc thuộc tính thực của Player/Character. Để mục tiêu bật nộ rồi
  chọn cờ thể hiện trạng thái ĐANG nộ, không chọn chỉ số thanh tích nộ.
  Dữ liệu thiếu mặc định được coi là chưa rõ; không đoán tên thuộc tính TSB.

ĐIỀU KHIỂN
  RightShift: hiện/ẩn menu. F8 hoặc DỪNG: tắt tính năng, khôi phục thay đổi.
  J: lướt tự tạo nếu đã bật. Fly: WASD / joystick, Space / Ctrl, nút LÊN/XUỐNG.
  Mở menu tắt Auto M1 / Auto Skill / Auto Block để tránh bấm nhầm giao diện.
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
    logicAt = 0, groundAt = 0, localAt = 0, espAt = 0, fpsFrames = 0, fpsTime = 0, fps = 0,
    flags = {
        safe = true, anonymous = false, antiVoid = false, hidden = false,
        lock = false, m1 = false, skills = false, switchAwake = false, missingInactive = false,
        block = false, dodge = false, ultDodge = false, loopEmote = true,
        speed = false, fly = false, dash = false, stabilize = false,
        esp = false, boxes = true, tracers = false, chams = true,
        potato = false, bright = false, fragments = false, fpsCap = false,
    },
    values = {
        speed = 28, fly = 48, travel = 85, radius = 18, distance = 4,
        retreat = 30, voidY = -50, m1Gap = 0.36, skillGap = 0.55,
        espDistance = 500, fpsCap = 120, dashLength = 12,
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
function App.press(key, duration, owner)
    if App.inputs[key] then return true end
    if App.focused == false then return false, "Cửa sổ mất focus", false end
    if App.panel and App.panel.Visible then return false, "Menu đang mở", false end
    if Input:GetFocusedTextBox() or GuiService.MenuIsOpen then return false, "Đang dùng giao diện", false end
    local camera = World.CurrentCamera
    if not camera then return false, "Camera chưa sẵn sàng", false end
    local release
    if key == "M1" then
        local viewport, inset = camera.ViewportSize, GuiService:GetGuiInset()
        local x, y = math.floor(viewport.X * 0.5), math.floor(viewport.Y * 0.42 + inset.Y)
        if VIM and not App.rejected.mouse then
            local ok = pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 0) end)
            if ok then release = function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 0) end
            else App.rejected.mouse = true end
        end
        if not release then
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
            if Caps.click and not App.rejected.click then
                local clicked = pcall(Caps.click)
                if clicked then return true else App.rejected.click = true end
            end
            if Caps.down and Caps.up and not App.rejected.mousePair then
                local pressed = pcall(Caps.down)
                if pressed then release = Caps.up
                else pcall(Caps.up); App.rejected.mousePair = true end
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
    if not release then return false, "Môi trường chặn hoặc thiếu API mô phỏng input", true end
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
function App.ground(position)
    local ignore = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then table.insert(ignore, player.Character) end
    end
    if App.effects then table.insert(ignore, App.effects) end
    local parameters = RaycastParams.new()
    parameters.FilterType = Enum.RaycastFilterType.Exclude
    parameters.FilterDescendantsInstances = ignore
    local hit = World:Raycast(position + Vector3.new(0, 18, 0), Vector3.new(0, -100, 0), parameters)
    if not hit or hit.Normal.Y < 0.55 then return nil end
    local _, humanoid, root = App.parts(Me)
    if not humanoid then return nil end
    return hit.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 + 0.3, 0)
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
    local up = (App.upPointer or App.keys[Enum.KeyCode.Space]) and 1 or 0
    local down = (App.downPointer or App.keys[Enum.KeyCode.LeftControl] or App.keys[Enum.KeyCode.RightControl]) and 1 or 0
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
            root.CFrame = root.CFrame:Lerp(goal.cf, alpha)
            root.AssemblyLinearVelocity = Vector3.zero
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
function App.nearest(exclude, requireInactive)
    local _, _, myRoot = App.parts(Me)
    if not myRoot then return nil end
    local best, distance = nil, 1000
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Me and player.UserId ~= exclude then
            local _, _, root = App.parts(player)
            local eligible = not requireInactive or App.awake(player) == false
            if root and eligible then
                local d = (root.Position - myRoot.Position).Magnitude
                if d < distance then best, distance = player, d end
            end
        end
    end
    return best
end
function App.chooseTarget()
    local target
    if App.targetMode == "Gần nhất" then target = App.nearest(nil, App.flags.switchAwake)
    else
        target = App.current and Players:GetPlayerByUserId(App.current) or App.selectedPlayer()
        if not App.parts(target) and App.current ~= App.selected then target = App.selectedPlayer() end
    end
    if not target or not App.parts(target) then return nil end
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
    if App.panel.Visible or now < App.pauseUntil or App.inputs.F then return end
    if not (App.flags.lock or App.flags.m1 or App.flags.skills) then return end
    local _, _, myRoot = App.parts(Me)
    local target = App.chooseTarget()
    local _, _, root = App.parts(target)
    if not myRoot or not root then
        App.releaseAll("combat")
        if App.goal and App.goal.priority == 10 then App.goal = nil end
        return
    end
    if App.flags.lock and not App.flags.fly then
        local ground = App.ground((root.CFrame * CFrame.new(0, 0, App.values.distance)).Position)
        if ground then App.moveTo(App.face(ground, root.Position), 10, 0.5, false) end
    end
    if (root.Position - myRoot.Position).Magnitude > 7 then return end
    if App.flags.m1 and now - App.lastAttack >= math.max(App.values.m1Gap, App.flags.safe and 0.65 or 0.18) then
        App.lastAttack = now
        local ok, reason, fatal = App.press("M1", 0.045, "combat")
        if not ok and fatal then App.flags.m1 = false; App.refresh(); App.notify("Auto M1 đã tắt", reason) end
    end
    if App.flags.skills and now - App.lastSkill >= math.max(App.values.skillGap, App.flags.safe and 1.1 or 0.25) then
        App.lastSkill = now
        local keys = {"One", "Two", "Three", "Four"}
        local ok, reason, fatal = App.press(keys[App.skillIndex], 0.045, "combat")
        App.skillIndex = App.skillIndex % 4 + 1
        if not ok and fatal then App.flags.skills = false; App.refresh(); App.notify("Auto Skill đã tắt", reason) end
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
    App.flags.m1, App.flags.skills, App.flags.block, App.flags.lock = false, false, false, false
    App.releaseAll(); App.goal = nil
    App.refresh()
end
function App.setFlag(key, enabled)
    if not App.alive then return end
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
function App.new(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties or {}) do object[key] = value end
    object.Parent = parent
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
    Size = UDim2.fromOffset(440, 580), AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.bg,
    BorderSizePixel = 0, Active = true, ZIndex = 10,
}, App.gui)
App.round(App.panel, 14)
local border = App.new("UIStroke", {Thickness = 1.4, Color = C.purple, Transparency = 0.2}, App.panel)
App.new("UIGradient", {Color = ColorSequence.new(C.red, C.purple), Rotation = 35}, border)
local header = App.new("Frame", {Size = UDim2.new(1, 0, 0, 66), BackgroundTransparency = 1, Active = true}, App.panel)
App.new("TextLabel", {
    Position = UDim2.fromOffset(16, 9), Size = UDim2.new(1, -190, 0, 27),
    BackgroundTransparency = 1, Text = "UwUNCTT", TextColor3 = C.red,
    Font = Enum.Font.GothamBold, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left,
}, header)
App.new("TextLabel", {
    Position = UDim2.fromOffset(17, 37), Size = UDim2.new(1, -32, 0, 18),
    BackgroundTransparency = 1, Text = "nctt  /  v2.0  /  " .. executor,
    Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Left,
}, header)
local function headerButton(text, x, width, color)
    local button = App.new("TextButton", {
        Position = UDim2.new(1, x, 0, 14), Size = UDim2.fromOffset(width, 30),
        BackgroundColor3 = color or C.row, BorderSizePixel = 0,
        Text = text, TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 12,
    }, header)
    App.round(button, 7); return button
end
local emergency = headerButton("DỪNG", -160, 68, C.red)
local minimize, close = headerButton("—", -84, 32), headerButton("X", -44, 32)
local tabBar = App.new("ScrollingFrame", {
    Position = UDim2.fromOffset(12, 69), Size = UDim2.new(1, -24, 0, 39),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
    ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarImageColor3 = C.purple,
}, App.panel)
App.new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, tabBar)
App.pages, App.tabs = {}, {}
for index, title in ipairs({"Bảo vệ", "Nhân vật", "Combat", "Counter", "Emote", "Di chuyển", "Tối ưu"}) do
    local button = App.new("TextButton", {
        Size = UDim2.fromOffset(100, 33), BackgroundColor3 = index == 1 and C.purple or C.row,
        BorderSizePixel = 0, Text = title, TextColor3 = C.text,
        Font = Enum.Font.GothamMedium, TextSize = 12, LayoutOrder = index,
    }, tabBar)
    App.round(button, 8)
    local page = App.new("ScrollingFrame", {
        Position = UDim2.fromOffset(12, 119), Size = UDim2.new(1, -24, 1, -169),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarImageColor3 = C.purple, Visible = index == 1,
        ScrollingDirection = Enum.ScrollingDirection.Y,
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
    Position = UDim2.new(0, 16, 1, -41), Size = UDim2.new(1, -32, 0, 30),
    BackgroundTransparency = 1, Text = "Tất cả tính năng đang tắt · F8: dừng · RightShift: menu",
    Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.muted, TextWrapped = true,
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
    while #App.toasts >= 3 do local old = table.remove(App.toasts, 1); old:Destroy() end
    local viewport = World.CurrentCamera and World.CurrentCamera.ViewportSize or Vector2.new(400, 700)
    local card = App.new("Frame", {
        Size = UDim2.fromOffset(math.min(345, viewport.X - 24), 78), BackgroundColor3 = C.card,
        BorderSizePixel = 0, BackgroundTransparency = 0.1,
    }, App.toastArea)
    App.round(card, 10)
    App.new("UIStroke", {Color = C.purple, Transparency = 0.35}, card)
    App.new("TextLabel", {Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 19), BackgroundTransparency = 1, Text = title, TextColor3 = C.red, Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left}, card)
    App.new("TextLabel", {Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 38), BackgroundTransparency = 1, Text = message, TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top}, card)
    local progress = App.new("Frame", {Size = UDim2.new(1, -16, 0, 2), Position = UDim2.new(0, 8, 1, -5), BackgroundColor3 = C.purple, BorderSizePixel = 0}, card)
    Tween:Create(progress, TweenInfo.new(4, Enum.EasingStyle.Linear), {Size = UDim2.new(0, 0, 0, 2)}):Play()
    table.insert(App.toasts, card)
    task.delay(4.1, function()
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
        Size = UDim2.new(1, 0, 0, 42), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.card, BorderSizePixel = 0, Text = text, TextWrapped = true,
        Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.muted,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = nextOrder(parent),
    }, parent)
    App.new("UIPadding", {PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10)}, label)
    App.round(label); return label
end
function App.action(parent, text, callback)
    local button = App.new("TextButton", {
        Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = C.row, BorderSizePixel = 0,
        Text = text, TextWrapped = true, TextColor3 = C.text, TextSize = 12,
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
    local frame = App.new("Frame", {Size = UDim2.new(1, 0, 0, 68), BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = nextOrder(parent)}, parent)
    App.round(frame)
    App.new("TextLabel", {Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 20), BackgroundTransparency = 1, Text = title, Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Left}, frame)
    local box = App.new("TextBox", {Position = UDim2.fromOffset(9, 28), Size = UDim2.new(1, -18, 0, 32), BackgroundColor3 = C.row, BorderSizePixel = 0, ClearTextOnFocus = false, Text = initial or "", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.text}, frame)
    App.round(box, 6); return box
end
function App.slider(parent, title, key, low, high, step, callback)
    local frame = App.new("Frame", {Size = UDim2.new(1, 0, 0, 68), BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = nextOrder(parent)}, parent)
    App.round(frame)
    App.new("TextLabel", {Position = UDim2.fromOffset(11, 6), Size = UDim2.new(1, -92, 0, 23), BackgroundTransparency = 1, Text = title, TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left}, frame)
    local box = App.new("TextBox", {Position = UDim2.new(1, -76, 0, 5), Size = UDim2.fromOffset(64, 26), BackgroundColor3 = C.row, BorderSizePixel = 0, ClearTextOnFocus = false, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.red}, frame)
    App.round(box, 6)
    local bar = App.new("Frame", {Position = UDim2.new(0, 13, 0, 46), Size = UDim2.new(1, -26, 0, 8), BackgroundColor3 = C.row, BorderSizePixel = 0, Active = true}, frame)
    App.round(bar, 4)
    local fill = App.new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.purple, BorderSizePixel = 0}, bar)
    App.round(fill, 4)
    local thumb = App.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(17, 17), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = C.red, BorderSizePixel = 0, Active = true}, bar)
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
    bar.InputBegan:Connect(began); thumb.InputBegan:Connect(began)
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

local floating = App.new("TextButton", {Position = UDim2.new(0, 10, 0.4, 0), Size = UDim2.fromOffset(65, 39), BackgroundColor3 = C.purple, BorderSizePixel = 0, Text = "UwU", TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 15, Visible = false, ZIndex = 20}, App.gui)
local floatingStop = App.new("TextButton", {Position = UDim2.new(0, 10, 0.4, 46), Size = UDim2.fromOffset(65, 34), BackgroundColor3 = C.red, BorderSizePixel = 0, Text = "DỪNG", TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 11, Visible = false, ZIndex = 20}, App.gui)
App.round(floating); App.round(floatingStop)
App.flightHud = App.new("Frame", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.45, 0), Size = UDim2.fromOffset(62, 150), BackgroundTransparency = 1, Visible = false, ZIndex = 20}, App.gui)
for index, title in ipairs({"LÊN", "XUỐNG", "LƯỚT"}) do
    local button = App.new("TextButton", {Position = UDim2.fromOffset(0, (index - 1) * 50), Size = UDim2.fromOffset(62, 42), BackgroundColor3 = C.row, BorderSizePixel = 0, Text = title, TextColor3 = C.text, TextSize = 11, Font = Enum.Font.GothamBold}, App.flightHud)
    App.round(button)
    if index == 3 then button.Activated:Connect(function() App.try("Lướt", App.dash) end)
    else
        local up = index == 1
        button.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                if up then App.upPointer = input else App.downPointer = input end
            end
        end)
    end
end
function App.showMenu(visible)
    App.panel.Visible = visible
    floating.Visible, floatingStop.Visible = not visible, not visible
    App.flightHud.Visible = not visible and (App.flags.fly or App.flags.dash)
    if visible then
        if App.goal and App.goal.priority == 10 then App.goal = nil end
        local active = App.flags.m1 or App.flags.skills or App.flags.block
        App.flags.m1, App.flags.skills, App.flags.block = false, false, false
        App.releaseAll()
        if active then App.notify("Mở menu", "Đã tắt input tự động để tránh bấm nhầm.") end
    end
    App.refresh()
end
table.insert(App.refreshers, function() App.flightHud.Visible = not App.panel.Visible and (App.flags.fly or App.flags.dash) end)
floating.Activated:Connect(function() App.showMenu(true) end)
floatingStop.Activated:Connect(function() App.stopAll("Đã tắt và khôi phục thay đổi."); App.showMenu(true) end)
emergency.Activated:Connect(function() App.stopAll("Đã tắt và khôi phục thay đổi.") end)
minimize.Activated:Connect(function() App.showMenu(false) end)
close.Activated:Connect(App.unload)

local protect, characterPage, combatPage, counterPage, emotePage, movePage, optimizePage = table.unpack(App.pages)
App.note(protect, "UwUNCTT · nctt\nMenu client độc lập. Nhận diện API không đồng nghĩa đã kiểm chứng mọi executor. Không có anti-ban tuyệt đối.")
App.toggle(protect, "Safe Mode: chỉ giảm tần suất", "safe")
App.toggle(protect, "Anonymizer: tên giả trong menu / ESP", "anonymous")
App.slider(protect, "Tốc độ nội suy (studs/giây)", "travel", 20, 200, 5)
App.note(protect, "Nội suy không phải Teleport Bypass. pcall chỉ bắt lỗi Lua; không chặn lệnh kick hoặc phát hiện từ máy chủ. Anonymizer chỉ đổi hình ảnh phía bạn.")
App.action(protect, "Xem API đã nhận diện", function()
    local lines = {"Executor: " .. executor, "getgenv: " .. tostring(type(getgenv) == "function"), "gethui: " .. tostring(Caps.gethui ~= nil), "VirtualInputManager: " .. tostring(VIM ~= nil)}
    for _, name in ipairs({"click", "down", "up", "keydown", "keyup", "fpsset", "fpsget", "touch"}) do
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
                App.stopCombat(); App.selected, App.current = candidate.UserId, nil
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
    App.stopCombat(); App.targetMode, App.current = value, nil
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
App.toggle(movePage, "Lướt tự tạo: J / nút LƯỚT", "dash")
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
    local width = math.max(220, math.min(480, viewport.X - 18))
    local height = math.max(240, math.min(620, viewport.Y - top.Y - bottom.Y - 18))
    App.panel.Size = UDim2.fromOffset(width, height)
    local wantedX = recenter and viewport.X / 2 or App.panel.Position.X.Scale * viewport.X + App.panel.Position.X.Offset
    local wantedY = recenter and (viewport.Y + top.Y - bottom.Y) / 2 or App.panel.Position.Y.Scale * viewport.Y + App.panel.Position.Y.Offset
    local x = math.clamp(wantedX, width / 2 + 6, math.max(width / 2 + 6, viewport.X - width / 2 - 6))
    local y = math.clamp(wantedY, top.Y + height / 2 + 6, math.max(top.Y + height / 2 + 6, viewport.Y - bottom.Y - height / 2 - 6))
    App.panel.Position = UDim2.fromOffset(x, y)
end
function App.pauseControls(message)
    local wasActive = App.flags.fly or App.flags.speed or App.flags.lock or App.flags.m1 or App.flags.skills or App.flags.block
    App.stopCombat()
    App.flags.fly, App.flags.speed, App.flags.stabilize = false, false, false
    App.stopFly(); App.restore("speed"); App.restore("stabilize"); App.stopEmote()
    App.keys, App.upPointer, App.downPointer = {}, nil, nil
    App.refresh()
    if wasActive and message then App.notify("Tạm dừng điều khiển", message) end
end
App.focused = true
local drag
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        if input.Position.X > header.AbsolutePosition.X + header.AbsoluteSize.X - 174 then return end
        drag = {input = input, start = input.Position, position = App.panel.Position}
    end
end)
App.bind(Input.InputChanged, function(input)
    local slider = App.sliderDrag
    if slider and (input == slider.input or (slider.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
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
    if App.sliderDrag and input == App.sliderDrag.input then App.sliderDrag = nil end
    if drag and input == drag.input then drag = nil; App.fit(false) end
end)
App.bind(Input.InputBegan, function(input, processed)
    if Input:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.F8 then App.stopAll("Đã dừng và khôi phục."); App.showMenu(true); return end
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
    if not suspended then App.try("Di chuyển client", App.movementTick, dt, now) end
    if now - App.logicAt >= (App.flags.safe and 0.22 or 0.10) then
        App.logicAt = now
        if not suspended then
            App.try("Counter / Block", App.reactionTick, now)
            App.try("Combat", App.combatTick, now)
        end
        local target = App.current and Players:GetPlayerByUserId(App.current)
        App.status.Text = string.format("%d FPS  ·  %s  ·  F8: DỪNG", App.fps, target and App.name(target) or "Chưa có mục tiêu tự động")
    end
    App.try("Tối ưu đồ họa", App.workQueue)
end)
watchCamera(); App.updateRoster(); App.refresh()
App.notify("UwUNCTT · nctt", "Đã mở menu. Tính năng tự động chưa bật. Xem giới hạn trong tab Bảo vệ.")
