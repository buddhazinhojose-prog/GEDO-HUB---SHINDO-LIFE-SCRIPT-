
--========================================================
-- GEDO HUB V2.0
-- ZYON CORE V5.10
-- Standalone Lua / Luau implementation
--========================================================

local GEDO = {
    Name = "GEDO HUB",
    Version = "2.0.0",
    Running = true,
    Config = {
        Theme = "Dark",
        StorageFile = "GEDO_HUB_V2.json",
        AutoSave = true,
        Pastebin = {
            APIKey = "",
            UserKey = "",
            Expiration = "1D",
            Visibility = "1"
        }
    }
}

--========================================================
-- 01. RUNTIME CAPABILITIES
--========================================================

local Services = {}

if game and game.GetService then
    local success, result = pcall(function()
        return {
            Players = game:GetService("Players"),
            HttpService = game:GetService("HttpService"),
            UserInputService = game:GetService("UserInputService"),
            TweenService = game:GetService("TweenService")
        }
    end)

    if success then
        Services = result
    end
end

local function notify(message)
    print("[GEDO HUB] " .. tostring(message))
end

--========================================================
-- 02. DEFAULT DATABASE
--========================================================

GEDO.Data = {
    CurrentMap = "Manual",

    Maps = {
        {
            Name = "Manual",
            Region = "Unspecified",
            Notes = "Default map profile",
            Targets = {}
        }
    },

    Targets = {
        Mobs = {},
        Bosses = {},
        Bijuu = {},
        Creatures = {}
    },

    Collection = {
        Stages = {
            {Name = "Preparation", Complete = false},
            {Name = "Exploration", Complete = false},
            {Name = "Collection", Complete = false},
            {Name = "Verification", Complete = false},
            {Name = "Completion", Complete = false}
        }
    },

    Spins = {
        Current = 0,
        History = {}
    },

    Codes = {},
    Settings = {
        Notifications = true,
        AutoSave = true
    }
}

--========================================================
-- 03. STORAGE ENGINE
--========================================================

GEDO.Storage = {}

local function getFileAPI()
    return {
        Read = type(readfile) == "function" and readfile or nil,
        Write = type(writefile) == "function" and writefile or nil,
        Exists = type(isfile) == "function" and isfile or nil
    }
end

function GEDO.Storage:Save()
    if not Services.HttpService then
        return false, "JSON service unavailable"
    end

    local ok, json = pcall(function()
        return Services.HttpService:JSONEncode(GEDO.Data)
    end)

    if not ok then
        return false, tostring(json)
    end

    local api = getFileAPI()

    if api.Write then
        local success, err = pcall(function()
            api.Write(GEDO.Config.StorageFile, json)
        end)

        if success then
            return true, "Saved to local file"
        end

        return false, tostring(err)
    end

    GEDO.Storage.LastBackup = json
    return true, "Saved in current session memory"
end

function GEDO.Storage:Load()
    local api = getFileAPI()

    if not api.Read then
        return false, "Persistent file access unavailable"
    end

    if api.Exists then
        local ok, exists = pcall(
            api.Exists,
            GEDO.Config.StorageFile
        )

        if not ok or not exists then
            return false, "No saved database"
        end
    end

    local ok, contents = pcall(
        api.Read,
        GEDO.Config.StorageFile
    )

    if not ok then
        return false, tostring(contents)
    end

    local decoded, result = pcall(function()
        return Services.HttpService:JSONDecode(contents)
    end)

    if not decoded or type(result) ~= "table" then
        return false, "Invalid database"
    end

    GEDO.Data = result
    return true, "Database loaded"
end

--========================================================
-- 04. MAP PROFILE ENGINE
--========================================================

GEDO.MapManager = {}

function GEDO.MapManager:Add(name, region, notes)
    if type(name) ~= "string" or name == "" then
        return false, "Invalid map name"
    end

    for _, map in ipairs(GEDO.Data.Maps) do
        if map.Name:lower() == name:lower() then
            return false, "Map already exists"
        end
    end

    table.insert(GEDO.Data.Maps, {
        Name = name,
        Region = region or "Unspecified",
        Notes = notes or "",
        Targets = {}
    })

    GEDO.Storage:Save()
    return true
end

function GEDO.MapManager:Select(name)
    for _, map in ipairs(GEDO.Data.Maps) do
        if map.Name == name then
            GEDO.Data.CurrentMap = name
            GEDO.Storage:Save()
            return true
        end
    end

    return false, "Map profile not found"
end

function GEDO.MapManager:Remove(name)
    if name == "Manual" then
        return false, "Default profile cannot be removed"
    end

    for index, map in ipairs(GEDO.Data.Maps) do
        if map.Name == name then
            table.remove(GEDO.Data.Maps, index)

            if GEDO.Data.CurrentMap == name then
                GEDO.Data.CurrentMap = "Manual"
            end

            GEDO.Storage:Save()
            return true
        end
    end

    return false, "Profile not found"
end

function GEDO.MapManager:GetCurrent()
    for _, map in ipairs(GEDO.Data.Maps) do
        if map.Name == GEDO.Data.CurrentMap then
            return map
        end
    end
end

--========================================================
-- 05. TARGET TRACKING ENGINE
--========================================================

GEDO.TargetManager = {}

local Categories = {
    "Mobs",
    "Bosses",
    "Bijuu",
    "Creatures"
}

function GEDO.TargetManager:Add(category, name, notes)
    if not GEDO.Data.Targets[category] then
        return false, "Invalid category"
    end

    if type(name) ~= "string" or name == "" then
        return false, "Target name required"
    end

    table.insert(GEDO.Data.Targets[category], {
        Name = name,
        Notes = notes or "",
        Observed = false,
        Timestamp = os.time()
    })

    GEDO.Storage:Save()
    return true
end

function GEDO.TargetManager:Mark(category, index)
    local list = GEDO.Data.Targets[category]
    local target = list and list[index]

    if not target then
        return false
    end

    target.Observed = not target.Observed
    GEDO.Storage:Save()

    return true
end

function GEDO.TargetManager:Remove(category, index)
    local list = GEDO.Data.Targets[category]

    if not list or not list[index] then
        return false
    end

    table.remove(list, index)
    GEDO.Storage:Save()

    return true
end

--========================================================
-- 06. COLLECTION ENGINE
--========================================================

GEDO.Collection = {}

function GEDO.Collection:Toggle(index)
    local stage = GEDO.Data.Collection.Stages[index]

    if not stage then
        return false
    end

    stage.Complete = not stage.Complete
    GEDO.Storage:Save()

    return true
end

function GEDO.Collection:Progress()
    local completed = 0
    local total = #GEDO.Data.Collection.Stages

    for _, stage in ipairs(GEDO.Data.Collection.Stages) do
        if stage.Complete then
            completed = completed + 1
        end
    end

    return completed, total
end

--========================================================
-- 07. SPIN MANAGER
--========================================================

GEDO.SpinManager = {}

function GEDO.SpinManager:Update(amount)
    amount = tonumber(amount)

    if not amount or amount < 0 then
        return false
    end

    GEDO.Data.Spins.Current = amount

    table.insert(GEDO.Data.Spins.History, {
        Amount = amount,
        Timestamp = os.time()
    })

    GEDO.Storage:Save()
    return true
end

--========================================================
-- 08. CODE MANAGER
--========================================================

GEDO.CodeManager = {}

function GEDO.CodeManager:Add(code)
    if type(code) ~= "string" or code == "" then
        return false
    end

    table.insert(GEDO.Data.Codes, {
        Code = code,
        Redeemed = false,
        Added = os.time()
    })

    GEDO.Storage:Save()
    return true
end

function GEDO.CodeManager:Toggle(index)
    local entry = GEDO.Data.Codes[index]

    if not entry then
        return false
    end

    entry.Redeemed = not entry.Redeemed
    GEDO.Storage:Save()

    return true
end

--========================================================
-- 09. PASTEBIN HTTPS ENGINE
--========================================================

GEDO.Cloud = {}

local function encodeForm(data)
    local HttpService = Services.HttpService

    local parts = {}

    for key, value in pairs(data) do
        table.insert(
            parts,
            HttpService:UrlEncode(tostring(key))
            .. "=" ..
            HttpService:UrlEncode(tostring(value))
        )
    end

    table.sort(parts)

    return table.concat(parts, "&")
end

local function getRequestAdapter()
    if type(request) == "function" then
        return request
    end

    if type(http_request) == "function" then
        return http_request
    end

    if type(syn) == "table"
        and type(syn.request) == "function" then
        return syn.request
    end

    if type(http) == "table"
        and type(http.request) == "function" then
        return http.request
    end

    return nil
end

function GEDO.Cloud:Configure(apiKey, userKey)
    GEDO.Config.Pastebin.APIKey = apiKey or ""
    GEDO.Config.Pastebin.UserKey = userKey or ""
end

function GEDO.Cloud:Backup()
    local config = GEDO.Config.Pastebin

    if config.APIKey == "" then
        return false, "Pastebin developer key missing"
    end

    if not Services.HttpService then
        return false, "HTTP service unavailable"
    end

    local adapter = getRequestAdapter()

    if not adapter then
        return false, "No compatible HTTPS request adapter"
    end

    local success, json = pcall(function()
        return Services.HttpService:JSONEncode(GEDO.Data)
    end)

    if not success then
        return false, "JSON encoding failed"
    end

    local body = encodeForm({
        api_dev_key = config.APIKey,
        api_user_key = config.UserKey,
        api_option = "paste",
        api_paste_code = json,
        api_paste_name = "GEDO HUB V2 Backup",
        api_paste_private = config.Visibility,
        api_paste_expire_date = config.Expiration
    })

    local ok, response = pcall(function()
        return adapter({
            Url = "https://pastebin.com/api/api_post.php",
            Method = "POST",
            Headers = {
                ["Content-Type"] =
                    "application/x-www-form-urlencoded"
            },
            Body = body
        })
    end)

    if not ok then
        return false, tostring(response)
    end

    if type(response) ~= "table" then
        return false, "Unexpected HTTP response"
    end

    local status = response.StatusCode or response.Status

    if tonumber(status) ~= 200 then
        return false, "Pastebin HTTP status: " .. tostring(status)
    end

    local result = tostring(response.Body or "")

    if result:find("Bad API request", 1, true) then
        return false, result
    end

    if not result:match("^https?://") then
        return false, "Pastebin rejected or returned an unexpected response: " .. result
    end

    self.LastURL = result
    return true, result
end

--========================================================
-- 10. GUI ENGINE
--========================================================

GEDO.UI = {
    Pages = {},
    Selected = "Dashboard"
}

local COLORS = {
    Background = Color3.fromRGB(16, 18, 27),
    Panel = Color3.fromRGB(25, 29, 42),
    Accent = Color3.fromRGB(65, 145, 255),
    Text = Color3.fromRGB(240, 243, 250),
    Muted = Color3.fromRGB(155, 165, 185),
    Green = Color3.fromRGB(75, 205, 135),
    Red = Color3.fromRGB(235, 90, 100)
}

function GEDO.UI:Create(class, properties, parent)
    local object = Instance.new(class)

    for key, value in pairs(properties or {}) do
        object[key] = value
    end

    object.Parent = parent
    return object
end

function GEDO.UI:Label(parent, text, position, size)
    return self:Create("TextLabel", {
        Position = position,
        Size = size,
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COLORS.Text,
        TextSize = 13,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true
    }, parent)
end

function GEDO.UI:Button(parent, text, position, callback)
    local button = self:Create("TextButton", {
        Position = position,
        Size = UDim2.fromOffset(145, 32),
        BackgroundColor3 = COLORS.Panel,
        Text = text,
        TextColor3 = COLORS.Text,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = true
    }, parent)

    self:Create("UICorner", {
        CornerRadius = UDim.new(0, 6)
    }, button)

    button.Activated:Connect(callback)

    return button
end

function GEDO.UI:Page(name)
    local page = self.Pages[name]

    if page then
        page.Visible = true
    end

    for pageName, object in pairs(self.Pages) do
        if pageName ~= name then
            object.Visible = false
        end
    end

    self.Selected = name
end

function GEDO.UI:Create()
    local player = Services.Players
        and Services.Players.LocalPlayer

    if not player then
        return false, "LocalPlayer unavailable"
    end

    local playerGui = player:WaitForChild("PlayerGui")

    local old = playerGui:FindFirstChild("GEDO_HUB_V2")

    if old then
        old:Destroy()
    end

    local screen = self:Create("ScreenGui", {
        Name = "GEDO_HUB_V2",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    }, playerGui)

    self.Screen = screen

    local main = self:Create("Frame", {
        Name = "Main",
        Size = UDim2.fromOffset(700, 450),
        Position = UDim2.new(0.5, -350, 0.5, -225),
        BackgroundColor3 = COLORS.Background,
        BorderSizePixel = 0,
        Active = true
    }, screen)

    self.Main = main

    self:Create("UICorner", {
        CornerRadius = UDim.new(0, 12)
    }, main)

    -- Draggable title bar
    local top = self:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundColor3 = COLORS.Panel,
        BorderSizePixel = 0
    }, main)

    self:Create("UICorner", {
        CornerRadius = UDim.new(0, 12)
    }, top)

    self:Label(
        top,
        "GEDO HUB  V2.0",
        UDim2.fromOffset(16, 0),
        UDim2.new(0.7, 0, 1, 0)
    )

    local close = self:Button(
        top,
        "CLOSE",
        UDim2.new(1, -85, 0, 8),
        function()
            screen:Destroy()
        end
    )

    close.Size = UDim2.fromOffset(65, 30)

    -- Drag implementation
    local dragging = false
    local dragInput
    local dragStart
    local startPosition

    top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = main.Position
        end
    end)

    top.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    top.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    Services.UserInputService.InputChanged:Connect(function(input)
        if dragging and (
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        ) then
            local delta = input.Position - dragStart

            main.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)

    -- Sidebar
    local sidebar = self:Create("Frame", {
        Position = UDim2.fromOffset(10, 58),
        Size = UDim2.fromOffset(160, 380),
        BackgroundColor3 = COLORS.Panel,
        BorderSizePixel = 0
    }, main)

    self:Create("UICorner", {
        CornerRadius = UDim.new(0, 8)
    }, sidebar)

    -- Content
    local content = self:Create("Frame", {
        Position = UDim2.fromOffset(180, 58),
        Size = UDim2.new(1, -190, 1, -68),
        BackgroundColor3 = COLORS.Panel,
        BorderSizePixel = 0
    }, main)

    self:Create("UICorner", {
        CornerRadius = UDim.new(0, 8)
    }, content)

    local pages = {
        "Dashboard",
        "Maps",
        "Targets",
        "Collection",
        "Spins",
        "Codes",
        "Cloud",
        "Settings"
    }

    for _, name in ipairs(pages) do
        local page = self:Create("ScrollingFrame", {
            Name = name,
            Size = UDim2.new(1, -16, 1, -16),
            Position = UDim2.fromOffset(8, 8),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            CanvasSize = UDim2.fromOffset(0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y
        }, content)

        self.Pages[name] = page

        local button = self:Button(
            sidebar,
            name,
            UDim2.fromOffset(7, 8 + (#self.Pages - 1) * 43),
            function()
                self:Page(name)
            end
        )

        button.Size = UDim2.fromOffset(146, 34)
    end

    self:BuildPages()

    self:Page("Dashboard")

    return true
end

--========================================================
-- 11. GUI PAGE CONTENT
--========================================================

function GEDO.UI:BuildPages()
    local function addLabel(page, text, y)
        return self:Label(
            page,
            text,
            UDim2.fromOffset(12, y),
            UDim2.new(1, -24, 0, 30)
        )
    end

    local function addInput(page, placeholder, y)
        local input = self:Create("TextBox", {
            Position = UDim2.fromOffset(12, y),
            Size = UDim2.new(1, -24, 0, 34),
            BackgroundColor3 = COLORS.Background,
            TextColor3 = COLORS.Text,
            PlaceholderColor3 = COLORS.Muted,
            PlaceholderText = placeholder,
            Text = "",
            TextSize = 12,
            Font = Enum.Font.Gotham,
            ClearTextOnFocus = false
        }, page)

        self:Create("UICorner", {
            CornerRadius = UDim.new(0, 6)
        }, input)

        return input
    end

    local function addButton(page, text, y, callback)
        return self:Button(
            page,
            text,
            UDim2.fromOffset(12, y),
            callback
        )
    end

    -- DASHBOARD
    local p = self.Pages.Dashboard

    addLabel(p, "SYSTEM OVERVIEW", 10)
    addLabel(p, "Version: " .. GEDO.Version, 45)
    addLabel(p, "Current map: " .. GEDO.Data.CurrentMap, 75)

    local done, total = GEDO.Collection:Progress()

    addLabel(
        p,
        "Collection progress: " .. done .. "/" .. total,
        105
    )

    addLabel(p, "Runtime: Lua / Luau", 135)
    addLabel(p, "Cloud: Pastebin adapter configurable", 165)

    addButton(p, "SAVE DATABA