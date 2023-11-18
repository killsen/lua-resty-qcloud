
local cjson     = require "cjson.safe"
local hmac      = require "resty.hmac"
local sha256    = require "resty.sha256"
local http      = require "resty.http"
local _tohex    = require "resty.string".to_hex
local _concat   = table.concat

local __ = { _VERSION = '23.11.16' }
------------------------------------------------------

local function hex_sha256(data)
-- @data    : string
-- @return  : string

    local sha = sha256.new()
    sha:update(data)
    return _tohex(sha:final())
end

local function hmac_sha256(key, data)
-- @key     : string
-- @data    : string
-- @return  : string

    local sha = hmac:new(key, hmac.ALGOS.SHA256)
    sha:update(data)
    return sha:final()
end

local function hex_hmac_sha256(key, data)
-- @key     : string
-- @data    : string
-- @return  : string

    local bin = hmac_sha256(key, data)
    return _tohex(bin)
end


__.post__ = {
    "POST请求",
    req = {
        secret_id       = "string   //密钥ID",
        secret_key      = "string   //密钥Key",
        headers         = "map<string> ? //请求标头",
        service         = "string   //服务名称",
        version         = "string   //服务版本",
        action          = "string   //接口名称",
        region          = "string   //地域名称",
        language        = "string ? //语言: 默认 zh-CN",
        content_type    = "string ? //内容类型: 默认 application/json",
        payload         = "string ? //请求数据",
    },
    res = "any"
}
__.post = function(req)

    local secret_id     = req.secret_id
    local secret_key    = req.secret_key

    local algorithm     = "TC3-HMAC-SHA256"  -- 签名算法
    local service       = req.service
    local version       = req.version
    local action        = req.action
    local region        = req.region
    local language      = req.language or "zh-CN"
    local content_type  = req.content_type or "application/json"
    local timestamp     = ngx.time()
    local date          = os.date("!%Y-%m-%d", timestamp)  -- 日期以协调世界时格式化

    local host          = service .. "." .. region .. ".tencentcloudapi.com"
    local uri           = "/"
    local query         = ""
    local url           = "https://" .. host .. uri
    local method        = "POST"
    local payload       = req.payload or ""

    local headers = {}

    if type(req.headers) == "table" then
        for k, v in pairs(req.headers) do
            headers[k] = v
        end
    end

    -- 参与签名的头部信息
    headers["Content-Type"  ] = content_type
    headers["Host"          ] = host

    local signed_headers    = "content-type;host"
    local canonical_headers = "content-type:" .. content_type .. "\n" ..
                              "host:" .. host .. "\n"

    -- 公共参数
    -- https://cloud.tencent.com/document/product/614/56474
    headers["X-TC-Action"   ] = action
    headers["X-TC-Timestamp"] = timestamp
    headers["X-TC-Version"  ] = version
    headers["X-TC-Region"   ] = region
    headers["X-TC-Language" ] = language

    -- 签名方法 v3
    -- https://cloud.tencent.com/document/api/614/56475
    -- https://github.com/TencentCloud/signature-process-demo/blob/main/signature-v3/lua/signv3.lua

    -- 1. 拼接规范请求串
    local canonical_request = _concat({
        method,
        uri,
        query,
        canonical_headers,
        signed_headers,
        hex_sha256(payload),
    }, "\n")

    -- ngx.say(canonical_request)
    -- ngx.say "------------------------------"

    local credential_scope = date .. "/" .. service .. "/tc3_request"

    -- 2. 拼接待签名字符串
    local string_to_sign = _concat({
        algorithm,
        timestamp,
        credential_scope,
        hex_sha256(canonical_request),
    }, "\n")

    -- ngx.say(string_to_sign)
    -- ngx.say "------------------------------"

    -- 3. 计算签名
    -- 1）计算派生签名密钥: 二进制的数据
    local secret_date    = hmac_sha256("TC3" .. secret_key, date)
    local secret_service = hmac_sha256(secret_date, service)
    local secret_signing = hmac_sha256(secret_service, "tc3_request")
    -- 2）计算签名
    local signature = hex_hmac_sha256(secret_signing, string_to_sign)

    -- ngx.say(signature)
    -- ngx.say "------------------------------"

    -- 4. 拼接 Authorization
    local authorization = _concat({
        algorithm       , " ",
        "Credential"    , "=", secret_id, "/", credential_scope, ", ",
        "SignedHeaders" , "=", signed_headers, ", ",
        "Signature"     , "=", signature,
    }, "")

    -- ngx.say(authorization)
    -- ngx.say "------------------------------"

    headers["Authorization"] = authorization

    local httpc = http.new()

    local res, err = httpc:request_uri(url, {
        method  = method,
        query   = query,
        headers = headers,
        body    = payload,
    })
    if not res then return nil, err end

    -- ngx.say(res.status)
    -- ngx.say(res.body)

    local obj

    obj = cjson.decode(res.body)
    if type(obj) ~= "table" then return nil, "response decode fail" end

    obj = obj["Response"]
    if type(obj) ~= "table" then return nil, "response not found" end

    -- 返回结果中如果存在 Error 字段，则表示调用 API 接口失败
    -- https://cloud.tencent.com/document/product/614/56477

    local error = obj["Error"]
    if type(error) == "table" then
        local err = error["Message"] or "unknown error"
        return nil, err
    end

    return obj

end

-- 测试
__._TESTING = function()

    -- 安全提示
    -- 您的 API 密钥代表您的账号身份和所拥有的权限，使用腾讯云 API 可以操作您名下的所有腾讯云资源。
    -- 为了您的财产和服务安全，请妥善保存和定期更换密钥，请勿通过任何方式（如 GitHub）上传或者分享您的密钥信息。建议您参照安全设置策略
    -- https://console.cloud.tencent.com/cam/capi

    local res, err = __.post {
        secret_id   = os.getenv("QCLOUD_SECRET_ID"),
        secret_key  = os.getenv("QCLOUD_SECRET_KEY"),
        service     = "cls",
        version     = "2020-10-16",
        action      = "DescribeTopics",
        region      = "ap-shanghai",
        payload     = "{}",
    }

    return res or err

end

--------------------------------------------------------------------------------
return __
