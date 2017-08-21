# install-powershell.sh

## Features of install-powershell.sh

* can be called directly from git
* optionally installs vs code and vs powershell extension (aka PowerShell IDE) using optional `-includeide` switch
* defaults to completely automated operation (if appropriate permissions are available)
* automatically looks up latest version via git tags
* automatic selection of appropriate install sub-script
* configures software installs for repositories when repositories are in place, otherwise pulls files from git releases.  As repository versions are made available, script will be updated to take advantage.
* user permission checking
* sub-installers called from local file system if they exist, otherwise pulled from git
* sub-installers can be called directly if auto-selection is not needed

## Minimum Requirements for install-powershell.sh

* bash shell
* `sed`
* native package manager available
* `curl` (auto-installed if missing)

## Usage

### Direct from Github

```bash
bash <(wget -O - https://raw.githubusercontent.com/PowerShell/PowerShell/master/tools/install-powershell.sh) <ARGUMENTS>

wget -O - https://raw.githubusercontent.com/PowerShell/PowerShell/master/tools/install-powershell.sh | bash -s <ARGUMENTS>
```

### Local Copy

```bash
bash install-powershell.sh <ARGUMENTS>
```

## Examples

### Only Install PowerShell Core

```bash
bash <(wget -O - https://raw.githubusercontent.com/PowerShell/PowerShell/master/tools/install-powershell.sh)
```

### Install PowerShell Core with IDE

```bash
bash <(wget -O - https://raw.githubusercontent.com/PowerShell/PowerShell/master/tools/install-powershell.sh) -includeide
```

### Install PowerShell Core with IDE and do tests that require a human to interact with the installation process

```bash
bash <(wget -O - https://raw.githubusercontent.com/PowerShell/PowerShell/master/tools/install-powershell.sh) -includeide -interactivetesting
```

### Install AppImage

```bash
bash <(wget -O - https://raw.githubusercontent.com/PowerShell/PowerShell/master/tools/install-powershell.sh) -appimage
```

### Installation To do list

* Detect and wait when package manager is busy/locked? - at least Ubuntu (CentOS does this internally)