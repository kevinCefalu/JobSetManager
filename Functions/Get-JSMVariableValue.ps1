function Get-JFMVariableValue
{
    param
    (
    [string]$Name
    )
        Get-Variable -Scope Script -Name $name -ValueOnly
}
