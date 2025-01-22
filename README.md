# ![ludo logo](<ludo logo.png>)

🕸️ an (experimental) Lua runtime aiming at accessing native OS APIs, and of course blazingly fast 🚀!

## Features

- 🚀 Blazingly fast
- 🌐 Web server
- 📚 Lua runtime
- 💻 native OS APIs

## Example usage

```lua
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


```

then do `ludo ./test.lua` to run the server. You'll then be able to query the web server at `http://localhost:5555/` and `http://localhost:5555/battery-level`.

```bash
curl http://localhost:5555/ --data "hi there :)"

curl http://localhost:5555/battery-level
```
