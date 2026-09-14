local M = {}

M.hex_to_rgb = function(hex)
  hex = hex:gsub("^#", "")

  if not hex:match "^%x%x%x%x%x%x$" then
    return nil
  end

  local r = tonumber(hex:sub(1, 2), 16)
  local g = tonumber(hex:sub(3, 4), 16)
  local b = tonumber(hex:sub(5, 6), 16)

  return string.format("rgb(%d, %d, %d)", r, g, b)
end

M.rgb_to_hex = function(rgb)
  local r, g, b = rgb:match "rgb%((%d+),%s*(%d+),%s*(%d+)%)"

  if not (r and g and b) then
    return nil
  end

  r, g, b = tonumber(r), tonumber(g), tonumber(b)

  if r < 0 or r > 255 or g < 0 or g > 255 or b < 0 or b > 255 then
    return nil
  end

  return string.format("#%02X%02X%02X", r, g, b)
end

return M
