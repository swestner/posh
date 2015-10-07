import-module psake
function invoke-csake{
 [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = 0)][alias("t")][string] $task,
        [Parameter(Position = 1, Mandatory = 0)][alias("v")][string] $version = $null,
        [Parameter(Position = 2, Mandatory = 0)][alias("r")][string] $root = $null,
        [Parameter(Position = 3, Mandatory = 0)][alias("n")][string] $notes = 'no notes submitted',
		[Parameter(Position = 4, Mandatory = 0)][alias("b")][string] $build = 'Release',
	    [Parameter(Position = 5, Mandatory = 0)][alias("d")][string] $deploy = $null,
		[Parameter(Position = 6, Mandatory = 0)][alias("p")][string] $properties = '',	
		[Parameter(Position = 7, Mandatory = 0)][alias("s")][string] $spec = '',
		[Parameter(Position = 8, Mandatory = 0)][alias("pre")][string] $prerelease = ''
		
)

	$ErrorActionPreference = "Stop"
	 
	 $script = join-path -path $PSScriptRoot -childpath default.ps1
   $defaults = ConvertFrom-StringData ($properties -Replace ";", "`n")
   
   if($version){
    $defaults += @{"version" = "$version"}
   }
   if($root){
    $defaults += @{"root" = "$root"}
   }

   if($deploy){
     $defaults += @{"octo_env" = "$deploy"}
   }

   if($spec){                             
     $defaults += @{"nuget_spec" = "$spec"} 
   }                    
	
	if($prerelease){
		$prerelease += @{"prerelease" = "$prerelease"} 
	}

   $defaults += @{"build_config" = "$build"}
   $defaults += @{"notes" = "$notes"}  
                                                   
   $script = join-path -path $PSScriptRoot -childpath default.ps1
   
   $out = ($defaults | out-string )
   
   write-output ''
   write-output 'Properties'
   write-output '---------------'
   write-output $out
   
   try{
     write-host "Invoke-psake $task -properties $defaults"
     Invoke-psake "$script" $task -properties $defaults
   }
   catch{}
   finally{
    if($psake.build_success -eq $true){
      exit 0
    }
    else{
      write-host "build failed"
      exit 1
    }
    if($LastExitCode){
       Write-Host "build failed"
       exit $LastExitCode
    }
    else{
        Write-Host "B3D"
    }
    $psake
    remove-module psake
    remove-module csake
  }
}
