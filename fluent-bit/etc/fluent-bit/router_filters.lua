local severity_map = {
    [0] = "emergency",
    [1] = "alert",
    [2] = "critical",
    [3] = "error",
    [4] = "warning",
    [5] = "notice",
    [6] = "info",
    [7] = "debug",
}

function router_level(tag, timestamp, record)
    local pri = tonumber(record["pri"])
    if pri then
        record["level"] = severity_map[pri % 8] or "unknown"
    end
    return 1, timestamp, record
end
