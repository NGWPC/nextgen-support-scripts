# Login the testbed cluster and start a desktop

`https://cloud.nextgenwaterprediction.com/clusters/Zhengtao.Cui/opertestbed`

# Clone `nwm-automation-scripts`

Open a terminal and clone the `add_NCO_realtime_scripts` branch.

  `git clone -b add_NCO_realtime_scripts  https://github.com/NGWPC/nwm-automation-scripts/tree/add_NCO_realtime_scripts`

# Run the installation script

```
cd nwm-automation-scripts/nwm.v4.0.0
./install_testbed.sh
```
This will start a EcFlow server on the default port (3141) and install the EcFlow/NCO scripts for NWM.  The script also accept a port number as an argument. You can choose an unused port number if the default port number has already been used, 

```
cd nwm-automation-scripts/nwm.v4.0.0
./install_testbed.sh 3500
```

# Start EcFlow UI

```
/contrib/software/ecflow/5.6.0/bin/ecflow_ui &

```

# Connect to EcFlow server

1. From the menu, select "Servers" -> "Manage Servers ...", then "Add Server". 
2. Name anything you want for the server name, such as 'testserver'.
3. Hostname is 'localhost'.
4. Port is '3141' or the port number you selected during installation.
