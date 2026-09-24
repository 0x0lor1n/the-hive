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

-- Linear-RGB blend + HSLuv lightness lerp: the math hl_overrides was tuned
-- against. kanagawa's lib.color blends in sqrt-RGB with the ratio reversed.
local function channels(hex)
  local r, g, b = hex:lower():match "^#(%x%x)(%x%x)(%x%x)$"
  assert(r, "invalid hex: " .. tostring(hex))
  return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
end

---@param alpha number 0 = bg, 1 = fg
M.blend = function(fg, bg, alpha)
  local f, b = channels(fg), channels(bg)
  local out = {}
  for i = 1, 3 do
    local v = alpha * f[i] + (1 - alpha) * b[i]
    out[i] = math.floor(math.min(math.max(0, v), 255) + 0.5)
  end
  return string.format("#%02X%02X%02X", out[1], out[2], out[3])
end

M.darken = function(hex, amount, bg)
  return M.blend(hex, bg or "#000000", math.abs(amount))
end

M.brighten = function(hex, percentage)
  local hsluv = require "kanagawa.lib.hsluv"
  local hsl = hsluv.hex_to_hsluv(hex)
  local space = percentage < 0 and hsl[3] or 100 - hsl[3]
  hsl[3] = hsl[3] + space * percentage
  return hsluv.hsluv_to_hex(hsl)
end

return M
