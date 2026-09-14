-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Night light: hyprsunset-solar writes sunrise/sunset profiles into
-- ~/.config/hypr/hyprsunset.conf. The daemon has to stay running for those
-- switches to fire.
o.launch_on_start("hyprsunset")

-- Dictation: voxtype runs as a systemd user service (voxtype.service),
-- not autostarted here. Parakeet int8 transcribes on CPU, so no dGPU
-- pinning or keepalive is needed.
