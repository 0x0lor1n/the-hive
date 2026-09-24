-- Legacy colour keys (base, mantle, blue, ...) -> kanagawa wave palette names,
-- so the `C.<key>` refs in hl_overrides, ui, editor and bufferline stay as-is.
local M = {}

M.map = {
  base = "sumiInk3",
  mantle = "sumiInk1",
  surface0 = "sumiInk4",
  surface1 = "sumiInk6",
  overlay0 = "fujiGray",
  subtext0 = "oldWhite",
  text = "fujiWhite",
  rosewater = "oldWhite",
  flamingo = "oniViolet2",
  pink = "sakuraPink",
  mauve = "oniViolet",
  red = "waveRed",
  maroon = "peachRed",
  peach = "surimiOrange",
  yellow = "carpYellow",
  green = "springGreen",
  teal = "waveAqua2",
  sky = "springBlue",
  sapphire = "lightBlue",
  blue = "crystalBlue",
  lavender = "springViolet2",
  -- extra keys the old theme's color_overrides added
  dark_purple = "springViolet1",
  sun = "carpYellow",
  vibrant_green = "springGreen",
}

---@param palette? table kanagawa palette; read from the loaded theme if omitted
M.get = function(palette)
  palette = palette or require("kanagawa.colors").setup({ theme = "wave" }).palette
  local C = {}
  for key, name in pairs(M.map) do
    C[key] = palette[name]
  end
  return C
end

return M
