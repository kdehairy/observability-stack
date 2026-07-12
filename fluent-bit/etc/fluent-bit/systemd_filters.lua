function ident_fix(tag, timestamp, record)
    local ident = record["ident"]
    if ident then
        record["ident"] = ident:gsub("^systemd%.", "")
    end
    return 1, timestamp, record
end
