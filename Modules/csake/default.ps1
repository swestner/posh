Framework "4.5.1x64"

Task prep { cd (get-working) }
Task clean -depends prep { api-clean }
Task restore { nuget-restore }

Task default -depends clean,build
Task build -depends clean, restore { api-build }
Task unit -depends build { api-unit }
Task integration -depends build { api-integration }
Task coverage -depends build { api-coverage }

Task wclean -depends prep { web-clean }
Task bower -depends wclean { web-bower }
Task npm -depends wclean { web-npm }
Task grunt -depends wclean,bower,npm { web-grunt }

Task db -depends prep{db-build}

Task pack { nuget-pack }
Task push -depends pack { nuget-push }
Task push-no-build {nuget-pack-no-build, nuget-ppush}
Task deploy -depends push { octo-deploy }

Task lib -depends build,unit,integration,pack,push {}
Task vendor -depends build, pack { octo-push; octo-release;octo-deploy;}

Task api-release -depends build,unit,integration,pack,push {octo-release}
Task web-release -depends wclean,bower,npm,grunt,pack,push {octo-release}
Task db-release  -depends prep, clean, db, pack, push{octo-release}

Task api-deploy -depends api-release,deploy {}
Task web-deploy -depends web-release,deploy {}
Task db-deploy -depends db-release,deploy {}

Task test {}
Task test1 { Exec { exit 1 } }
Task test0 { Exec { exit 0 } }



##########################################################################################
#
#API
#
##########################################################################################
Properties { #project names
  $project_main = $null
  $project_unit = $null
  $project_intg = $null
  $coverage = ""

  $vs_ver = "12.0"
  $vs_vars = "2013"
  $vs_platform = "Any CPU"

  $ms_test = $null
}

function artifacts-clean{
  Exec { ri -Force -Recurse (get-artifact-path) -ErrorAction silentlycontinue | Out-Null }
  Exec { ni (get-artifact-path) -ItemType directory | Out-Null }
}
function api-clean {
  $path = Join-Path -Path (get-working) -ChildPath **\bin
  Exec { ri $path -Recurse -Force }  
  artifacts-clean
}

function api-build {
  $target = get-solution
  #$target = get-project
  write-output "msbuild $target /t:build /p:configuration=$build_config /p:Platform=$vs_platform /p:VisualStudioVersion=$vs_ver"
  Exec { msbuild $target /t:build /p:configuration=$build_config /p:Platform=$vs_platform /p:VisualStudioVersion=$vs_ver }
}

function api-unit { test-runner -Type "unit" }

function api-integration { test-runner -Type "integration" }

function api-coverage {}

function test-runner {
  param(
    [string]$type = $null
	#type is a secondary project in a solution with the following structure :  
    #main.csproj
    #main.unit.csproj <--secondary
    #main.integration.csproj <--secondary
    #main.otherstuff.csproj <--secondary

  )

  #look in the working directories bin folder to find the 
  $path = Join-Path -Path (get-working) -ChildPath '**\bin'  
  $bin_filter = "*." + $type + ".dll"
  $bin = (gci -Path $path -Filter $bin_filter -Recurse).FullName

  $stamp = Get-Date -Format 'yyyyMMddThhmmssZ'
  $results = (get-artifact-path) + "\" + $type + "_" + $stamp + ".trx";
  $test_runner = find-tester

  Exec { & "$test_runner" /resultsfile:$results /testcontainer:$bin /nologo /usestderr }
}

function get-solution {
  find-file -Filter '*.sln'
}

function get-project-main {

  $filter = $null

  if ($project_main -eq $null) {
    $slnName = get-name
    $project_main = "$slnName.csproj"

    Write-Host "solution name : $slnName"
    Write-Host "project name : $project_main"
  }

  $project_main = find-file -Filter $project_main
  Write-Host "project path : $project_main"
  $project_main
}

function get-project ($project,$type = "") {
  if ($project -eq $null) {
    $project = find-file -Filter ((get-name) + $type + ".csproj")
  }
  $project
}

function find-tester {
  if ($ms_test -eq $null) {
    $vs_path = Join-Path -Path (find-latest-vs) -child "..\"
    $ms_test = find-file -Filter "mstest.exe" -Path $vs_path
  }
  $ms_test
}

function find-builder {}

function find-latest-vs {

  for ($i = 20; $i -gt 0; $i --)
  {
    $testing = "VS" + $i + "0COMNTOOLS"
    $exists = Test-Path Env:\$testing

    if ($exists) {
      (gci env: | where { $_.name -like $testing } | select value).value;
      break;
    }
  }
}

##########################################################################################
#
#COMMON
#
##########################################################################################
Properties {
  $build_config = "Release"
  $version = "0.0.0.0"
  $prerelease = ""
  $prereleaseSuffix = "-prerelease"
  $notes = "no notes"
  $artifacts = $null
  $root = $null
}

function get-working {
  if (!($root)) {
    $root = $pwd;
  }

  (New-Object System.IO.DirectoryInfo $root).FullName
}

function get-name {
  $name = (gci (get-working) -Filter *.sln).BaseName

	if(!$name){
		$name = (gi $(get-working)).Basename
	}

	$name
}

function get-artifact-path {
  $result = $null;

  if (!$artifacts) {
    Join-Path -Path (get-working) -ChildPath 'artifacts'
  } else {
    $artifacts
  }

}


function find-file {
  param([string]$filter = $(throw "part of the file name to looks for is missing"),
    [string]$path = $null)

  if (!$path) {
    $path = get-working
  }

  (gci $path -Recurse -Filter $filter).FullName
}

function load {
  param([string]$name = (throw "you must pass the path to the module to load"))

  if (!(Get-Module $name)) { Import-Module $name }

}

##########################################################################################
#
#NUGET
#
##########################################################################################
Properties { #nuget
  $nuget = "nuget" #needs to be in PATH
  $nuget_url = "http://ccnuget/"
  $nuget_url_sym = "http://ccsymbols/NuGet"
  $nuget_key = ""
  $nuget_spec = ""
}

function nuget-restore { Exec { & "$nuget" restore } }
function nuget-pack {
  $spec = get-nuspec
  Write-Host "spec = $spec"
  Write-Host "config = $build_config" 
  $semver = (get-version)
  Write-Output "$nuget pack $spec -Version $semver -NoPackageAnalysis -Symbols -Properties Configuration=$build_config -output (get-artifact-path)"
  
  Exec { & "$nuget" pack $spec -Version $semver -NoPackageAnalysis -Symbols -Properties Configuration=$build_config -output (get-artifact-path) }
}

function nuget-push { if ($build_config -like "octo") { octo-push } else { nuget-ppush; nuget-spush } }

function nuget-pack-no-build{
	$spec = get-nuspec
  Write-Host "spec = $spec"
  $semver = (get-version)
  Write-Output "$nuget pack $spec -Version $semver -NoPackageAnalysis -output (get-artifact-path)"
  
  Exec { & "$nuget" pack $spec -Version $semver -NoPackageAnalysis -output (get-artifact-path) }
}

function nuget-ppush {

  Write-Output "$nuget push (get-package) -s $nuget_url"
  Exec { & "$nuget" push (get-package) -s $nuget_url }
}

function nuget-spush{ 
	Write-Output "$nuget push (get-package) -s $nuget_url"
	Exec { & "$nuget" push (get-symbols) -s $nuget_url_sym } 
}

function get-version{

  $semver = $version
  
  if($prerelease){
		$semver = "$semver$prereleaseSuffix"
  }
  
  $semver

}
function get-package {
  (gci -Path (get-artifact-path) -Filter *.nupkg -Exclude *.symbols.nupkg -Recurse).FullName
}

function get-symbols {
  (gci -Path (get-artifact-path) -Filter *.symbols.nupkg -Recurse).FullName
}


function get-nuspec {

  $path = get-working
  Write-Host "looking in $path for nuspec"

  if (!($nuget_spec)) {
			
		$name = (get-name) + '.nuspec'
		write-host "check for a nuspec with the same name as the directory $name" 
		$nuget_spec = (gci $path -Filter $name).FullName

		if(!($nuget_spec)){
			write-host "otherwise check for any nupsec in the root directory"
			#check the root directory first
			$nuget_spec = (gci $path -Filter *.nuspec).FullName
		}
		
		if(!($nuget_spec)){
			write-host "otherwise check for any nuspec anywhere"
			$nuget_spec = (gci $path -Recurse -Filter *.nuspec -Exclude *build*).FullName
		}    
  }

	if (!$nuget_spec) {
    Write-Host "nuspec not found. looking for project"
    $project = get-project-main

    if (!$project) {
      Write-Host "no project or nupsec found...this is gonna be a problem"
    }
    else {
      $nuget_spec = $project
    }

  }

  $nuget_spec
}
##########################################################################################
#
#OCTO
#
##########################################################################################
Properties { #octopus
  $octo = "octo" #needs to be in PATH
  $octo_url = "http://ccoctopus"
  $octo_key = "API-E1HOMGQPJ9EZY9IP3UPEZ63VV0"
  $octo_push_url = "$octo_url/nuget/packages"
  $octo_project = $project_name
  $octo_env = ""
}

function get-octo-project-name { 
	#get the package and strip the semver
	$project = (gi (get-package)).BaseName -replace '(?:.\d+){3}', ''
	$project = $project -replace $prereleaseSuffix, ''
	if(!$project){
		$project = (gi (get-nuspec)).BaseName 
	}

	$project;
}
function octo-push { 
	$package = get-package
	Write-Host "$nuget push  $package $octo_key -s $octo_push_url"
	Exec { & "$nuget" push $package $octo_key -s $octo_push_url } 
}

function octo-release {
  $project = (get-octo-project-name)
	#$project = (gi (get-package)).BaseName
  $semver = (get-version)
  Write-Output "`"$octo`" create-release --project=`"$project`" --version=`"$semver`" --packageversion=`"$version`" --server=`"$octo_url`" --apiKey=`"$octo_key`" --releaseNotes `"$notes`" "
  Exec { & "$octo" create-release --project="$project" --version="$version" --packageversion="$semver" --server="$octo_url" --apiKey="$octo_key" --releaseNotes "$notes" }
}

function octo-deploy {
  if (-not ($octo_env)) {
    Write-Output "No automated deployments environments have been set up. To do so set the octo_env property to the name of the octopus environment you would like to deploy to (e.g. CC3-Test, CAMS3-Test, etc)"
    exit 1
    return;
  }

  $project = (get-octo-project-name)
  Write-Output "project = $project"
  Write-Output "working = $(get-working)"
  
  Write-Output 'deploying to ' $octo_env
  Write-Output "`"$octo`" deploy-release --project `"$project`"  --releaseNumber `"$version`" --deployto `"$octo_env`" --server `"$octo_url`" --apiKey `"$octo_key`""

  exec{& "$octo" deploy-release --project "$project" --releaseNumber "$version" --deployto "$octo_env" --server "$octo_url" --apiKey "$octo_key"}
}
#########################################################################################
#
#WEB
#
##########################################################################################

Properties { #web
  $grunt = "grunt" #needs to be in PATH
  $grunt_task = "build"
  $bower = "bower" #needs to be in PATH
  $npm = "npm" #needs to be in PATH 
}

function web-grunt { Exec { & $grunt $grunt_task } }

function web-bower {
  Exec { & $bower install }
}


function web-npm { Exec { & $npm install } }

function web-clean {
  $working = (get-working)
  artifacts-clean
  Exec { & ri $working\**\bower_components -Recurse -Force }
  Exec { & $npm cache clean }
  Exec { & $bower cache clean }

}

#########################################################################################
#
#DB Deploy
#
##########################################################################################
properties{
	$server = "."
	$database = $null

}

function db-build{
	
	write-host "CreateDatabase.bat $server $database"	
	exec{.\CreateDatabase.bat $server $database}
	
	if($LastExitCode){
	   Write-Host "Database failed to build. THE BUILD IS BROOOOOOKEN!!!!"
	   Write-Host $result
	   exit $LastExitCode
}
}


