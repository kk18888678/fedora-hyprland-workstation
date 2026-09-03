-- Default monitor configuration.
--
-- Use the preferred mode reported by the display and let Hyprland
-- determine its position automatically.
--
-- For virtual machine environments (e.g. QEMU / KVM virtio-gpu), targeted
-- monitor description matching ensures seamless resolution adaptation
-- without hardcoding any display port names or fixed pixel geometries.
--
-- Physical workstation monitor configuration remains generic, safe,
-- and dynamically adaptable.

hl.monitor({
    output = "desc:Red Hat Inc. QEMU Monitor",
    mode = "preferred",
    position = "auto",
    scale = "1",
})

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = "1",
})
