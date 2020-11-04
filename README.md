# healthchecks_service_ps

Powershell script to install a service to check in with healthchecks once a minute on Windows.


Created by:    Bo Saurage
Created on:    2020-11-03
Filename:      healthchecks_service.ps1
Organization:  

Downloads NSSM, installs it. You provide your healthchecks API key, a request is made for a unique url.
A ps1 file is written to disk and a service is set up to run this at an interval of your choosing.
Finally you get to open the checks webpage where you enable notifications.

https://healthchecks.io/
https://nssm.cc/
