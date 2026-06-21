function status_class(tag, timestamp, record)
    local status = record["status"]
    if status then
        local class = math.floor(status / 100)
        record["status_class"] = tostring(class) .. "xx"
        if class >= 5 then
            record["level"] = "error"
        elseif class == 4 then
            record["level"] = "warn"
        else
            record["level"] = "info"
        end
    end
    return 1, timestamp, record
end
