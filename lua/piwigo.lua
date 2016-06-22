--[[
    Piwigo module definition
    
]]
-- see http://w3.impa.br/~diego/software/luasocket/http.html
local http = require "socket.http"
local ltn12 = require "ltn12"
local cjson = require "cjson"


Piwigo = {}
Piwigo.__index = Piwigo

function Piwigo.create(url)
    local pwg = {}
    setmetatable(pwg, Piwigo)
    pwg.url = url
    return pwg
end

local function printResponseInfos(method, status, headers)
    print("Failed to execute method ["..method.."], HTTP status = "..status)
    for k, v in pairs(headers) do
        print("\t"..k.." = "..v)
    end
end

local uri_prefix = "/ws.php?format=json"

function Piwigo:login(username, password)
    local credentials = "username="..username.."&password="..password.."&method=pwg.session.login"
    local _, status, headers = http.request {
        url = self.url..uri_prefix.."&method=pwg.session.login",
        method = "POST",
        source = ltn12.source.string(credentials),
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Content-length"] = #credentials,
            ["Referer"] = self.url.."/tools/ws.htm",
            ["Connection"] = "keep-alive"
        }
    }
    print("Login status = "..status)
    if status == 200 then
        -- Parse set-cookie header value in way to extract piwigo cookie
        self.cookie =  headers["set-cookie"]:match("pwg_id=(%w+);.+")
        local sessionStatus = self:getSessionStatus()
        self.pwg_token = sessionStatus.pwg_token 
        self.username = sessionStatus.username
        self.status = sessionStatus.status       
        return true    
    else
        return false
    end 
end

function Piwigo:logout()
    local _, status, headers = http.request {
        url = self.url..uri_prefix.."&method=reflection.getMethodDetails&methodName=pwg.session.logout",
        headers = {
            ["Cookie"] = "pwg_id="..self.cookie,
            ["Referer"] = self.url.."/tools/ws.htm",
            ["Connection"] = "close"
        } 
    }
    print("logout status = "..status)    
end


function Piwigo:getSessionStatus()
    local buf = {}
    local _, status, headers = http.request {
        url = self.url..uri_prefix.."&method=pwg.session.getStatus",
        headers = {
            ["Cookie"] = "pwg_display_thumbnail=no_display_thumbnail; pwg_id="..self.cookie,
            ["Referer"] = self.url.."/tools/ws.htm",
            ["Connection"] = "keep-alive"
        },
        sink = ltn12.sink.table(buf)
        --sink = ltn12.sink.file(io.stdout) 
    }
    if status == 200 then 
        local json = cjson.decode(table.concat(buf))
        return json.result
    else
        printResponseInfos("pwg.session.getStatus", status, headers)
        return {}
    end
end

function Piwigo:getInfos()
    local buf, result = {}, {}
    local _, status, headers = http.request {
        url = self.url..uri_prefix.."&method=pwg.getInfos",
        headers = {
            ["Cookie"] = "pwg_display_thumbnail=no_display_thumbnail; pwg_id="..self.cookie,
            ["Referer"] = self.url.."/tools/ws.htm",
            ["Connection"] = "keep-alive"
        },
        sink = ltn12.sink.table(buf)
        --sink = ltn12.sink.file(io.stdout) 
    }
    if status == 200 then 
        local json = cjson.decode(table.concat(buf))
        for i, v in ipairs(json.result.infos) do
            print(v.name)
            result[i] = v.name
        end
    else
        printResponseInfos("pwg.getInfos", status, headers)
    end
    return result
end


function Piwigo:getCategoriesList()
    local buf, result = {}, {}
    local _, status, headers = http.request {
        url = self.url..uri_prefix.."&method=pwg.categories.getList&recursive=true&fullname=true",
        headers = {
            ["Cookie"] = "pwg_id="..self.cookie,
            ["Referer"] = self.url.."/tools/ws.htm",
            ["Connection"] = "keep-alive"
        },
        sink = ltn12.sink.table(buf)
        --sink = ltn12.sink.file(io.stdout) 
    }
    if status == 200 then 
        local json = cjson.decode(table.concat(buf))
        for i, v in ipairs(json.result.categories) do
            result[i] = { name = v.name, id = v.id }
        end
        
    end
    return result
end

function Piwigo:upload(imagePath, categoryId)
    -- see http://piwigo.org/doc/doku.php?id=dev:webapi:pwg.images.upload
    -- http://stackoverflow.com/questions/12202301/upload-file-to-a-server-using-lua
    -- https://github.com/catwell/lua-multipart-post
    -- http://www.capgo.com/Resources/SoftwareDev/LuaSocketShortRef20.pdf
    local data = "image="..imagePath.."&category="..categoryId.."&pwg_token"..self.pwg_token
    local image = io.open(imagePath) 
    local buf = {}
    
    local _, status, headers = http.request {
        url = self.url..uri_prefix.."&method=pwg.images.upload",
        method = "POST",
        source = ltn12.source.cat(ltn12.source.string(data), ltn12.source.file(image)),
        headers = {
            ["Content-Type"] = "multipart/form-data",
            ["Referer"] = self.url.."/tools/ws.htm",
            ["Connection"] = "keep-alive",
            ["Cookie"] = "pwg_id="..self.cookie
        },
        sink = ltn12.sink.table(buf) 
    }
    image:close()
    print("Upload status = "..status)
    print("response = "..table.concat(buf))
  --  printResponseInfos("pwg.images.upload", status, headers)
end


return Piwigo