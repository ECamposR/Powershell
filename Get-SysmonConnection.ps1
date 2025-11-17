function Get-SysmonConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]  $DestinationIP,
        [string[]] $ComputerName = $env:COMPUTERNAME
    )

    foreach ($PC in $ComputerName) {
        Get-WinEvent -ComputerName $PC `
                     -LogName 'Microsoft-Windows-Sysmon/Operational' `
                     -FilterXPath "*[System/EventID=3] and
                                    *[EventData[Data[@Name='DestinationIp']='$DestinationIP']]" |
        ForEach-Object {
            $xml = [xml]$_.ToXml()
            [pscustomobject]@{
                Computer        = $PC
                TimeCreated     = $_.TimeCreated
                Image           = ($xml.Event.EventData.Data | ? Name -eq 'Image').'#text'
                CommandLine     = ($xml.Event.EventData.Data | ? Name -eq 'CommandLine').'#text'
                User            = ($xml.Event.EventData.Data | ? Name -eq 'User').'#text'
                DestinationPort = ($xml.Event.EventData.Data | ? Name -eq 'DestinationPort').'#text'
                Protocol        = ($xml.Event.EventData.Data | ? Name -eq 'Protocol').'#text'
            }
        }
    }
}

