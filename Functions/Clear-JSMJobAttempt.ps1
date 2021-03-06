function Clear-JSMJobAttempt
{
    [cmdletbinding(DefaultParameterSetName = 'All')]
    param(
        <#
        [parameter(ParameterSetName = 'SpecificJobAttempt',Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [string]$JobName
        ,
        [parameter(ParameterSetName = 'SpecificJobAttempt',Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [int[]]$Attempt
        #>
        )
    Begin
    {
        switch ($PSCmdlet.ParameterSetName)
        {
            'All'
            {
                Initialize-TrackingVariable
                $script:JobAttempts.clear()
            }
        }
    }
    <#
    Process
    {
        switch ($PSCmdlet.ParameterSetName)
        {
            'SpecificJobName'
            {
                $Script:
            }
        }
    }
    #>
}