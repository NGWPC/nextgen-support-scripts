# Login the testbed cluster and start a desktop

`https://cloud.nextgenwaterprediction.com/clusters/Zhengtao.Cui/opertestbed`

# Clone `nwm-automation-scripts`

Open a terminal and clone the `add_NCO_realtime_scripts` branch

  `git clone -b add_NCO_realtime_scripts  https://github.com/NGWPC/nwm-automation-scripts/tree/add_NCO_realtime_scripts`

# Run the installation script

```
cd nwm-automation-scripts
./install_testbed.sh
```

# Start EcFlow UI

```
/contrib/software/ecflow/5.6.0/bin/ecflow_ui &

```

# Connect to EcFlow server

1. From the menu, select "Servers" -> "Manage Servers ...", then "Add Server". 
2. Name anything you want for the server name, such as 'testserver'
3. Hostname is 'localhost'.
4. Port is "3141'.
