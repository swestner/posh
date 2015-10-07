
# Load posh-git example profile
. "$home\Documents\WindowsPowerShell\Modules\posh-git\profile.example.ps1"
install-module z
set-alias npp notepad++.exe
set-alias ex explorer.exe
$ccgit = "https://github.com/CareerCruising"



function dd{
	Param([String] $folder)
		$tempdir = [system.guid]::newguid().tostring()
		$tempdir = 'c:\' + $tempdir
		md $tempdir | Out-Null

		robocopy $tempdir $folder /mir /njh /njs /ndl /nc /ns | Out-Null
		del $folder -force -recurse | Out-Null
		del $tempdir -force | Out-Null
		write 'done!'
}


function trigger{

	Param($branch, $remote)


	if(!$branch){
		$branch = (git rev-parse --abbrev-ref HEAD)
	}

	if(!$remote){
		$remote = (git remote)
	}

	$file = './test.txt';

	if(!(test-path $file)){
		ni $file -t file
		git add --all
	}
	else
	{
		ri $file
	}

	git commit -am 'test trigger'
	git push $remote $branch

}

function prr{
	$netrc = "$home\_netrc"
	$regex = '(?:.*login\s)([^\r\n$]+)[\r\n$]*.*password\s([^\r\n$]+)'

	if([IO.File]::ReadAllText($netrc) -match $regex){
		$user = $matches[1]
		$pass = $matches[2]
	}

	pull-report --org CareerCruising --gh-user $user --gh-pass $pass
}
