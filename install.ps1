<#
.SYNOPSIS
  Installs Rust on Windows the way it is meant to be: rustup, the stable toolchain, the Microsoft C++ build tools
  it needs to link programs, the usual components (rust-src, rust-analyzer, clippy, rustfmt) and the targets you ask for.

.DESCRIPTION
  Looks for a Rust that is already there (installed with rustup, with the stand-alone installer, or left half-installed)
  and asks what to do with it: keep and update it, install again from scratch, or uninstall it.
  Nothing is changed before every question has been answered. Safe to run again.

  What it never touches: your projects, and what you installed with `cargo install`, your cargo configuration and
  your crates.io login (unless you ask for them to be removed when uninstalling).

.PARAMETER Yes
  Answers yes to every question (the Microsoft and Rust terms, the confirmations). When a Rust is already there and no
  action is given, a healthy one is kept and updated, a broken or half-installed one is installed again.

.PARAMETER Keep
  A Rust is already there: keep it and update it.

.PARAMETER Reinstall
  A Rust is already there: remove it and install it again (its toolchains and settings are erased).

.PARAMETER Uninstall
  Remove Rust and install nothing.

.PARAMETER Wipe
  With -Uninstall: also remove what you installed with `cargo install`, the cargo configuration and caches (the whole cargo folder).

.PARAMETER Target
  Extra compilation targets to add, for example wasm32-unknown-unknown.

.PARAMETER Toolchain
  The toolchain to install and make the default. Default: stable.

.PARAMETER RustProfile
  The rustup profile: minimal, default (adds rustfmt, clippy, docs) or complete. Default: default.

.PARAMETER SkipMsvc
  Does not install the Microsoft C++ build tools (you have them, or you use another linker).

.PARAMETER DryRun
  Shows what would be done and changes nothing. Questions are answered with their default.

.EXAMPLE
  irm https://raw.githubusercontent.com/Oignontom8283/itfrp/main/install.ps1 | iex

.EXAMPLE
  iex "& { $(irm https://raw.githubusercontent.com/Oignontom8283/itfrp/main/install.ps1) } --yes --target wasm32-unknown-unknown"
#>
[CmdletBinding(PositionalBinding = $false)]
param(
  [switch]$Yes,
  [switch]$Keep,
  [switch]$Reinstall,
  [switch]$Uninstall,
  [switch]$Wipe,
  [string[]]$Target = @(),
  [string]$Toolchain = '',
  [ValidateSet('', 'minimal', 'default', 'complete')][string]$RustProfile = '',
  [switch]$SkipMsvc,
  [switch]$DryRun,
  # lets the command line style options (--yes, --target x) work too
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @()
)

# Everything lives in this block: piped into `iex`, nothing (no function, no variable, no preference) is left in your session.
$ranFromFile = [bool]$MyInvocation.MyCommand.Path
$outcome = @{ Failed = $false }
& {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'   # the progress bar of Invoke-WebRequest makes downloads very slow in Windows PowerShell 5.1

  $o = @{ Yes = [bool]$Yes; Keep = [bool]$Keep; Reinstall = [bool]$Reinstall; Uninstall = [bool]$Uninstall; Wipe = [bool]$Wipe; SkipMsvc = [bool]$SkipMsvc; DryRun = [bool]$DryRun
          Targets = @($Target | Where-Object { $_ }); Toolchain = $Toolchain; Profile = $RustProfile; Interactive = $true }

  # the proxies rustup puts in the cargo `bin` folder (everything else there was installed by `cargo install`)
  $proxyNames = 'cargo', 'cargo-clippy', 'cargo-fmt', 'cargo-miri', 'clippy-driver', 'rls', 'rust-analyzer', 'rust-gdb', 'rust-gdbgui', 'rust-lldb', 'rustc', 'rustdoc', 'rustfmt', 'rustup'

  function Say([string]$Message) { Write-Host "[itfrp] $Message" -ForegroundColor Cyan }
  function Good([string]$Message) { Write-Host "[itfrp] $Message" -ForegroundColor Green }
  function Warn([string]$Message) { Write-Host "[itfrp] $Message" -ForegroundColor Yellow }

  # Says what is about to be done, and does it unless this is a dry run.
  function Step([string]$What, [scriptblock]$Action) {
    Say $What
    if (-not $o.DryRun) { & $Action }
  }

  # ------------------------------------------------------------------------------------------------ options
  function Resolve-Options {
    for ($i = 0; $i -lt $Rest.Count; $i++) {
      $arg = $Rest[$i]
      $name, $value = $arg -split '=', 2
      if ($name -in '--yes', '-y') { $o.Yes = $true }
      elseif ($name -eq '--keep') { $o.Keep = $true }
      elseif ($name -eq '--reinstall') { $o.Reinstall = $true }
      elseif ($name -eq '--uninstall') { $o.Uninstall = $true }
      elseif ($name -eq '--wipe') { $o.Wipe = $true }
      elseif ($name -eq '--dry-run') { $o.DryRun = $true }
      elseif ($name -eq '--skip-msvc') { $o.SkipMsvc = $true }
      elseif ($name -in '--target', '--toolchain', '--profile') {
        if ($null -eq $value) {
          if ($i + 1 -ge $Rest.Count) { throw "Option $name needs a value." }
          $i++
          $value = $Rest[$i]
        }
        if ($name -eq '--target') { $o.Targets += @($value -split '[,; ]' | Where-Object { $_ }) }
        elseif ($name -eq '--toolchain') { $o.Toolchain = $value }
        else { $o.Profile = $value }
      }
      else { throw "Unknown option: $arg" }
    }
    if ($env:ITFRP_YES -match '^(1|true|yes)$') { $o.Yes = $true }
    if ($env:ITFRP_TARGET) { $o.Targets += @($env:ITFRP_TARGET -split '[,; ]' | Where-Object { $_ }) }
    if (-not $o.Toolchain) { $o.Toolchain = if ($env:ITFRP_TOOLCHAIN) { $env:ITFRP_TOOLCHAIN } else { 'stable' } }
    if (-not $o.Profile) { $o.Profile = if ($env:ITFRP_PROFILE) { $env:ITFRP_PROFILE } else { 'default' } }
    if ($o.Profile -notin 'minimal', 'default', 'complete') { throw "Unknown profile '$($o.Profile)' (minimal, default or complete)." }
    $o.Targets = @($o.Targets | Select-Object -Unique)
    if (@($o.Keep, $o.Reinstall, $o.Uninstall | Where-Object { $_ }).Count -gt 1) { throw 'Choose only one of --keep, --reinstall and --uninstall.' }
    if ($o.Wipe -and -not $o.Uninstall) { throw '--wipe goes with --uninstall.' }
    try { $o.Interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected } catch { $o.Interactive = $true }
  }

  # ------------------------------------------------------------------------------------------------ questions
  function Ask([string]$Question) {
    if ($o.Yes -or $o.DryRun) { Say "$Question -> yes"; return $true }
    if (-not $o.Interactive) { throw "Cannot ask: $Question`nRun again with -Yes (or --yes) to answer yes to every question." }
    while ($true) {
      $answer = (Read-Host "$Question [y/N]").Trim().ToLowerInvariant()
      if ($answer -in 'y', 'yes', 'o', 'oui') { return $true }
      if ($answer -in '', 'n', 'no', 'non') { return $false }
    }
  }

  # Returns the number (from 1) of the chosen line; the default one when answered by -Yes or by a dry run.
  function Choose([string]$Question, [string[]]$Lines, [int]$Default) {
    if ($o.Yes -or $o.DryRun) { Say "$Question -> $($Lines[$Default - 1])"; return $Default }
    if (-not $o.Interactive) { throw "Cannot ask: $Question`nRun again with -Yes, or with --keep, --reinstall or --uninstall." }
    Write-Host ''
    Write-Host "[itfrp] $Question" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Lines.Count; $i++) {
      $mark = if ($i + 1 -eq $Default) { ' (default)' } else { '' }
      Write-Host ("  {0}) {1}{2}" -f ($i + 1), $Lines[$i], $mark)
    }
    while ($true) {
      $answer = (Read-Host "Your choice [1-$($Lines.Count)]").Trim()
      if ($answer -eq '') { return $Default }
      $n = 0
      if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Lines.Count) { return $n }
    }
  }

  # ------------------------------------------------------------------------------------------------ the machine
  function Get-Machine {
    $version = [Environment]::OSVersion.Version
    if ($version.Major -lt 10) { throw "Rust needs Windows 10 or later (this is Windows $($version.Major).$($version.Minor))." }
    foreach ($tool in 'winget', 'curl.exe') {
      if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool was not found. This script needs Windows 10 or 11 with winget (the 'App Installer' of the Microsoft Store) and curl, which Windows has by default."
      }
    }
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
      'AMD64' { return @{ Arch = $arch; Triple = 'x86_64-pc-windows-msvc'; VcComponent = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' } }
      'ARM64' { return @{ Arch = $arch; Triple = 'aarch64-pc-windows-msvc'; VcComponent = 'Microsoft.VisualStudio.Component.VC.Tools.ARM64' } }
      'x86' { return @{ Arch = $arch; Triple = 'i686-pc-windows-msvc'; VcComponent = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' } }
      default { throw "Unsupported processor: $arch." }
    }
  }

  function Get-CargoHome { if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $env:USERPROFILE '.cargo' } }
  function Get-RustupHome { if ($env:RUSTUP_HOME) { $env:RUSTUP_HOME } else { Join-Path $env:USERPROFILE '.rustup' } }

  function Update-SessionPath {
    $parts = @([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'))
    $env:Path = ($parts | Where-Object { $_ }) -join ';'
  }

  function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  }

  # ------------------------------------------------------------------------------------------------ what Rust is already there
  function Get-RustState {
    $cargoHome = Get-CargoHome
    $rustupHome = Get-RustupHome
    $bin = Join-Path $cargoHome 'bin'
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $msi = @(Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.Publisher -eq 'The Rust Project Developers' -and $_.DisplayName -like 'Rust *' -and $_.PSChildName -match '^\{[0-9A-Fa-f-]+\}$' })
    $rustupExe = Join-Path $bin 'rustup.exe'
    $hasRustup = Test-Path $rustupExe
    $toolchains = @()
    if (Test-Path (Join-Path $rustupHome 'toolchains')) { $toolchains = @(Get-ChildItem (Join-Path $rustupHome 'toolchains') -Directory -ErrorAction SilentlyContinue) }
    $proxies = @()
    if (Test-Path $bin) { $proxies = @(Get-ChildItem $bin -File -ErrorAction SilentlyContinue | Where-Object { $proxyNames -contains $_.BaseName -and $_.Extension -eq '.exe' }) }
    $rustupHomeUsed = (Test-Path $rustupHome) -and [bool](Get-ChildItem $rustupHome -Force -ErrorAction SilentlyContinue)

    # does a Rust work? (the cargo folder first, otherwise whatever the PATH finds)
    $working = $false
    $version = ''
    $rustc = Join-Path $bin 'rustc.exe'
    if (-not (Test-Path $rustc)) { $found = Get-Command rustc -ErrorAction SilentlyContinue; $rustc = if ($found) { $found.Source } else { $null } }
    if ($rustc) {
      try {
        $text = & $rustc --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $text) { $working = $true; $version = "$text".Trim() }
      } catch { $working = $false }
    }

    # a Rust put there by something else (scoop, chocolatey, msys2...): reported, never touched
    $foreign = @()
    foreach ($c in @(Get-Command rustc, cargo, rustup -All -ErrorAction SilentlyContinue)) {
      $src = "$($c.Source)"
      if ($src -and -not $src.StartsWith($bin, [StringComparison]::OrdinalIgnoreCase) -and $src -notmatch '\\Program Files[^\\]*\\Rust ') { $foreign += $src }
    }

    $present = ($msi.Count -gt 0) -or $hasRustup -or ($toolchains.Count -gt 0) -or ($proxies.Count -gt 0) -or $rustupHomeUsed
    $healthy = $hasRustup -and $working -and ($toolchains.Count -gt 0) -and ($msi.Count -eq 0)
    return [pscustomobject]@{
      CargoHome = $cargoHome; RustupHome = $rustupHome; Bin = $bin; Msi = $msi; HasRustup = $hasRustup; Toolchains = $toolchains
      Proxies = $proxies; RustupHomeUsed = $rustupHomeUsed; Working = $working; Version = $version; Foreign = @($foreign | Select-Object -Unique)
      Present = $present; Healthy = $healthy
    }
  }

  function Show-RustState($s) {
    if (-not $s.Present) {
      Say 'No Rust found on this computer.'
    } else {
      Say 'A Rust is already there:'
      foreach ($m in $s.Msi) { Say "  - installed with the stand-alone installer: $($m.DisplayName)" }
      if ($s.HasRustup) { Say "  - rustup: $($s.Bin)" }
      elseif ($s.Proxies.Count) { Say "  - leftovers of rustup in $($s.Bin) (rustup.exe itself is missing)" }
      if ($s.Toolchains.Count) { Say ('  - toolchains: ' + (($s.Toolchains | ForEach-Object { $_.Name }) -join ', ')) }
      elseif ($s.RustupHomeUsed) { Say "  - $($s.RustupHome) holds settings but no toolchain" }
      if ($s.Working) { Say "  - it works: $($s.Version)" } else { Say '  - it does not work (no rustc runs)' }
      if ($s.Healthy) { Good 'State: healthy.' } else { Warn 'State: broken, half-installed or not managed by rustup.' }
    }
    foreach ($f in $s.Foreign) { Warn "Another Rust is installed by something else (not touched): $f" }
  }

  # ------------------------------------------------------------------------------------------------ removing
  # Deletes a folder, even one with very deep paths (which Remove-Item refuses in Windows PowerShell 5.1).
  function Remove-Tree([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    Step "Removing $Path" {
      & cmd.exe /c rmdir /s /q "$Path" 2>$null | Out-Null
      if (Test-Path $Path) { Warn "Could not remove everything in $Path (a program is probably using it). Close it and run this script again." }
    }
  }

  # Removes a folder from a PATH variable kept in the registry, keeping the other entries exactly as they are.
  function Remove-PathEntry([string]$Dir, [string]$Key = 'HKCU:\Environment') {
    $item = Get-Item $Key -ErrorAction SilentlyContinue
    if (-not $item) { return }
    $raw = $item.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    if (-not $raw) { return }
    $want = $Dir.TrimEnd('\').ToLowerInvariant()
    $keep = @()
    $changed = $false
    foreach ($part in ($raw -split ';')) {
      if (-not $part) { continue }
      if ([Environment]::ExpandEnvironmentVariables($part).TrimEnd('\').ToLowerInvariant() -eq $want) { $changed = $true } else { $keep += $part }
    }
    if (-not $changed) { return }
    $kind = $item.GetValueKind('Path')
    Step "Removing $Dir from your PATH" { Set-ItemProperty -Path $Key -Name 'Path' -Value ($keep -join ';') -Type $kind }
  }

  # Programs running from the Rust folders hold their files: they are stopped (an editor restarts its rust-analyzer by itself).
  function Stop-RustPrograms($s) {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $p = $null
        try { $p = $_.Path } catch { }
        $p -and ($p.StartsWith($s.Bin, [StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($s.RustupHome, [StringComparison]::OrdinalIgnoreCase))
      })
    foreach ($p in $running) { Step "Stopping $($p.ProcessName) (pid $($p.Id))" { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
    if ($running.Count -and -not $o.DryRun) { Start-Sleep -Seconds 1 }
  }

  # Removes the Rust that is installed, and nothing that is yours: the toolchains and rustup's settings go,
  # what you installed with `cargo install`, the cargo configuration and your crates.io login stay.
  function Remove-RustInstall($s) {
    Stop-RustPrograms $s
    foreach ($m in $s.Msi) {
      Step "Uninstalling $($m.DisplayName)" {
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/x $($m.PSChildName) /passive /norestart" -Verb RunAs -Wait -PassThru
        if ($p.ExitCode -notin 0, 3010) { throw "Could not uninstall $($m.DisplayName) (exit code $($p.ExitCode)). Remove it from Windows settings > Apps, then run this script again." }
      }
    }
    Remove-Tree $s.RustupHome
    foreach ($f in @($s.Proxies)) { Step "Removing $($f.FullName)" { Remove-Item -LiteralPath $f.FullName -Force } }
    if (-not $o.DryRun) { Update-SessionPath }
  }

  function Remove-UserData($s) {
    Remove-Tree $s.CargoHome
  }

  # ------------------------------------------------------------------------------------------------ downloads
  # curl.exe comes with Windows (in PowerShell, plain `curl` is another thing: an alias of Invoke-WebRequest).
  function Get-Download([string]$Url, [string]$Path) {
    Say "Downloading $Url"
    if ($o.DryRun) { return }
    & curl.exe --fail --silent --show-error --location --retry 3 --output $Path $Url
    if ($LASTEXITCODE -ne 0) { throw "Could not download $Url (curl exit code $LASTEXITCODE)." }
  }

  # Downloads rustup-init.exe and checks it against the checksum Rust publishes next to it.
  function Get-RustupInit([string]$Triple, [string]$Folder) {
    $url = "https://static.rust-lang.org/rustup/dist/$Triple/rustup-init.exe"
    $path = Join-Path $Folder 'rustup-init.exe'
    Get-Download $url $path
    if ($o.DryRun) { return $path }
    $sumFile = "$path.sha256"
    Get-Download "$url.sha256" $sumFile
    $expected = @((Get-Content -Raw $sumFile) -split '\s+' | Where-Object { $_ })[0].ToLowerInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLowerInvariant()
    if ($expected -ne $actual) { throw "rustup-init.exe does not match the checksum Rust publishes (expected $expected, got $actual). Not running it." }
    Good 'rustup-init.exe: checksum verified.'
    return $path
  }

  # ------------------------------------------------------------------------------------------------ the C++ build tools
  function Test-Msvc($machine) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $false }
    $found = & $vswhere -products '*' -latest -requires $machine.VcComponent -property installationPath
    if (-not $found) { return $false }
    # the Windows SDK (kernel32.lib...) is needed as well
    $libs = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Lib'
    return (Test-Path $libs) -and [bool](Get-ChildItem $libs -Recurse -Filter kernel32.lib -ErrorAction SilentlyContinue | Select-Object -First 1)
  }

  # winget installs the Build Tools; when a Visual Studio is already there (without the C++ part), its own installer adds the C++ part to it.
  function Install-Msvc($machine) {
    $arguments = '--passive --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    if ($machine.Arch -eq 'ARM64') { $arguments += ' --add Microsoft.VisualStudio.Component.VC.Tools.ARM64' }
    $installer = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer'
    $existing = $null
    if (Test-Path (Join-Path $installer 'vswhere.exe')) { $existing = & (Join-Path $installer 'vswhere.exe') -products '*' -latest -property installationPath }
    if ($existing -and (Test-Path (Join-Path $installer 'setup.exe'))) {
      Step "Adding the C++ build tools to the Visual Studio in $existing (Windows asks for administrator rights; this takes a few minutes)..." {
        $p = Start-Process -FilePath (Join-Path $installer 'setup.exe') -ArgumentList "modify --installPath `"$existing`" $arguments" -Verb RunAs -Wait -PassThru
        if ($p.ExitCode -notin 0, 3010) { throw "The Visual Studio installer failed (exit code $($p.ExitCode))." }
        if ($p.ExitCode -eq 3010) { Warn 'Windows asks for a restart to finish installing the build tools.' }
      }
    } else {
      Step 'Installing the C++ build tools with winget (Windows asks for administrator rights; this takes a few minutes)...' {
        & winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --accept-package-agreements --accept-source-agreements --override $arguments
        if ($LASTEXITCODE -ne 0) { Warn "winget finished with code $LASTEXITCODE." }
      }
    }
    if (-not $o.DryRun -and -not (Test-Msvc $machine)) {
      throw "The C++ build tools are still not there. Open the Visual Studio Installer, choose 'Desktop development with C++' for the Build Tools, restart Windows if it asks, then run this script again."
    }
  }

  # ------------------------------------------------------------------------------------------------ rustup
  function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    Say ("$Exe " + ($Arguments -join ' '))
    if ($o.DryRun) { return }
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed (exit code $LASTEXITCODE)." }
  }

  function Set-Up-Toolchain {
    $rustup = Join-Path (Join-Path (Get-CargoHome) 'bin') 'rustup.exe'
    if (-not $o.DryRun -and -not (Test-Path $rustup)) { $rustup = 'rustup' }
    if ($o.DryRun) { $rustup = 'rustup' }
    Invoke-Native $rustup @('set', 'profile', $o.Profile)
    Invoke-Native $rustup @('toolchain', 'install', $o.Toolchain, '--profile', $o.Profile)
    Invoke-Native $rustup @('default', $o.Toolchain)
    $components = @('rust-src', 'rust-analyzer')
    if ($o.Profile -eq 'minimal') { $components += 'rustfmt', 'clippy' }
    Invoke-Native $rustup (@('component', 'add', '--toolchain', $o.Toolchain) + $components)
    if ($o.Targets.Count) { Invoke-Native $rustup (@('target', 'add', '--toolchain', $o.Toolchain) + $o.Targets) }
  }

  # Does it work? A program is compiled and run, which needs the linker.
  function Test-Installation([string]$Folder) {
    Say 'Checking the installation...'
    $bin = Join-Path (Get-CargoHome) 'bin'
    & (Join-Path $bin 'rustc.exe') --version
    & (Join-Path $bin 'cargo.exe') --version
    & (Join-Path $bin 'rustup.exe') show active-toolchain
    $source = Join-Path $Folder 'check.rs'
    Set-Content -Path $source -Value 'fn main() { println!("Rust works."); }' -Encoding Ascii
    $exe = Join-Path $Folder 'check.exe'
    & (Join-Path $bin 'rustc.exe') $source -o $exe 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'rustc could not build a program: the C++ build tools are missing or incomplete. Restart Windows if it was asked, then run this script again.' }
    & $exe
  }

  # ------------------------------------------------------------------------------------------------ the whole thing
  function Install-RustProperly {
    Resolve-Options
    $machine = Get-Machine
    Say "Windows $($machine.Arch) -> $($machine.Triple), toolchain '$($o.Toolchain)', profile '$($o.Profile)'"
    if ($o.DryRun) { Warn 'Dry run: nothing will be changed.' }
    $s = Get-RustState
    Show-RustState $s

    # ---- what to do with the Rust that is there
    $action = 'install'
    if ($s.Present) {
      if ($o.Uninstall) { $action = 'uninstall' }
      elseif ($o.Reinstall) { $action = 'reinstall' }
      elseif ($o.Keep) {
        if (-not $s.Healthy) { throw 'The Rust that is there is not healthy, so it cannot be kept. Use --reinstall to install it again.' }
        $action = 'keep'
      }
      elseif ($s.Healthy) {
        $n = Choose 'What do you want to do with it?' @('Keep it and update it', 'Install it again from scratch (the toolchains and settings are erased)', 'Uninstall Rust', 'Cancel') 1
        $action = @('keep', 'reinstall', 'uninstall', 'cancel')[$n - 1]
      } else {
        $n = Choose 'What do you want to do with it?' @('Install it again from scratch, overwriting the current settings', 'Uninstall Rust', 'Cancel') 1
        $action = @('reinstall', 'uninstall', 'cancel')[$n - 1]
      }
    } elseif ($o.Uninstall -or $o.Keep) {
      Say 'Nothing to uninstall or keep: there is no Rust here.'
      if ($o.Uninstall) { return }
    }
    if ($action -eq 'cancel') { Say 'Nothing was changed.'; return }

    # ---- every question, before anything is changed
    $erase = $action -in 'reinstall', 'uninstall'
    if ($erase) {
      $what = if ($action -eq 'uninstall') { 'Uninstall' } else { 'Erase' }
      $list = @()
      if ($s.Msi.Count) { $list += 'the stand-alone Rust installation' }
      if ($s.RustupHomeUsed) { $list += "the toolchains and settings in $($s.RustupHome)" }
      if ($s.Proxies.Count) { $list += "the rustup programs in $($s.Bin)" }
      if ($list.Count -eq 0) { $list += 'the leftovers of Rust' }
      Say ("About to remove: " + ($list -join ', ') + '.')
      Say "Kept: your projects, what you installed with 'cargo install', your cargo configuration and your crates.io login."
      if (-not (Ask "$what it now?")) { Say 'Nothing was changed.'; return }
    }
    $wipe = $false
    if ($action -eq 'uninstall' -and (Test-Path $s.CargoHome)) {
      $wipe = $o.Wipe
      if (-not $wipe -and -not $o.Yes -and -not $o.DryRun) { $wipe = Ask "Also remove $($s.CargoHome) (the tools you installed with cargo install, the cargo configuration, the crates.io login and the caches)?" }
    }
    $needMsvc = $false
    if ($action -ne 'uninstall' -and -not $o.SkipMsvc -and -not (Test-Msvc $machine)) {
      $needMsvc = $true
      Say 'The Microsoft C++ build tools are needed to link Rust programs on Windows, and are not (fully) installed.'
      Say 'Terms: https://visualstudio.microsoft.com/license-terms/ (Visual Studio Build Tools).'
      if (-not (Ask 'Do you accept the Microsoft terms and install the C++ build tools?')) { throw 'Cannot continue without the C++ build tools (use --skip-msvc if you have another linker). Nothing was changed.' }
    }
    if ($action -in 'install', 'reinstall') {
      Say 'Rust (rustup, rustc, cargo) is free software under the MIT and Apache-2.0 licences: https://www.rust-lang.org/policies/licenses'
      if (-not (Ask 'Do you accept the Rust licences and install Rust with rustup?')) { throw 'Nothing was changed.' }
    }

    $work = Join-Path ([IO.Path]::GetTempPath()) ('itfrp-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    if (-not $o.DryRun) { New-Item -ItemType Directory -Path $work | Out-Null }
    try {
      # ---- removing
      if ($erase) {
        Remove-RustInstall $s
        if ($action -eq 'uninstall') {
          Remove-PathEntry $s.Bin
          if ($wipe) { Remove-UserData $s }
          Good 'Rust is uninstalled. Open a new terminal so that the PATH is up to date.'
          return
        }
      }

      # ---- the C++ build tools
      if ($needMsvc) { Install-Msvc $machine }
      elseif ($o.SkipMsvc) { Say 'Skipping the C++ build tools (as asked).' }
      else { Good 'C++ build tools: already installed.' }

      # ---- rustup
      $cargoBin = Join-Path (Get-CargoHome) 'bin'
      if ($action -eq 'keep') {
        $rustup = Join-Path $cargoBin 'rustup.exe'
        Invoke-Native $rustup @('self', 'update')
      } else {
        $init = Get-RustupInit $machine.Triple $work
        Invoke-Native $init @('-y', '--default-toolchain', $o.Toolchain, '--profile', $o.Profile, '--default-host', $machine.Triple)
      }
      if (-not $o.DryRun) { $env:Path = "$cargoBin;$env:Path" }

      # ---- toolchain, components, targets
      Set-Up-Toolchain

      if ($o.DryRun) { Say 'Dry run: nothing was changed.'; return }
      Test-Installation $work
      Good 'Done. Open a new terminal (and restart your editor) so that every program sees the new PATH.'
    } finally {
      if (-not $o.DryRun -and (Test-Path $work)) { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }
    }
  }

  try {
    Install-RustProperly
  } catch {
    Write-Host "[itfrp] $($_.Exception.Message)" -ForegroundColor Red
    $outcome.Failed = $true
  }
}

# `exit` would close the terminal when this is piped into iex: it is only used when this is a file that was run.
if ($outcome.Failed -and $ranFromFile) { exit 1 }
