
route("/", function(req, res)
    x = "world"
    return "hello, " .. x
end)

route("/test", function(req, res)
    return "test"
end)

