function Test-JobCondition
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [string[]]$JobConditionList
        ,
        [Parameter(Mandatory)]
        $ConditionValuesObject
        ,
        [Parameter(Mandatory)]
        [ValidateSet($true,$false)]
        [bool]$TestFor
    )
    switch ($TestFor)
    {
        $true
        {
            if (@(switch ($JobConditionList) {{$ConditionValuesObject.$_ -eq $true}{$true}{$ConditionValuesObject.$_ -eq $false}{$false} default {$false}}) -notcontains $false)
            {
                $true
            }
            else
            {
                $false    
            }
        }
        $false
        {
            if (@(switch ($JobConditionList) {{$ConditionValuesObject.$_ -eq $true}{$true}{$ConditionValuesObject.$_ -eq $false}{$false} default {$true}}) -notcontains $true)
            {
                $true
            }
            else
            {
                $false    
            }
        }
    }
}
function Test-JobResult
{
    [cmdletbinding()]
    param
    (
        [parameter(Mandatory)]
        [hashtable]$ResultsValidation
        ,
        [parameter(Mandatory)]
        $JobResults
        ,
        [parameter()]
        [string]$JobName
    )
    if
    (
        @(
            switch ($ResultsValidation.Keys)
            {
                'ValidateType'
                {
                    $message = "$($DefinedJob.Name): Validation $_ ($($ResultsValidation.$_))"
                    Write-Log -Message $message -EntryType Attempting
                    $Result = $JobResults -is $ResultsValidation.$_
                    if ($Result -eq $true)
                    {
                        $message = "$($DefinedJob.Name): Validation $_ ($($ResultsValidation.$_))"
                        Write-Log -Message $message -EntryType Succeeded
                    }
                    if ($Result -eq $false)
                    {
                        $message = "$($DefinedJob.Name): Validation $_ ($($ResultsValidation.$_))"
                        Write-Log -Message $message -EntryType Failed
                    }
                    Write-Output -InputObject $Result
                }
                'ValidateElementCountExpression'
                {
                    $message = "$($DefinedJob.Name): Validation $_ ($($ResultsValidation.$_))"
                    Write-Log -Message $message -EntryType Attempting
                    $Result = Invoke-Expression "$($JobResults.count) $($ResultsValidation.$_)"
                    if ($Result -eq $true)
                    {
                        $message = "$($DefinedJob.Name): Validation $_ ($($ResultsValidation.$_)). Result Count: $($JobResults.count)"
                        Write-Log -Message $message -EntryType Succeeded
                    }
                    if ($Result -eq $false)
                    {
                        $message = "$($DefinedJob.Name): Validation $_ ($($ResultsValidation.$_)). Result Count: $($JobResults.count)"
                        Write-Log -Message $message -EntryType Failed
                    }
                    Write-Output -InputObject $Result
                }
                'ValidateElementMember'
                {
                    $message = "$($DefinedJob.Name): Validation $_ ($($ResultsValidation.$_))"
                    Write-Log -Message $message -EntryType Attempting                    
                    $Result = $(
                        $MemberNames = @($JobResults[0] | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name)
                        if
                        (
                            @(
                                switch ($ResultsValidation.$_)
                                {
                                    {$_ -in $MemberNames}
                                    {Write-Output -InputObject $true}
                                    {$_ -notin $MemberNames}
                                    {Write-Output -InputObject $false}
                                }
                            ) -contains $false
                        )
                        {Write-Output -InputObject $false}
                        else
                        {Write-Output -InputObject $true}
                    )
                    if ($Result -eq $true)
                    {
                        $message = "$($DefinedJob.Name): Validation $_ ($($ResultsValidation.$_))"
                        Write-Log -Message $message -EntryType Succeeded
                    }
                    if ($Result -eq $false)
                    {
                        $message = "$($DefinedJob.Name): Validation $_ ($($ResultsValidation.$_))"
                        Write-Log -Message $message -EntryType Failed
                    }
                    Write-Output -InputObject $Result
                }
                'ValidatePath'
                {
                    $message = "$($DefinedJob.Name): Validation $_ ($($ResultsValidation.$_))"
                    Write-Log -Message $message -EntryType Attempting                    
                    $Result = Test-Path -path $JobResults
                    if ($Result -eq $true)
                    {
                        $message = "$($DefinedJob.Name): Validation $_ ($($ResultsValidation.$_))"
                        Write-Log -Message $message -EntryType Succeeded
                    }
                    if ($Result -eq $false)
                    {
                        $message = "$($DefinedJob.Name): Validation $_ ($($ResultsValidation.$_))"
                        Write-Log -Message $message -EntryType Failed
                    }
                    Write-Output -InputObject $Result                    
                }
            }
        ) -contains $false
    )
    {
        Write-Output -InputObject $false
    }
    else
    {
        Write-output -inputObject $true    
    }
}
function Get-RequiredJob
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
function Get-JobToStart
{
    [cmdletbinding()]
    param
    (
        [parameter(Mandatory)]
        [hashtable]$CompletedJobs
        ,
        [parameter()]
        [psobject[]]$AllCurrentJobs
        ,
        [parameter(Mandatory)]
        [psobject[]]$RequiredJobs
    )
    $JobsToStart = @(
        $RequiredJobs | Where-Object -FilterScript {
            ($_.Name -notin $CompletedJobs.Keys) -and
            ($_.Name -notin $AllCurrentJobs.Name) -and
            (
                ($_.DependsOnJobs.count -eq 0) -or
                (Test-JobCondition -JobConditionList $_.DependsOnJobs -ConditionValuesObject $CompletedJobs -TestFor $true)
            )
        }
    )
    Write-Output -InputObject $JobsToStart
}
function Set-JobFlowManagerPeriodicReportSettings
{
    [cmdletbinding()]
    param
    (
        [bool]$SendEmail = $false
        ,
        $Recipient
        ,
        $Sender
        ,
        $subject
        ,
        [bool]$attachLog
        ,
        $smtpServer
        ,
        [bool]$WriteLog = $true
        ,
        [parameter()]
        [validateset('Seconds','Minutes','Hours','Days')]
        $units = 'Minutes'
        ,
        [parameter()]
        $length
    )
    $Script:JobFlowManagerPeriodicReportSettings = [PSCustomObject]@{
        SendEmail = $SendEmail
        WriteLog = $WriteLog
        SMTPServer = $smtpServer
        Recipient = $Recipient
        Sender = $Sender
        Subject = $subject
        attachlog = $attachLog
        Units = $units
        Length = $length
    }
    Write-Output -InputObject $Script:JobFlowManagerPeriodicReportSettings
}
function Send-JobFlowManagerPeriodicReport
{
    [CmdletBinding()]
    param
    (
        $PeriodicReportSettings,
        $RequiredJobs
    )
    if ($PeriodicReportSettings.SendEmail -eq $true -or $PeriodicReportSettings.WriteLog -eq $true)
    {
        $currentRSJobs = @{}
        $rsjobs = @(Get-RSJob)
        foreach ($rsj in $rsjobs)
        {
            $currentRSJobs.$($rsj.name) = $true
        }
        $PeriodicReportJobStatus = @(
            foreach ($rj in $RequiredJobs)
            {
                switch ($Global:completedJobs.ContainsKey($rj.name))
                {
                    $true
                    {
                        [PSCustomObject]@{
                            Name = $rj.name
                            Status = 'Completed'
                            StartTime = $rj.StartTime
                            EndTime = $rj.EndTime
                            ElapsedMinutes = [math]::round($(New-TimeSpan -Start $rj.StartTime -End $rj.EndTime).TotalMinutes,1)
                        }    
                    }
                    $false
                    {
                        switch ($currentRSJobs.ContainsKey($rj.name))
                        {
                            $true
                            {
                                [PSCustomObject]@{
                                    Name = $rj.name
                                    Status = 'Processing'
                                    StartTime = $rj.StartTime
                                    EndTime = $null
                                    ElapsedMinutes = [math]::Round($(New-TimeSpan -Start $rj.StartTime -End (Get-Date)).TotalMinutes,1)
                                }
                            }
                            $false
                            {
                                [PSCustomObject]@{
                                    Name = $rj.name
                                    Status = 'Pending'
                                    StartTime = $null
                                    EndTime = $null
                                    ElapsedMinutes = $null
                                }
                            }
                        }
                    }
                }
            }
        )
        $PeriodicReportJobStatus = $PeriodicReportJobStatus | Sort-Object StartTime,EndTime        
    }
    if ($PeriodicReportSettings.SendEmail)
    {
        $body = "$($PeriodicReportJobStatus | ConvertTo-Html)"
        $SendMailMessageParams = @{
            Body = $body
            Subject = $PeriodicReportSettings.Subject
            BodyAsHTML = $true
            To = $PeriodicReportSettings.Recipient
            From = $PeriodicReportSettings.Sender
            SmtpServer = $PeriodicReportSettings.SmtpServer
        }
        if ($PeriodicReportSettings.attachlog)
        {
            $SendMailMessageParams.attachments = $logpath
        }
        Send-MailMessage @SendMailMessageParams
    }

}
function Invoke-JobProcessingLoop
{
    [cmdletbinding()]
    param
    (
        $Settings
        ,
        [psobject[]]$JobDefinitions
        ,
        [parameter()]
        [ValidateRange(5,60)]
        [int16]$SleepSecondsBetweenRSJobCheck = 20
        ,
        [switch]$Interactive
        ,
        [switch]$FilterJobsOnly
        ,
        [switch]$RetainCompletedJobs
        ,
        [switch]$RetainFailedJobs
        ,
        [switch]$LoopOnce
        ,
        [switch]$ReportJobsToStartThenReturn
        ,
        [int]$JobFailureRetryLimit = 3
        ,
        [switch]$PeriodicReport
        ,
        $PeriodicReportSettings
    )
    ##################################################################
    #Get the Required Jobs from the JobDefinitions
    ##################################################################
    try
    {
        $message = 'Invoke-JobProcessingLoop: Get-RequiredJob'
        Write-Log -Message $message -EntryType Attempting
        $Global:RequiredJobs = Get-RequiredJob -Settings $Settings -JobDefinitions $jobDefinitions -ErrorAction Stop    
        Write-Log -Message $message -EntryType Succeeded        
    }
    catch
    {
        $myerror = $_.tostring()
        Write-Log -Message $message -EntryType Failed
        Write-Log -Message $myerror -ErrorLog -Verbose
        Return $null
    }
    ##################################################################
    #Prep for Jobs Loop
    ##################################################################
    if ($RetainCompletedJobs -eq $true -and ((Test-Path variable:Global:CompletedJobs) -eq $true))
    {
        #do nothing
    }
    else
    {
        $Global:CompletedJobs = @{} #Will add JobName as Key and Value as True when a job is completed        
    }
    if ($RetainFailedJobs -eq $true -and ((Test-Path variable:Global:FailedJobs) -eq $true))
    {
        #do nothing
    }
    else
    {
        $Global:FailedJobs = @{} #Will add JobName as Key and value as array of failures that occured
    }
    ##################################################################
    #Loop to manage Jobs to successful completion or gracefully handled failure
    ##################################################################
    #$stopwatch = [system.diagnostics.stopwatch]::startNew()
    Do
    {
        
        #initialize loop variables
        $newlyCompletedJobs = @()
        $newlyFailedDefinedJobs = @()
        #Get existing jobs and check for those that are running and/or newly completed
        $CurrentlyExistingRSJobs = @(Get-RSJob)
        $AllCurrentJobs = @($CurrentlyExistingRSJobs | Where-Object -FilterScript {$_.Name -notin $Global:CompletedJobs.Keys})
        $newlyCompletedRSJobs = $AllCurrentJobs | Where-Object -FilterScript {$_.Completed -eq $true}
        #Check for jobs that meet their start criteria
        $jobsToStart = Get-JobToStart -CompletedJobs $Global:CompletedJobs -AllCurrentJobs $AllCurrentJobs -RequiredJobs $Global:RequiredJobs
        if ($JobsToStart.Count -ge 1)
        {
            $message = "Found $($JobsToStart.Count) Jobs Ready To Start"
            Write-Log -message $message -entryType Notification -verbose
            foreach ($job in $jobsToStart)
            {
                $message = "$($job.Name): Ready to Start"
                Write-Log -message $message -entrytype Notification -verbose
                Update-ProcessStatus -Job $Job.name -Message $message -Status $true
            }
            if ($ReportJobsToStartThenReturn -eq $true)
            {
                Return $null
            }
            #Start the jobs
            :nextJobToStart foreach ($job in $JobsToStart)
            {
                #Run the PreJobCommands
                if ([string]::IsNullOrWhiteSpace($job.PreJobCommands) -eq $false)
                {
                    $message = "$($job.Name): Found PreJobCommands."
                    Write-Log -Message $message -EntryType Notification
                    $message = "$($job.Name): Run PreJobCommands"
                    try
                    {
                        Write-Log -Message $message -EntryType Attempting
                        . $($job.PreJobCommands)
                        Write-Log -Message $message -EntryType Succeeded
                    }
                    catch
                    {
                        $myerror = $_.tostring()
                        Write-Log -Message $message -EntryType Failed -ErrorLog -Verbose
                        Write-Log -Message $myerror -ErrorLog
                        continue nextJobToStart
                        $newlyFailedDefinedJobs += $($job | Select-Object -Property *,@{n='FailureType';e={'PreJobCommands'}})
                    }
                }
                #Prepare the Start-RSJob Parameters
                $StartRSJobParams = $job.StartRSJobParams
                $StartRSJobParams.Name = $job.Name                   
                #add values for variable names listed in the argumentlist property of the Defined Job (if it is not already in the StartRSJobParameters property)
                if ($job.ArgumentList.count -ge 1)
                {
                    $message = "$($job.Name): Found ArgumentList to populate with live variables."
                    Write-Log -Message $message -EntryType Notification
                    try
                    {
                        $StartRSJobParams.ArgumentList = @(
                            foreach ($a in $job.ArgumentList)
                            {
                                $message = "$($job.Name): Get Argument List Variable $a"
                                Write-Log -Message $message -EntryType Attempting
                                Get-Variable -Name $a -ValueOnly -ErrorAction Stop
                                Write-Log -Message $message -EntryType Succeeded                                    
                            }
                        )
                    }
                    catch
                    {
                        $myerror = $_.tostring()
                        Write-Log -Message $message -EntryType Failed -ErrorLog -Verbose
                        Write-Log -Message $myerror -ErrorLog
                        continue nextJobToStart
                    }
                }
                #if the job definition calls for splitting the workload among several jobs     
                if ($job.JobSplit -gt 1)
                {
                    $StartRSJobParams.Throttle = $job.JobSplit
                    $StartRSJobParams.Batch = $job.Name                
                    try
                    {
                        $message = "$($job.Name): Get the data to split from variable $($job.jobsplitDataVariableName)"
                        Write-Log -Message $message -EntryType Attempting -Verbose
                        $DataToSplit = Get-Variable -Name $job.JobSplitDataVariableName -ValueOnly -ErrorAction Stop
                        Write-Log -Message $message -EntryType Succeeded -Verbose
                    }
                    catch
                    {
                        $myerror = $_.tostring()
                        Write-Log -Message $message -EntryType Failed -ErrorLog -Verbose
                        Write-Log -Message $myerror -ErrorLog
                        continue nextJobToStart
                    }
                    try
                    {
                        $message = "$($job.Name): Calculate the split ranges for the data $($job.jobsplitDataVariableName) for $($job.JobSplit) batch jobs"
                        Write-Log -Message $message -EntryType Attempting -Verbose    
                        $splitGroups = New-SplitArrayRange -inputArray $DataToSplit -parts $job.JobSplit -ErrorAction Stop
                        Write-Log -Message $message -EntryType Succeeded -Verbose
                    }
                    catch
                    {
                        $myerror = $_.tostring()
                        Write-Log -Message $message -EntryType Failed -ErrorLog -Verbose
                        Write-Log -Message $myerror -ErrorLog
                        continue nextJobToStart
                    }
                    $splitjobcount = 0
                    foreach ($split in $splitGroups)
                    {
                        $splitjobcount++
                        $YourSplitData = $DataToSplit[$($split.start)..$($split.end)]
                        try
                        {
                            $message = "$($job.Name): Start Batch Job $splitjobcount of $($job.JobSplit)"
                            Write-Log -Message $message -EntryType Attempting -Verbose
                            Start-RSJob @StartRSJobParams | Out-Null
                            Write-Log -Message $message -EntryType Succeeded -Verbose
                            Update-ProcessStatus -Job $Job.name -Message $message -Status $true
                        }
                        catch
                        {
                            $myerror = $_.tostring()
                            Write-Log -Message $message -EntryType Failed -ErrorLog -Verbose
                            Write-Log -Message $myerror -ErrorLog
                            Update-ProcessStatus -Job $Job.name -Message $message -Status $false
                            continue nextJobToStart
                        }
                    }
                }
                #otherwise just start one job
                else
                {      
                    try
                    {
                        $message = "$($job.Name): Start Job"                 
                        Write-Log -Message $message -EntryType Attempting -Verbose
                        Start-RSJob @StartRSJobParams | Out-Null
                        Write-Log -Message $message -EntryType Succeeded -Verbose              
                        Update-ProcessStatus -Job $Job.name -Message $message -Status $true
                    }
                    catch
                    {
                        $myerror = $_.tostring()
                        Write-Log -Message $message -EntryType Failed -ErrorLog -Verbose
                        Write-Log -Message $myerror -ErrorLog
                        Update-ProcessStatus -Job $Job.name -Message $message -Status $false
                        continue nextJobToStart
                    }
                }
                switch (Test-Member -Name StartTime -MemberType NoteProperty -InputObject $job)
                {
                    $true
                    {$job.StartTime = Get-Date}
                    $false
                    {$job | Add-Member -MemberType NoteProperty -Name StartTime -Value (Get-Date)}
                }
            }
            $message = "Finished Processing Jobs Ready To Start"
            Write-Log -message $message -entryType Notification -verbose
        }#if
        #Check for newly completed jobs that may need to be received and validated
        if ($newlyCompletedRSJobs.count -ge 1)
        {
            $skipBatchJobs = @{}
            $newlyCompletedJobs = @(
                :nextRSJob foreach ($rsJob in $newlyCompletedRSJobs)
                {
                    #skip examining this job if another in the same batch has already been examined in this loop
                    if ($skipBatchJobs.ContainsKey($rsJob.name))
                    {
                        continue nextRSJob
                    }
                    #Match the RS Job to the Job Definition
                    $DefinedJob = @($Global:RequiredJobs | Where-Object -FilterScript {$_.name -eq $rsJob.name})
                    if ($DefinedJob.Count -eq 1)
                    {
                        $DefinedJob = $DefinedJob[0]
                    }
                    else
                    {
                        #this is not a managed job so we move on to the next one
                        continue nextRSJob    
                    }
                    #if the job is split into batched jobs, check if all batched jobs are completed
                    if ($DefinedJob.JobSplit -gt 1)
                    {
                        $BatchRSJobs = @(Get-RSJob -Batch $DefinedJob.Name)
                        if ($BatchRSJobs.Count -eq $DefinedJob.JobSplit)
                        {
                            if (($BatchRSJobs.Completed) -contains $false)
                            {
                                $skipBatchJobs.$($DefinedJob.Name) = $true
                                continue nextRSJob
                            }
                            else
                            {
                                $skipBatchJobs.$($DefinedJob.Name) = $true                                
                            }           
                        }
                        else #this is a failure that needs to be raised
                        {
                            #how should we exit the loop and report what happened?
                            #$NewlyFailedJobs += $($BatchRSJobs | Add-Member -MemberType NoteProperty -Name JobFailureType -Value 'SplitJobCountMismatch')                        
                        }   
                    }
                    switch (Test-Member -InputObject $DefinedJob -Name EndTime -MemberType NoteProperty)
                    {
                        $true
                        {$DefinedJob.EndTime = Get-Date}
                        $false
                        {$DefinedJob | Add-Member -MemberType NoteProperty -Name EndTime -Value (Get-Date)}
                    }
                    Write-Output -InputObject $DefinedJob
                }
            )
        }
        if ($newlyCompletedJobs.Count -ge 1)
        {
            Write-Log -Message "Found $($newlyCompletedJobs.Count) Newly Completed Defined Job(s) to Process: $($newlyCompletedJobs.Name -join ',')" -Verbose -EntryType Notification
        }
        :nextDefinedJob foreach ($DefinedJob in $newlyCompletedJobs)
        {
            $ThisDefinedJobSuccessfullyCompleted = $false
            Write-Log -Message "$($DefinedJob.name): RS Job Newly completed" -Verbose -EntryType Notification
            $message = "$($DefinedJob.name): Match newly completed RSJob to Defined Job."
            try
            {
                Write-Log -Message $message -EntryType Attempting
                $RSJobs = @(Get-RSJob -Name $DefinedJob.Name -ErrorAction Stop)
                Write-Log -Message $message -EntryType Succeeded
            }
            catch
            {
                $myerror = $_
                Write-Log -Message $message -EntryType Failed -ErrorLog
                Write-Log -Message $myerror.tostring() -ErrorLog
                continue nextDefinedJob
            }
            if ($DefinedJob.JobSplit -gt 1 -and ($RSJobs.Count -eq $DefinedJob.JobSplit) -eq $false)
            {
                $message = "$($DefinedJob.name): RSJob Count does not match Defined Job SplitJob specification."
                Write-Log -Message $message -ErrorLog -EntryType Failed
                continue nextDefinedJob
            }
            #Log any Errors from the RS Job
            if ($RSJobs.HasErrors -contains $true)
            {
                $message = "$($DefinedJob.Name): reported errors"
                Write-Log -Message $message -ErrorLog
                $Errors = foreach ($rsJob in $RSJobs) {if ($rsJob.Error.count -gt 0) {$rsJob.Error.getenumerator()}}
                if ($Errors.count -gt 0)
                {
                    $ErrorStrings = $Errors | ForEach-Object -Process {$_.ToString()}
                    Write-Log -Message $($($DefinedJob.Name + ' Errors: ') + $($ErrorStrings -join '|')) -ErrorLog                    
                }
            }#if        
            #Receive the RS Job Results to generic JobResults variable.  
            try 
            {
                $message = "$($DefinedJob.Name): Receive Results to Generic JobResults variable pending validation"
                Write-Log -Message $message -entrytype Attempting -Verbose
                $JobResults = Receive-RSJob -Job $RSJobs -ErrorAction Stop            
                Write-Log -Message $message -entrytype Succeeded -Verbose
                Update-ProcessStatus -Job $DefinedJob.name -Message $message -Status $true
            }
            catch
            {
                $myerror = $_.tostring()
                Write-Log -Message $message -EntryType Failed -ErrorLog -Verbose
                Write-Log -Message $myerror -ErrorLog
                $NewlyFailedDefinedJobs += $($DefinedJob | Select-Object -Property *,@{n='FailureType';e={'ReceiveRSJob'}})
                Update-ProcessStatus -Job $DefinedJob.name -Message $message -Status $false
                Continue nextDefinedJob
            }
            #Validate the JobResultsVariable
            if ($DefinedJob.ResultsValidation.count -gt 0)
            {
                $message = "$($DefinedJob.Name): Found Validation Tests to perform for JobResults"
                Write-Log -Message $message -EntryType Notification
                $message = "$($DefinedJob.Name): Test JobResults for Validations ($($DefinedJob.ResultsValidation.Keys -join ','))"
                Write-Log -Message $message -EntryType Notification
                if ($JobResults -eq $null)
                {
                    $message = "$($DefinedJob.Name): JobResults is NULL and therefore FAILED Validations ($($DefinedJob.ResultsValidation.Keys -join ','))"   
                    Write-Log -Message $message -EntryType Failed
                    $newlyFailedDefinedJobs += $($DefinedJob | Select-Object -Property *,@{n='FailureType';e={'NullResults'}})
                    continue nextDefinedJob                    
                }
                else #since JobResults is not NULL run the validation tests
                {
                    switch (Test-JobResult -ResultsValidation $DefinedJob.ResultsValidation -JobResults $JobResults)
                    {
                        $true
                        {
                            $message = "$($DefinedJob.Name): JobResults PASSED Validations ($($DefinedJob.ResultsValidation.Keys -join ','))"
                            Write-Log -Message $message -EntryType Succeeded
                        }
                        $false
                        {
                            $message = "$($DefinedJob.Name): JobResults FAILED Validations ($($DefinedJob.ResultsValidation.Keys -join ','))"   
                            Write-Log -Message $message -EntryType Failed
                            $newlyFailedDefinedJobs += $($DefinedJob | Select-Object -Property *,@{n='FailureType';e={'ResultsValidation'}})
                            continue nextDefinedJob
                        }
                    }
                }                        
                }
            else
            {
                $message = "$($DefinedJob.Name): No Validation Tests defined for JobResults"
                Write-Log -Message $message -EntryType Notification            
            }
            Try
            {
                $message = "$($DefinedJob.Name): Receive Results to Variable $($DefinedJob.ResultsVariableName)"            
                Write-Log -Message $message -EntryType Attempting
                Set-Variable -Name $DefinedJob.ResultsVariableName -Value $JobResults -ErrorAction Stop -Scope Global
                Write-Log -Message $message -EntryType Succeeded
                $ThisDefinedJobSuccessfullyCompleted = $true            
            }
            catch
            {
                $myerror = $_.tostring()
                Write-Log -Message $message -EntryType Failed -ErrorLog -Verbose
                Write-Log -Message $myerror -ErrorLog
                $NewlyFailedDefinedJobs += $($DefinedJob | Select-Object -Property *,@{n='FailureType';e={'SetResultsVariable'}})
                Update-ProcessStatus -Job $Job.name -Message $message -Status $false
                Continue nextDefinedJob
            }
            if ($DefinedJob.ResultsKeyVariableNames.count -ge 1)
            {
                foreach ($v in $DefinedJob.ResultsKeyVariableNames)
                {
                    try
                    {
                        $message = "$($DefinedJob.Name): Receive Key Results to Variable $v"
                        Write-Log -Message $message -entrytype Attempting -Verbose
                        Set-Variable -Name $v -Value $($JobResults.$($v)) -ErrorAction Stop -Scope Global
                        Write-Log -Message $message -entrytype Succeeded -Verbose
                        $ThisDefinedJobSuccessfullyCompleted = $true                             
                    }
                    catch
                    {
                        $myerror = $_.tostring()
                        Write-Log -Message $message -EntryType Failed -ErrorLog -Verbose
                        Write-Log -Message $myerror -ErrorLog
                        $NewlyFailedDefinedJobs += $($DefinedJob | Select-Object -Property *,@{n='FailureType';e={'SetResultsVariablefromKey'}})
                        Update-ProcessStatus -Job $Job.name -Message $message -Status $false                                                         
                        $ThisDefinedJobSuccessfullyCompleted = $false
                        Continue nextDefinedJob
                    }
                }
            }
            if ($ThisDefinedJobSuccessfullyCompleted -eq $true)
            {
                $message = "$($DefinedJob.Name): Successfully Completed"
                Write-Log -Message $message -EntryType Notification
                Update-ProcessStatus -Job $DefinedJob.name -Message 'Job Successfully Completed' -Status $true       
                $Global:CompletedJobs.$($DefinedJob.name) = $true
                #Run PostJobCommands
                if ([string]::IsNullOrWhiteSpace($DefinedJob.PostJobCommands) -eq $false)
                {
                    $message = "$($DefinedJob.Name): Found PostJobCommands."
                    Write-Log -Message $message -EntryType Notification
                    $message = "$($DefinedJob.Name): Run PostJobCommands"
                    try
                    {
                        Write-Log -Message $message -EntryType Attempting
                        . $($DefinedJob.PostJobCommands)
                        Write-Log -Message $message -EntryType Succeeded
                    }
                    catch
                    {
                        $myerror = $_.tostring()
                        Write-Log -Message $message -EntryType Failed -ErrorLog -Verbose
                        Write-Log -Message $myerror -ErrorLog
                    }
                }
                #Remove Jobs and Variables - expand the try catch to each operation (job removal and variable removal)
                try
                {
                    Remove-RSJob $RSJobs -ErrorAction Stop
                    if ($DefinedJob.RemoveVariablesAtCompletion.count -gt 0)
                    {
                        $message = "$($DefinedJob.name): Removing Variables $($DefinedJob.RemoveVariablesAtCompletion -join ',')"
                        Write-Log -Message $message -EntryType Attempting
                        Remove-Variable -Name $DefinedJob.RemoveVariablesAtCompletion -ErrorAction Stop -Scope Global
                        Write-Log -Message $message -EntryType Succeeded
                    }
                    Remove-Variable -Name JobResults -ErrorAction Stop             
                }
                catch
                {
                    $myerror = $_.tostring()
                    Write-Log -Message $message -EntryType Failed -ErrorLog -Verbose
                    Write-Log -Message $myerror -ErrorLog                 
                }
                [gc]::Collect()
                Start-Sleep -Seconds 5
            }#if $thisDefinedJobSuccessfullyCompleted
            #remove variables JobResults,SplitData,YourSplitData . . .
        }#foreach
        if ($newlyCompletedJobs.Count -ge 1)
        {
            Write-Log -Message "Finished Processing Newly Completed Jobs" -EntryType Notification -Verbose
        }
        #do something here with NewlyFailedJobs
        if ($newlyFailedDefinedJobs.count -ge 1)
        {
            foreach ($nfdj in $newlyFailedDefinedJobs)
            {
                switch ($Global:FailedJobs.ContainsKey($nfdj.name))
                {
                    $true
                    {
                        $Global:FailedJobs.$($nfdj.name).FailureCount++
                        $Global:FailedJobs.$($nfdj.name).FailureType += $nfdj.FailureType
                    }
                    $false
                    {
                        $Global:FailedJobs.$($nfdj.name) = [PSCustomObject]@{
                            FailureCount = 1
                            FailureType = @($nfdj.FailureType)
                        }
                    }
                }
                #if JobFailureRetryLimit exceeded then abort the loop
                if (($nfdj.JobFailureRetryLimit -ne $null -and $Global:FailedJobs.$($nfdj.name).FailureCount -gt $nfdj.JobFailureRetryLimit) -or $Global:FailedJobs.$($nfdj.name).FailureCount -gt $JobFailureRetryLimit)
                {
                    $message = "$($nfdj.Name): Exceeded JobFailureRetry Limit. Ending Job Processing Loop. Failure Count: $($Global:FailedJobs.$($nfdj.name).FailureCount). FailureTypes: $($Global:FailedJobs.$($nfdj.name).FailureType -join ',')"
                    Write-Log -Message $message -EntryType FAILED -ErrorLog
                    $JobProcessingLoopFailure = $true
                    $StopLoop = $true
                }
                else #otherwise remove the jobs and we'll try again next loop
                {
                    try
                    {
                        $message = "$($nfdj.Name): Removing Failed RSJob(s)."
                        Write-Log -Message $message -entryType Attempting
                        Get-RSJob -Name $nfdj.name | Remove-RSJob -ErrorAction Stop                        
                        Write-Log -Message $message -entryType Succeeded                        
                    }
                    catch
                    {
                        $myerror = $_.tostring()
                        Write-Log -Message $message -entrytype Failed -ErrorLog
                        Write-Log -Message $myerror -ErrorLog
                    }
                }
            }
        }
        if ($Interactive)
        {
            $Script:AllCurrentJobs = Get-RSJob | Where-Object -FilterScript {$_.Name -notin $Global:CompletedJobs.Keys}
            $CurrentlyRunningJobs = $script:AllCurrentJobs | Select-Object -ExpandProperty Name            
            Write-Verbose -Message "==========================================================================" -Verbose
            Write-Verbose -Message "$(Get-Date)" -Verbose
            Write-Verbose -Message "==========================================================================" -Verbose
            Write-Verbose -Message "Currently Running Jobs: $(($CurrentlyRunningJobs | sort-object) -join ',')" -Verbose
            Write-Verbose -Message "==========================================================================" -Verbose
            Write-Verbose -Message "Completed Jobs: $(($Global:CompletedJobs.Keys | sort-object) -join ',' )" -Verbose
            Write-Verbose -Message "==========================================================================" -Verbose
        }
        if ($PeriodicReport -eq $true)
        {
            #add code here to periodically report on progress via a job?
            #$Script:WaitingOnJobs = $Global:RequiredJobs.name | Where-Object -FilterScript {$_ -notin $Global:CompletedJobs.Keys}
            if ($PeriodicReportSettings -ne $null)
            {
                $currentUnits = $stopwatch.Elapsed.$('Total' + $PeriodicReportSettings.units)
                if ((Test-Path variable:LastUnits) -eq $false)
                {$LastUnits = 0}
                switch ($currentUnits % $PeriodicReportSettings.Length -eq 0)
                {
                    $true
                    {
                        if ($LastUnits -eq 0 -or $LastUnits -ne $currentUnits)
                        {
                            Send-JobFlowManagerPeriodicReport -PeriodicReportSettings $PeriodicReportSettings -RequiredJobs $Global:RequiredJobs
                            $LastUnits = $currentUnits
                        }
                    }
                    $false
                    {
                        #do nothing
                    }
                }

            }
        }
        if ($LoopOnce -eq $true)
        {
            $StopLoop = $true
        }
        else
        {
            Start-Sleep -Seconds $SleepSecondsBetweenRSJobCheck            
        }
    }
    Until
    (((Compare-Object -DifferenceObject @($Global:CompletedJobs.Keys) -ReferenceObject @($Global:RequiredJobs.Name)) -eq $null) -or $StopLoop)
    if ($JobProcessingLoopFailure)
    {
        Write-Output -InputObject $False
    }
    else
    {
        Write-Output -InputObject $true
    }
}

###############################################################################################
#Module Variables and Variable Functions
###############################################################################################
function Get-JobFlowManagerVariable
{
param
(
[string]$Name
)
    Get-Variable -Scope Script -Name $name 
}
function Get-JobFlowManagerVariableValue
{
param
(
[string]$Name
)
    Get-Variable -Scope Script -Name $name -ValueOnly
}
function Set-JobFlowManagerVariable
{
param
(
[string]$Name
,
$Value
)
    Set-Variable -Scope Script -Name $Name -Value $value  
}
function New-JobFlowManagerVariable
{
param 
(
[string]$Name
,
$Value
)
    New-Variable -Scope Script -Name $name -Value $Value
}
function Remove-JobFlowManagerVariable
{
param
(
[string]$Name
)
    Remove-Variable -Scope Script -Name $name
}
################################
#to develop
###############################
function Import-JobDefinitions
{
    $PossibleJobsFilePath = Join-Path (Get-ADExtractVariableValue PSScriptRoot) 'RSJobDefinitions.ps1'
    $PossibleJobs = &$PossibleJobsFilePath
}
function Update-ProcessStatus
{
    param($Job,$Message,$Status)
    if ((Test-Path 'variable:Global:ProcessStatus') -eq $false)
    {
      $Global:ProcessStatus = @()
    }
    $Global:ProcessStatus += [pscustomobject]@{TimeStamp = Get-TimeStamp; Job = $Job; Message = $Message;Status = $Status}
}
function get-yumldependencydiagram
{
    $(
    foreach ($job in $Jobs)
    {
        $JobName = $job | Select-Object -ExpandProperty Name
        $jobReferences = $job | Select-Object -ExpandProperty DependsOnJobs
        foreach ($jref in $jobReferences)    
        {
            "[" + $JobName + "] -> [" + $jref + "]"
        }
    }) -join ','
}