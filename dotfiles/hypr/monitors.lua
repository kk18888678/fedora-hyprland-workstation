-- Default monitor configuration.
--
-- Uses the preferred mode reported by the display at session initialization
-- and lets Hyprland position outputs automatically.
--
-- Note on Virtual Machine displays (e.g. QEMU / KVM virtio-gpu):
-- Virtual displays expose a dynamic DRM mode that reflects the hypervisor
-- viewer window size at compositor startup. Because Hyprland/Aquamarine
-- currently probes modes during initial output enumeration and skips
-- re-probing connected connectors on later DRM hotplug uevents, automatic
-- post-enumeration live window resizing cannot be guaranteed purely via
-- declarative monitor configuration without an upstream backend extension.
-- Users wishing to change virtual display resolution should set the desired
-- viewer window size prior to compositor launch or configure a discrete mode.

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = "1",
})

