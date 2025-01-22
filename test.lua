-- !strict
route("/", function(req, res)
    local x = "world"
    
    -- Create response body
    local response_body = "hello, " .. x .. ", you called from " .. req.path .. ", status: " .. res.status .. ", method: " ..
    req.method .. ", protocol: " .. req.protocol
    
    -- Add body if method is POST
    if req.method == "POST" then
        response_body = response_body .. ", body: " .. req.body
    end

    -- Set status so we can test if it works!
    res.status = 299

    return response_body
    
end)

route("/battery-level", function(req, res)
    local level = getBatteryLevel()
    if level then
        return "Battery level: " .. level .. "%"
    else
        return "Could not get battery level :("
    end
end)

