--!strict

route("/", function(req, res)
    local x = "world"
    return "hello, " .. x .. req
end)

route("/test", function(req, res)
    return "test"
end)

