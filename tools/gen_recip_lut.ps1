param(
    [string]$OutFile = "rtl/cpu_top/rv32_recip_lut_f40.mem",
    [ValidateSet(15, 16)]
    [int]$AddressBits = 16,
    [ValidateSet(40, 52)]
    [int]$FractionBits = 40
)

# The normalized divisor has bit 31 set.  The ROM address is the remaining
# high bits below it.  AddressBits=15/F=52 and AddressBits=16/F=40 are both
# proven to keep the post-Goldschmidt quotient estimate within one.
Add-Type -AssemblyName System.Numerics
$F = $FractionBits
$validConfiguration = (($AddressBits -eq 16) -and ($F -eq 40)) -or
                      (($AddressBits -eq 15) -and ($F -eq 52))
if (-not $validConfiguration) {
    throw "Only AddressBits=16/FractionBits=40 and AddressBits=15/FractionBits=52 are proven configurations"
}
$hexDigits = [int][Math]::Ceiling($F / 4.0)
$entries = 1 -shl $AddressBits
$numerator = [System.Numerics.BigInteger]::One -shl ($F + 32)
$resolved = if ([System.IO.Path]::IsPathRooted($OutFile)) {
    [System.IO.Path]::GetFullPath($OutFile)
} else {
    [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutFile))
}
$parent = [System.IO.Path]::GetDirectoryName($resolved)
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

$writer = $null
try {
    $writer = [System.IO.StreamWriter]::new(
        $resolved, $false, [System.Text.Encoding]::ASCII)
    for ($index = 0; $index -lt $entries; $index++) {
        if ($AddressBits -eq 15) {
            $h = [System.Numerics.BigInteger](0x8000 + $index)
            # Twice the midpoint of [h<<16, (h+1)<<16).
            $denominator = ($h -shl 17) + [System.Numerics.BigInteger]::op_Implicit(65535)
        } else {
            $h = [System.Numerics.BigInteger](0x10000 + $index)
            # Twice the midpoint of [h<<15, (h+1)<<15).
            $denominator = ($h -shl 16) + [System.Numerics.BigInteger]::op_Implicit(32767)
        }
        # Round to nearest.  The following Goldschmidt correction is made
        # one-sided by ceil()ing X*R0 before forming the correction factor.
        $value = ($numerator + ($denominator / 2)) / $denominator
        # BigInteger's hexadecimal formatter may add a sign-protection zero.
        # Strip it and explicitly pad to the selected ROM width.
        $hex = $value.ToString("X").TrimStart('0')
        if ($hex.Length -eq 0) { $hex = "0" }
        $writer.WriteLine($hex.PadLeft($hexDigits, '0'))
    }
}
finally {
    if ($null -ne $writer) {
        $writer.Dispose()
    }
}

Write-Host "Generated $entries reciprocal entries (F=$F) at $resolved"
