
local qcloud    = require "resty.qcloud"
local lz4       = require "resty.lz4"
local pb        = require "pb"
local protoc    = require "protoc"

local __ = { _VERSION = '23.11.18' }
------------------------------------------------------

-- LZ4 Extremely Fast Compression algorithm
-- https://github.com/lz4/lz4

-- LZ4 library for LuaJIT (FFI Binding)
-- https://github.com/CheyiLin/ljlz4
-- https://github.com/killsen/lua-resty-lz4

-- LZ4 fast compression algorithm binding for Lua
-- https://github.com/witchu/lua-lz4

-- A Lua module to work with Google protobuf
-- https://github.com/starwing/lua-protobuf

-- 在Lua中操作Google protobuf格式数据
-- https://github.com/starwing/lua-protobuf/blob/master/README.zh.md

-- 载入 schema
protoc:load [[
package cls;

message Log
{
    message Content
    {
        required string key   = 1; // 每组字段的 key
        required string value = 2; // 每组字段的 value
    }
    required int64   time     = 1; // 时间戳，UNIX时间格式
    repeated Content contents = 2; // 一条日志里的多个kv组合
}

message LogTag
{
    required string key       = 1;
    required string value     = 2;
}

message LogGroup
{
    repeated Log    logs        = 1; // 多条日志合成的日志数组
    optional string contextFlow = 2; // 目前暂无效用
    optional string filename    = 3; // 日志文件名
    optional string source      = 4; // 日志来源，一般使用机器IP
    repeated LogTag logTags     = 5;
}

message LogGroupList
{
    repeated LogGroup logGroupList = 1; // 日志组列表
}
]]

__.types = {
    Content = {
        key     = "string       //每组字段的 key",
        value   = "string     ? //每组字段的 value",
    },
    Log = {
        time    = "number       //时间戳: UNIX时间格式",
        contents= "@Content[]   //一条日志里的多个kv组合",
    },
    LogTag = {
        key     = "string       //日志标签 key",
        value   = "string    ?  //日志标签 value",
    }
}

__.UploadLog__ = {
    "上传日志",  -- https://cloud.tencent.com/document/product/614/59470
    req = {
        secret_id   = "string       //密钥ID",
        secret_key  = "string       //密钥Key",
        region      = "string       //日志区域",
        topic       = "string       //日志主题",
        logs        = "@Log[]       //日志数组",
        tags        = "@LogTag[] ?  //日志标签组",
        filename    = "string    ?  //日志文件名",
        source      = "string    ?  //日志来源: 一般使用机器IP",
    },
    res = "table",
}
__.UploadLog = function(t)

    local data = {
        logGroupList = {
            {
                logs        = t.logs,
                filename    = t.filename,
                source      = t.source,
                logTags     = t.tags or {},
            },
        }
    }

    local payload = pb.encode("cls.LogGroupList", data)

    payload = lz4.compress(payload)

    return qcloud.http.post {
        secret_id   = t.secret_id,
        secret_key  = t.secret_key,
        service     = "cls",
        version     = "2020-10-16",
        action      = "UploadLog",
        region      = t.region,
        payload     = payload,
        content_type = "application/octet-stream",
        headers = {
            ["X-CLS-TopicId"     ] = t.topic,
            ["X-CLS-CompressType"] = "lz4",
        },
    }

end

--------------------------------------------------------------------------------
return __
