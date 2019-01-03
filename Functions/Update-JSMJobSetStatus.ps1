function Update-JSMJobSetStatus
{
    param($Job,$Message,$Status)
    if ((Test-Path 'variable:Global:ProcessStatus') -eq $false)
    {
      $Global:ProcessStatus = @()
    }
    $Global:ProcessStatus += [pscustomobject]@{TimeStamp = Get-TimeStamp; Job = $Job; Message = $Message;Status = $Status}
}
