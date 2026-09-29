param(
    [ValidateSet('Put','PutLogin','Get','Remove')][string]$Action,
    [Parameter(Mandatory=$true)][string]$Directory,
    [Parameter(Mandatory=$true)][string]$AccountId,
    [string]$PayloadVariable = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$root = [IO.Path]::GetFullPath($Directory).TrimEnd('\','/')
if ([IO.Path]::GetFileName($root) -ne 'accounts' -or [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($root)) -ne 'goobplayability') { throw 'Invalid account store' }
if ($AccountId -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { throw 'Invalid account identifier' }
$path = Join-Path $root ($AccountId.ToLowerInvariant() + '.dpapi')
$entropy = [Text.Encoding]::UTF8.GetBytes('GoobplayabilityAccountSessions-v1')
$digest = [Security.Cryptography.SHA256]::Create()
$key = [BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))).Replace('-','')
$digest.Dispose()
$mutex = [Threading.Mutex]::new($false,'Local\GoobplayabilityAccounts-' + $key)
$locked = $false
try {
    try { $locked = $mutex.WaitOne(5000) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'Busy' }
    if ($Action -in @('Put','PutLogin')) {
        if ($PayloadVariable -notmatch '^GOOB_ACCOUNT_IPC_[0-9_]+$') { throw 'Invalid private payload channel' }
        # Process-only inherited memory. No token/password arguments or plaintext files.
        $payload = [Environment]::GetEnvironmentVariable($PayloadVariable,'Process')
        [Environment]::SetEnvironmentVariable($PayloadVariable,$null,'Process')
        if ($null -eq $payload -or $payload.Length -gt 32768) { throw 'Invalid payload' }
        $record = $payload | ConvertFrom-Json
        if ($record.id -ne $AccountId) { throw 'Identity mismatch' }
        if ($Action -eq 'Put') {
            if ($record.token -isnot [string] -or $record.refresh_token -isnot [string] -or $record.token.Length -gt 16384 -or $record.refresh_token.Length -gt 16384) { throw 'Invalid session' }
            foreach ($name in $record.PSObject.Properties.Name) { if ($name -notin @('id','token','refresh_token')) { throw 'Unexpected secret field' } }
        } else {
            if ($record.email -isnot [string] -or $record.password -isnot [string] -or $record.email.Length -gt 512 -or $record.password.Length -gt 4096) { throw 'Invalid login' }
            foreach ($name in $record.PSObject.Properties.Name) { if ($name -notin @('id','email','password')) { throw 'Unexpected secret field' } }
        }
        if ([IO.File]::Exists($path)) {
            $previousBytes=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($path),$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
            $previous=[Text.Encoding]::UTF8.GetString($previousBytes) | ConvertFrom-Json
            [Array]::Clear($previousBytes,0,$previousBytes.Length)
            if ($previous.id -ne $AccountId) { throw 'Identity mismatch' }
            $preserve=if($Action -eq 'Put'){@('email','password')}else{@('token','refresh_token')}
            foreach($field in $preserve){if($null -ne $previous.$field){$record | Add-Member -NotePropertyName $field -NotePropertyValue $previous.$field}}
            $previous=$null
        } elseif ($Action -eq 'PutLogin') { throw 'Save verified session first' }
        $forgetLogin = $Action -eq 'PutLogin' -and [string]::IsNullOrEmpty($record.password)
        $payload=$record | ConvertTo-Json -Compress
        $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
        $encrypted = [Security.Cryptography.ProtectedData]::Protect($bytes,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        [Array]::Clear($bytes,0,$bytes.Length)
        $payload = $null; $record = $null
        [IO.Directory]::CreateDirectory($root) | Out-Null
        [IO.File]::WriteAllBytes($path + '.tmp',$encrypted)
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($path+'.tmp',$path,$path+'.bak') }
        else { [IO.File]::Move($path+'.tmp',$path) }
        # Forgetting a login must also discard the encrypted prior-password backup.
        if ($forgetLogin -and [IO.File]::Exists($path+'.bak')) { [IO.File]::Delete($path+'.bak') }
        '{"ok":true}'
    } elseif ($Action -eq 'Get') {
        if (-not [IO.File]::Exists($path) -or ([IO.FileInfo]$path).Length -gt 65536) { throw 'Unavailable' }
        $bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($path),$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        $payload = [Text.Encoding]::UTF8.GetString($bytes)
        [Array]::Clear($bytes,0,$bytes.Length)
        $record = $payload | ConvertFrom-Json
        if ($record.id -ne $AccountId) { throw 'Identity mismatch' }
        # Private OS.execute capture only. Never log this return value.
        $payload
        $payload = $null; $record = $null
    } else {
        # Exact ID-scoped local files only; no server deletion or account RPC.
        foreach ($suffix in @('','.bak','.tmp')) { if ([IO.File]::Exists($path+$suffix)) { [IO.File]::Delete($path+$suffix) } }
        '{"ok":true}'
    }
} catch {
    '{"ok":false,"error":"Session storage unavailable. No account credentials were changed."}'
    exit 1
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
