$cdHistory = Join-Path -Path $Env:USERPROFILE -ChildPath '\.cdHistory'

<# 

.SYNOPSIS 

   Tracks your most used directories, based on 'frecency'. This is done by storing your CD command history and ranking it over time.

.DESCRIPTION 

    After  a  short  learning  phase, z will take you to the most 'frecent'
    directory that matches the regex given on the command line.
	
.PARAMETER JumpPath

A regular expression of the directory name to jump to.

.PARAMETER Option

Frecency - Match by frecency (default)
Rank - Match by rank only
Time - Match by recent access only
List - List only
CurrentDirectory - Restrict matches to subdirectories of the current directory

.PARAMETER $ProviderDrives

A comma separated string of drives to match on. If none is specified, it will use a drive list from the currently selected provider.

For example, the following command will run the regular expression 'foo' against all folder names where the drive letters in your history match HKLM:\ C:\ or D:\

z foo -p HKLM,C,D

.PARAMETER $Remove

Remove the current directory from the datafile

.NOTES

Current PowerShell implementation is very crude and does not yet support all of the options of the original z bash script.
Although tracking of frequently used directories is obtained through the continued use of the "cd" command, the Windows registry is also scanned for frequently accessed paths.
	
.LINK 

   https://github.com/vincpa/z
   
.EXAMPLE

CD to the most frecent directory matching 'foo'

z foo

.EXAMPLE

CD to the most recently accessed directory matching 'foo'

z foo -o Time

#>
function z {
	param(
	[Parameter(Position=0)]
	[string]
	${JumpPath},

	[ValidateSet("Time", "T", "Frecency", "F", "Rank", "R", "List", "L", "CurrentDirectory", "C")]
	[Alias('o')]
	[string]
	$Option = 'Frecency',
	
	[Alias('p')]
	[string[]]
	$ProviderDrives = $null,
	
	[Alias('x')]
	[switch]
	$Remove = $null)
	
	if ((-not $Remove) -and [string]::IsNullOrWhiteSpace($JumpPath)) { Get-Help z; return; }
	
	if ((Test-Path $cdHistory)) {
		
		if ($Remove) {
			Save-CdCommandHistory $Remove

		} else {

			# This causes conflicts with the -Remove parameter. Not sure whether to remove registry entry.
			#$mruList = Get-MostRecentDirectoryEntries
			
			$history = (Get-Content -Path $cdHistory) #+ $mruList

			$providerRegex = Get-CurrentSessionProviderDrives $ProviderDrives
			
			$list = @()

			$history.Split([Environment]::NewLine) | ? { (-not [String]::IsNullOrWhiteSpace($_)) } | ConvertTo-DirectoryEntry |
				? { Get-DirectoryEntryMatchPredicate -path $_.Path -jumpPath $JumpPath -ProviderRegex $providerRegex } | Get-ArgsFilter -Option $Option |
				% {
					$list += $_
				}
			
			if ($Option -ne $null -and $Option.Length -gt 0 -and $Option[0] -eq 'l') {
			
				$newList = $list | % { New-Object PSObject -Property  @{Rank = $_.Rank; Path = $_.Path.FullName; LastAccessed = [DateTime]$_.Time } }
				Format-Table -InputObject $newList -AutoSize
				
			} else {

				if ($list.Length -eq 0) {
					Write-Host "$JumpPath Not found"
				
				} else {
					if ($list.Length -gt 1) {
						$entry = $list | Sort-Object -Descending { $_.Score } | select -First 1
						
					} else {
						$entry = $list[0]
					}
					
					Set-Location $entry.Path.FullName
					Save-CdCommandHistory $Remove
				}
			}
		}
	} else {
		Save-CdCommandHistory $Remove
	}
}

function pushdX
{
	[CmdletBinding(DefaultParameterSetName='Path', SupportsTransactions=$true, HelpUri='http://go.microsoft.com/fwlink/?LinkID=113370')]
	param(
	    [Parameter(ParameterSetName='Path', Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
	    [string]
	    ${Path},

	    [Parameter(ParameterSetName='LiteralPath', ValueFromPipelineByPropertyName=$true)]
	    [Alias('PSPath')]
	    [string]
	    ${LiteralPath},

	    [switch]
	    ${PassThru},

	    [Parameter(ValueFromPipelineByPropertyName=$true)]
	    [string]
	    ${StackName})

	begin
	{
	    try {
	        $outBuffer = $null
	        if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
	        {
	            $PSBoundParameters['OutBuffer'] = 1
	        }
	        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Push-Location', [System.Management.Automation.CommandTypes]::Cmdlet)
	        $scriptCmd = {& $wrappedCmd @PSBoundParameters }
	        $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
	        $steppablePipeline.Begin($PSCmdlet)
	    } catch {
	        throw
	    }
	}

	process
	{
	    try {
	        $steppablePipeline.Process($_)
			Save-CdCommandHistory # Build up the DB.
	    } catch {
	        throw
	    }
	}

	end
	{
	    try {
	        $steppablePipeline.End()
	    } catch {
	        throw
	    }
	}
}

function popdX {
	[CmdletBinding(SupportsTransactions=$true, HelpUri='http://go.microsoft.com/fwlink/?LinkID=113369')]
	param(
	    [switch]
	    ${PassThru},

	    [Parameter(ValueFromPipelineByPropertyName=$true)]
	    [string]
	    ${StackName})

	begin
	{
	    try {
	        $outBuffer = $null
	        if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
	        {
	            $PSBoundParameters['OutBuffer'] = 1
	        }
	        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Microsoft.PowerShell.Management\Pop-Location', [System.Management.Automation.CommandTypes]::Cmdlet)
	        $scriptCmd = {& $wrappedCmd @PSBoundParameters }
	        $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
	        $steppablePipeline.Begin($PSCmdlet)
	    } catch {
	        throw
	    }
	}

	process
	{
	    try {
	        $steppablePipeline.Process($_)
	    } catch {
	        throw
	    }
	}

	end
	{
	    try {
	        $steppablePipeline.End()
	    } catch {
	        throw
	    }
	}
	<#

	.ForwardHelpTargetName Microsoft.PowerShell.Management\Pop-Location
	.ForwardHelpCategory Cmdlet

	#>
}

# A wrapper function around the existing Set-Location Cmdlet.
function cdX
{
	[CmdletBinding(DefaultParameterSetName='Path', SupportsTransactions=$true, HelpUri='http://go.microsoft.com/fwlink/?LinkID=113397')]
	param(
	    [Parameter(ParameterSetName='Path', Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
	    [string]
	    ${Path},

	    [Parameter(ParameterSetName='LiteralPath', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
	    [Alias('PSPath')]
	    [string]
	    ${LiteralPath},

	    [switch]
	    ${PassThru},

	    [Parameter(ParameterSetName='Stack', ValueFromPipelineByPropertyName=$true)]
	    [string]
	    ${StackName})

	begin
	{
        $outBuffer = $null
        if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
        {
            $PSBoundParameters['OutBuffer'] = 1
        }
		
		$PSBoundParameters['ErrorAction'] = 'Stop'
		
        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Set-Location', [System.Management.Automation.CommandTypes]::Cmdlet)
        $scriptCmd = {& $wrappedCmd @PSBoundParameters }
				
        $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
        $steppablePipeline.Begin($PSCmdlet)					
	}

	process
	{
        $steppablePipeline.Process($_)
		
		Save-CdCommandHistory # Build up the DB.
	}

	end
	{
	    $steppablePipeline.End()
	}
}

function Get-DirectoryEntryMatchPredicate {
	Param(
		[Parameter(
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
    	$Path,
		
		[Parameter(
        Mandatory=$true,
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
		[string] $JumpPath,
		
		[string] $ProviderRegex
	)
	
	if ($Path -ne $null) {
		
		$null = .{
			
			$providerMatches = [System.Text.RegularExpressions.Regex]::Match($Path.FullName, $ProviderRegex).Success
			
			#Write-Host 'Regex: ' $providerRegex ' Match: ' $providerMatches.ToString().PadRight(5, ' ') 'Path: ' $Path.FullName
		}
		
		if ($providerMatches) {
			[System.Text.RegularExpressions.Regex]::Match($Path.Name, $JumpPath, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Success
		}
	}
}

function Get-CurrentSessionProviderDrives([string[]] $ProviderDrives) {
	
	if ($ProviderDrives -ne $null -and $ProviderDrives.Length -gt 0) {
		Get-ProviderDrivesRegex $ProviderDrives
	} else {
			
		# The FileSystemProvider supports \\ and X:\ paths.
		# An ideal solution would be to ask the provider if a path is supported.
		# Supports drives such as C:\ and also UNC \\
		if ((Get-Location).Provider.ImplementingType.Name -eq 'FileSystemProvider') {
			'(?i)^(((' + [String]::Concat( ((Get-Location).Provider.Drives.Name | % { $_ + '|' }) ).TrimEnd('|') + '):\\)|(\\{2})).*?'
		} else {
			Get-ProviderDrivesRegex (Get-Location).Provider.Drives
		}
	}
}

function Get-ProviderDrivesRegex([string[]] $ProviderDrives) {
	
	# UNC paths get special treatment. Allows one to 'z foo -ProviderDrives \\' and specify '\\' as the drive.
	if ($ProviderDrives -contains '\\') {
		$uncRootPathRegex = '|(\\{2})'
	}
	
	'(?i)^((' + [String]::Concat( ($ProviderDrives | % { $_ + '|' }) ).TrimEnd('|') + '):\\)' + $uncRootPathRegex + '.*?'
}

function Get-Frecency($rank, $time) {

	# Last access date/time
	$dx = (Get-Date).Subtract((New-Object System.DateTime -ArgumentList $time)).TotalSeconds

	if( $dx -lt 3600 ) { return $rank*4 }
    
	if( $dx -lt 86400 ) { return $rank*2 }
    
	if( $dx -lt 604800 ) { return $rank/2 }
	
    return $rank/4
}
			
function Save-CdCommandHistory($removeCurrentDirectory = $false) {

	$currentDirectory = Get-FormattedLocation

	$history = ''
	
	try {

		# Copy contents of file in to memory.
		if ((Test-Path $cdHistory)) {
			$history = Get-Content -Path $cdHistory
			Remove-Item $cdHistory
		}
		
		$foundDirectory = $false
		$runningTotal = 0
		
		foreach ($line in $history) {
			
			$line = $line.Trim()
			
			if ($line -ne '') {
			
				$canIncreaseRank = $true;
				
				$lineObj = ConvertTo-DirectoryEntry $line
				if ($lineObj.Path.FullName -eq $currentDirectory) {	
					
					$foundDirectory = $true
					
					if ($removeCurrentDirectory) {
						$canIncreaseRank = $false
						Write-Host "Removed entry $currentDirectory" -ForegroundColor Green
						
					} else {
						$lineObj.Rank++
						Save-HistoryEntry $cdHistory $lineObj.Rank $currentDirectory
					}
				} else {
					Out-File -InputObject $line -FilePath $cdHistory -Append
				}
				
				if ($canIncreaseRank) {
					$runningTotal += $lineObj.Rank
				}
			}
		}
		
		if (-not $foundDirectory -and $removeCurrentDirectory) {
			Write-Host "Current directory not found in CD history data file" -ForegroundColor Red
		} else {
		
			if (-not $foundDirectory) {
				Save-HistoryEntry $cdHistory 1 $currentDirectory
				$runningTotal += 1
			}
			
			if ($runningTotal -gt 6000) {
				
				$lines = Get-Content -Path $cdHistory
				Remove-Item $cdHistory
				 $lines | ? { $_ -ne $null -and $_ -ne '' } | % {
				 	$lineObj = ConvertTo-DirectoryEntry $_
					$lineObj.Rank = $lineObj.Rank * 0.99
					
					if ($lineObj.Rank -ge 1 -or $lineObj.Age -lt 86400) {
						Save-HistoryEntry $cdHistory $lineObj.Rank $lineObj.Path.FullName
					}
				}
			}
		}
	} catch {
		$history | Out-File $cdHistory # Restore file should an error occur.
		Write-Host $_.Exception.ToString() -ForegroundColor Red
	}
}

function Get-FormattedLocation() {
	if ((Get-Location).Provider.ImplementingType.Name -eq 'FileSystemProvider' -and (Get-Location).Path.Contains('FileSystem::\\')) {
		Get-Location | select -ExpandProperty ProviderPath # The registry provider does return a path which z understands. In other words, I'm too lazy.
	} else {
		Get-Location | select -ExpandProperty Path
	}
}

function Format-Rant($rank) {
	return $rank.ToString("000#.00", [System.Globalization.CultureInfo]::InvariantCulture);
}

function Save-HistoryEntry($cdHistory, $rank, $directory) {
	$entry = ConvertTo-HistoryEntry $rank $directory
	Out-File -InputObject $entry -FilePath $cdHistory -Append
}

function ConvertTo-HistoryEntry($rank, $directory) {
	(Format-Rant $rank) + (Get-Date).Ticks + $directory
}

function ConvertTo-DirectoryEntry {
	Param(
		[Parameter(
        Position=0, 
        Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
    	[String]$line
	)
	
	Process {

		$null = .{
		
			$matches = [System.Text.RegularExpressions.Regex]::Match($line, '(\d+\D\d{2})(\d+)(.*)');

			$pathValue = $matches.Groups[3].Value.Trim()
			
			try {	
				$pathValue = [System.IO.Path]::GetFileName($pathValue);
			} catch [System.ArgumentException] { }
		}

		@{
		  Rank=[double]::Parse($matches.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture);
		  Time=[long]::Parse($matches.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture);
		  Path=@{ Name = $pathValue; FullName = $matches.Groups[3].Value; }
		}
	}
}

function Get-MostRecentDirectoryEntries {

	$mruEntries = (Get-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths | % { $item = $_; $_.GetValueNames() | % { $item.GetValue($_) } })
		
	$mruEntries | % { ConvertTo-HistoryEntry 1 $_ }
}

function Get-ArgsFilter {
	Param(
		[Parameter(ValueFromPipeline=$true)]
    	[Hashtable]$historyEntry,
		
		[string]
		$Option = 'Frecency'
	)
	
	Process {
				
		if ($Option -eq 'Frecency') {
			$_.Add('Score', (Get-Frecency $_.Rank $_.Time));
		} elseif ($Option -eq 'Time') {
			$_.Add('Score', $_.Time);
		} elseif ($Option -eq 'Rank') {
			$_.Add('Score', $_.Rank);
		}
		
		return $_;
	}
}

<#

.ForwardHelpTargetName Set-Location
.ForwardHelpCategory Cmdlet

#>

$orig_cd = (Get-Alias -Name 'cd').Definition
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    set-item alias:cd -value $orig_cd
}
#Override the existing CD command with the wrapper in order to log 'cd' commands.
Set-item alias:cd -Value 'cdX'

Set-Alias -Name pushd -Value pushdX -Force -Option AllScope -Scope Global
Set-Alias -Name popd -Value popdX -Force -Option AllScope -Scope Global

Export-ModuleMember -Function z, cdX, pushdX, popdX -Alias cd, pushd
