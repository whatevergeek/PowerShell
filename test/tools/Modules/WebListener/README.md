# WebListener Module

A PowerShell module for managing the WebListener App. The included SelF-Signed Certificate `ServerCert.pfx` has the password set to `password` and is issued for the Client and Server Authentication key usages. This certificate is used by the WebListener App for SSL/TLS. The included SelF-Signed Certificate `ClientCert.pfx` has the password set to `password` and has not been issued for any specific key usage. This Certificate is used for Client Certificate Authentication with the WebListener App.

# Running WebListener

```powershell
Import-Module .\build.psm1
Publish-PSTestTools
$Listener = Start-WebListener -HttpPort 8083 -HttpsPort 8084
```

# Stopping WebListener

```powershell
Stop-WebListener
```
