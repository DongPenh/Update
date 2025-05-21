function Get-ChromeMasterKey {
    param($localStatePath)

    $localStateJson = Get-Content $localStatePath -Raw | ConvertFrom-Json
    $encryptedKeyBase64 = $localStateJson.os_crypt.encrypted_key
    $encryptedKey = [Convert]::FromBase64String($encryptedKeyBase64)
    $encryptedKey = $encryptedKey[5..($encryptedKey.Length - 1)] # Remove DPAPI prefix

    # Decrypt master key using DPAPI
    $masterKey = [System.Security.Cryptography.ProtectedData]::Unprotect($encryptedKey, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return $masterKey
}

function Decrypt-ChromeCookie {
    param($encryptedBytes, $masterKey)

    if ($encryptedBytes[0..2] -eq [byte[]](0x76, 0x31, 0x30)) { # 'v10' prefix
        $nonce = $encryptedBytes[3..14]
        $cipherText = $encryptedBytes[15..($encryptedBytes.Length - 17)]
        $tag = $encryptedBytes[($encryptedBytes.Length - 16)..($encryptedBytes.Length - 1)]

        $aesGcm = [System.Security.Cryptography.AesGcm]::new($masterKey)
        $plainBytes = New-Object byte[] $cipherText.Length
        $aesGcm.Decrypt($nonce, $cipherText, $tag, $plainBytes)

        return [System.Text.Encoding]::UTF8.GetString($plainBytes)
    } else {
        return "[Unsupported/Plaintext]"
    }
}

function Get-XeeCooCookies {
    param(
        [string]$Browser = "Chrome"
    )

    if ($Browser -ieq "Chrome") {
        $cookiePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Network\Cookies"
        $localStatePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
    } elseif ($Browser -ieq "Edge") {
        $cookiePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
        $localStatePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
    } else {
        Write-Error "Unsupported browser: $Browser"
        return
    }

    # Copy the cookie DB
    $tempDb = "$env:TEMP\XeeCoo_Cookies.sqlite"
    Copy-Item $cookiePath -Destination $tempDb -Force

    # Get the master key
    $masterKey = Get-ChromeMasterKey -localStatePath $localStatePath

    # Load SQLite assembly
    Add-Type -AssemblyName System.Data

    $connStr = "Data Source=$tempDb;Version=3;"
    $conn = New-Object System.Data.SQLite.SQLiteConnection $connStr
    $conn.Open()

    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT host_key, name, encrypted_value FROM cookies"

    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        $host = $reader["host_key"]
        $name = $reader["name"]
        $encryptedValue = $reader["encrypted_value"]

        $encBytes = New-Object byte[] $encryptedValue.Length
        $null = $encryptedValue.Read($encBytes, 0, $encryptedValue.Length)

        try {
            $decrypted = Decrypt-ChromeCookie -encryptedBytes $encBytes -masterKey $masterKey
        } catch {
            $decrypted = "[Decryption Failed]"
        }

        Write-Output "$host`t$name`t$decrypted"
    }

    $conn.Close()
    Remove-Item $tempDb -Force
}

# Example usage
Get-XeeCooCookies -Browser "Chrome"
# Get-XeeCooCookies -Browser "Edge"
