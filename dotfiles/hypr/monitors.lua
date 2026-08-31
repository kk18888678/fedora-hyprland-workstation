-- Default monitor configuration.
--
-- Use the preferred mode reported by the display and let Hyprland
-- determine its position automatically.
--
-- This generic configuration works as the VM baseline.
-- Physical workstation monitor configuration can be added after
-- the first bare-metal Hyprland installation.

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = "1",
})
