function Get-JSMVariableValue
{
    param
    (
    [string]$Name
    )
        Get-Variable -Scope Script -Name $name -ValueOnly
}
