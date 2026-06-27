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

function error_class(tag, timestamp, record)
    local severity = record["severity"]
    if severity then
				severity = string.lower(severity:gsub('%[', ''):gsub('%]', ''))

        if string.find(severity, '^err') then
            record["level"] = "error"
        elseif string.find(severity, '^warn') then
            record["level"] = "warning"
        elseif string.find(severity, '^notice') then
            record["level"] = "notice"
        elseif string.find(severity, '^info') then
            record["level"] = "info"
        else
            record["level"] = "unknown"
        end
    end
    return 1, timestamp, record
end

function ident_fix(tag, timestamp, record)
	local ident = record["ident"]
	if ident then
		record["ident"] = ident:gsub("^%a+%.%a+%.", "")
	end
	return 1, timestamp, record
end
