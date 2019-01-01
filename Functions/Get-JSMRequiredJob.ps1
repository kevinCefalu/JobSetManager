function Get-JFMRequiredJob
{
    [cmdletbinding()]
    param
    (
        $Settings
        ,
        [psobject[]]$JobDefinitions
    )
    #Only the jobs that meet the settings conditions or not conditions are required
    $RequiredJobFilter = [scriptblock] {
        (($_.OnCondition.count -eq 0) -or (Test-JobCondition -JobConditionList $_.OnCondition -ConditionValuesObject $Settings -TestFor $True)) -and
        (($_.OnNOTCondition.count -eq 0) -or (Test-JobCondition -JobConditionList $_.OnNotCondition -ConditionValuesObject $Settings -TestFor $False))
    }
    $message = "Get-RequiredJob: Filter $($jobDefinitions.count) JobDefinitions for Required Jobs"
    $RequiredJobs = @($JobDefinitions | Where-Object -FilterScript $RequiredJobFilter)
    if ($RequiredJobs.Count -eq 0)
    {
        Write-Log -Message $message -EntryType Failed -ErrorLog
        Write-Output -InputObject $null
    }
    else
    {
        Write-Log -Message $message -EntryType Succeeded
        $message = "Get-RequiredJob: Found $($RequiredJobs.Count) RequiredJobs as follows: $($Global:RequiredJobs.Name -join ', ')"
        Write-Log -Message $message -EntryType Notification
        Write-Output -InputObject $RequiredJobs
    }
}
