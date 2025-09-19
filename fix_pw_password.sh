
sudo chown "${USER}:pwuser" -R /ngencerf-app/nwm-automation-scripts
sudo chown "${USER}:pwuser" -R /ngencerf-app/ngen
sudo chown "${USER}:pwuser" -R /ngencerf-app/nwm-cal-mgr
sudo chown "${USER}:pwuser" -R /ngencerf-app/ngen-forcing
sudo chown "${USER}:pwuser" -R /ngencerf-app/nwm-fcst-mgr
sudo chown "${USER}:pwuser" -R /ngencerf-app/nwm-verf
sudo chown "${USER}:pwuser" -R /ngencerf-app/ngencerf-server
sudo chown "${USER}:pwuser" -R /ngencerf-app/ngencerf-docker
sudo chown "${USER}:pwuser" -R /ngencerf-app/ngencerf-ui
sudo chown "${USER}:pwuser" -R /ngencerf-app/singularity

git config --global --add safe.directory /ngencerf-app/nwm-automation-scripts
git config --global --add safe.directory /ngencerf-app/ngen
git config --global --add safe.directory /ngencerf-app/nwm-cal-mgr
git config --global --add safe.directory /ngencerf-app/ngen-forcing
git config --global --add safe.directory /ngencerf-app/nwm-fcst-mgr
git config --global --add safe.directory /ngencerf-app/nwmn-verf
git config --global --add safe.directory /ngencerf-app/ngencerf-server
git config --global --add safe.directory /ngencerf-app/ngencerf-docker
git config --global --add safe.directory /ngencerf-app/ngencerf-ui
