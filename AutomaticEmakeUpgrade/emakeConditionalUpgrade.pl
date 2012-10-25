# Perl script
#
# To be run with same arguments as emake.  If the local version of emake
# is older than that of the Cluster Manager, this script will download an
# archive file from the Cluster Manager and install that version of emake
# locally.  In either case, emake will then be executed with the arguments
# provided.

# This script assumes that the following files are located on the Cluster
# Manager in the Electric Accelerator installation area:
#
#	apache/htdocs/i686_Linux_<version>_bcp.tar.gz
#   apache/htdocs/i686_win32_<version>_bcp.zip
#	apache/htdocs/emakeVersion.txt - a file with one line containing the emake
#		version number, for example, 6.0.0
#
# The script retrieves these files using HTTP.  The HTTP default port can be
# overriden using the environment variable EA_HTTPPORT, for example
#
#	set EA_HTTPPORT=81
#
# to use port 81 instead of the default port 80. 
#
#
# The archives are available on the Electric-Cloud ftp site, for example:
#	ftp://<userName>:<passWord>@ftp.electric-cloud.com/accelerator/emake_archive/i686_win32/i686_win32_6.0.0_bcp.zip
#	ftp://<userName>:<passWord>@ftp.electric-cloud.com/accelerator/emake_archive/i686_Linux/i686_Linux_6.0.0_bcp.tar.gz
#

# ActivePerl used for development

# TODO Package up this script as an executable for Windows and Linux platforms
# TODO Recover Insight if it was in moved bin folder
# TODO Replace die with print STDERR and run runEmake()
# TODO Trap user permission to emake installation area problems earlier
# TODO Address symbolic link errors generated by Archive::Extractor with Linux
# TODO Archive::Extractor is noisy in Windows (listing all the extracted files)

use strict;
use warnings; 
use LWP::Simple;
use Archive::Extract;

# ------Beginning of Main----------


my @localPlatform = getLocalPlatform(); # 2-dim array, "Windows","32" | "Linux","64" | etc
my $installerName = "";
my $installerPath = "";
my $emakePath = getEmakePath($localPlatform[0]); # Pass Windows or Linux OS type
my $localEmakeVersion = getLocalEmakeVersion($emakePath, $localPlatform[0]);
if ($localEmakeVersion eq "") {
	print STDOUT "Could not determine local emake version; will attempt to run installed version of emake.\n";
	runEmake() ;  # Run emake and exit this script
}

my $cmHostName = getCmHostName();

# EA Webserver hostname with optional port number from environment variable EA_HTTPPORT
my $cmHostHTTP = $cmHostName;
if (exists $ENV{'EA_HTTPPORT'}) {
	$cmHostHTTP .= ':' . $ENV{'EA_HTTPPORT'};
	}

runEmake() if ($cmHostName eq "");  # Run emake and exit this script if no cluster manager specified in emake command

my $cmEmakeVersion = getCmEmakeVersion($cmHostHTTP);
if ($cmEmakeVersion eq "") {
	print STDOUT "Encountered problem getting emake version information from Cluster Manager, running installed version of emake.\n";
	runEmake() ;  # Run emake and exit this script
}

# Compare CM and local emake version; Only attemp to upgrade local emake if CM version is greater than local
# Assuming lexical gt is sufficient for version numbers
if ($cmEmakeVersion gt $localEmakeVersion) {
	print STDOUT "Cluster Manager emake appears to be more recent than the local emake.\n";
	print STDOUT "CM emake Version: ",$cmEmakeVersion,"\n";
	print STDOUT "Local emake Version: ",$localEmakeVersion,"\n";
	print STDOUT "Will attempt to install the Cluster Manager's emake locally.\n";
	# Get installer name based on operating system
	if ($localPlatform[0] eq "Windows") {
		$installerName = "i686_win32_" . $cmEmakeVersion . "_bcp.zip";
		$installerPath = $ENV{TEMP} . "\\";
	} else {
		$installerName = "i686_Linux_" . $cmEmakeVersion . "_bcp.tar.gz";
		$installerPath = "/tmp/";
	}	
	print STDOUT "Downloading installer, $installerName.\n";
	getInstaller($cmHostHTTP, $installerName, $installerPath);
	my $expandPath = $installerPath; # Expand in same directory as installer
	expandInstaller($installerName, $installerPath, $expandPath); 
	installEmake($cmEmakeVersion,$installerPath, $installerName, $emakePath, @localPlatform);
} else {
	print STDOUT "Local version of emake equal to or more recent than Cluster Manager's emake.\n" .
		"Running local version.\n";
}
runEmake();

# ---------End of Main------------

sub expandInstaller {
	# TODO Use tar and zip to extract instead?
	my ($installerName, $installerPath, $expandPath) = @_;
	my $archive = $installerPath . $installerName;
	# This will overwrite/add to any existing extrated archive.  This is okay, since we keep track of the version
	# i686_Linux/5.4.2, 6.0.0...
	my $ae = Archive::Extract->new( archive => $archive );
	my $ok = $ae->extract( to => $expandPath );
}

sub getEmakePath {
	my ($OS) = @_;
	my $emakePath = "";
	
	if ($OS eq "Windows") {
		# Only going to use the first in the path that has emake in it
		foreach (split /;/,$ENV{PATH}) {
			if ($_ =~ /(.*\\ECloud\\i686_win32\\.*)bin/) {
				if (system('dir ' . $1 . '\\bin\\emake.exe > NUL') == 0) { # Look for emake, but silence dir output
					$emakePath = $1 . '\\'; # Include trailing \ in path 
					last;
				}
				
			}
		}
	} else {
# Use of 'which emake' would not allow this script to be called 'emake'
#		if (`which emake` =~ /(^.*\/)bin\/emake/) {
#        	$emakePath = $1;
#		}
		my @path = split(/:/, $ENV{PATH});
		for my $testPath (@path) {
			# Find the path which contains the string 'ecloud' and the file 'emake'
	        if (-e "$testPath/emake" && "$testPath/emake" =~ m/ecloud/) {
	        $emakePath = $testPath;
	        $emakePath =~ s'/bin'/'; # Includes trailing / in path
	        }
		}
	}
	if ($emakePath eq "") {
		die "emake does not seem to be installed.";
	}
	return $emakePath;
}

sub getCmHostName {
	# Could probably do these three checks in a more compact way
	# Look on the command line first
	my $cmHostName = "";
	foreach (@ARGV) {
		if ($_ =~ /--emake-cm=([^\s]+)/) {
			$cmHostName = $1;
			last;  # No need to keep looking
		}
	}
	# Look in EMAKEFLAGS next if $cmHostName not set
	if ($cmHostName eq "" and exists $ENV{EMAKEFLAGS}) {
		if ($ENV{EMAKEFLAGS} =~ /--emake-cm=([^\s]+)/) {
			$cmHostName = $1;
		}
	}
	
	# Look at EMAKE_CM next if $cmHostName not set
	if ($cmHostName eq "" and exists $ENV{EMAKE_CM}) {
			if ($ENV{EMAKE_CM} =~ /([^\s]+)/) {
				$cmHostName = $1;
		}
	}
	return $cmHostName;
}

sub runEmake {
	my $arguments = "";
	foreach (@ARGV) {
		$arguments .= $_ . " ";
	}
	# Runs emake and exits script immediately
	# Originally used exec, but this did not return a prompt after execution
	system ('emake ' . $arguments) and exit;
}

sub getLocalPlatform {
	my $OS="";
	my $bits=32;
	if ($^O eq 'linux') {
		$OS="Linux";
		if (`uname -m` =~ /64/) {
			$bits = 64;
		}
	} else {
		$OS="Windows";
		if (`set` =~ /PROCESSOR_ARCHITECTURE=.*64/) {
			$bits = 64;
		}
	}
	return ($OS,$bits);
}

sub installEmake {
	my ($cmEmakeVersion,$installerPath, $installerName, $emakePath, @localPlatform) = @_;
	my $archiveBinPath = $installerPath;
	$archiveBinPath .= "i686_win32\\$cmEmakeVersion\\64\\" if ($localPlatform[0] eq "Windows" and $localPlatform[1] eq "64");
	$archiveBinPath .= "i686_win32\\$cmEmakeVersion\\" if ($localPlatform[0] eq "Windows" and $localPlatform[1] eq "32");
	$archiveBinPath .= "i686_Linux/$cmEmakeVersion/" if ($localPlatform[0] eq "Linux" and $localPlatform[1] eq "32");
	$archiveBinPath .= "i686_Linux/$cmEmakeVersion/64/" if ($localPlatform[0] eq "Linux" and $localPlatform[1] eq "64");
	if ($localPlatform[0] eq "Windows") {
		system('move "' . $emakePath . 'bin" "' . $emakePath . 'bin.orig_"' . $$); # Use PID to uniquify backup
		system('xcopy /E /I "' . $archiveBinPath . 'bin" "' . $emakePath . 'bin"');
	} else {
		system('mv "' . $emakePath . 'bin" "' . $emakePath . 'bin.orig_"' . $$); # Use PID to uniquify backup
		system('mv "' . $emakePath . 'lib" "' . $emakePath . 'lib.orig_"' . $$); # Use PID to uniquify backup
		system('cp -r "' . $archiveBinPath . '"bin "' . $emakePath . '"');
		system('cp -r "' . $archiveBinPath . '"lib "' . $emakePath . '"');
	}
}

sub getInstaller {
	my ($cmHostHTTP,$installer,$installerPath) = @_;
	my $url = 'http://' . $cmHostHTTP . '/accelerator/' . $installer;
	my $data = LWP::Simple::get $url;
	die "Could not download installer from Cluster Manager." unless defined $data;
	open (FH, ">" . $installerPath . $installer); # Use the same name for the local file 
	binmode (FH); 
	print FH $data; 
	close (FH); 
}

sub getCmEmakeVersion {
	my ($cmHostHTTP) = @_;
	my $version = "";
	my $url = 'http://' . $cmHostHTTP . '/accelerator/emakeVersion.txt';
	my $response = LWP::Simple::get $url;
	if (defined $response) {
		if ($response =~ /(\d+\.\d+\.\d+)/) {
			$version = $1;
		} else {
			print STDERR "Improper version format. Should be of the form a.b.c, for example 5.4.2.\n";
			print STDERR "Contact the Cluster Administrator to correct.\n";
		}	
	}
	else {
		print STDERR "Could not find the emakeVersion.txt file.  Contact the Cluster Administrator to correct.\n";
	}
	return $version;

}

sub getLocalEmakeVersion {
	my ($emakePath, $OS) = @_;
	my $fullEmakePath = $emakePath;
	if ($OS eq "Windows") {
		$fullEmakePath .= 'bin\\';
	} else {
		$fullEmakePath .= 'bin/';
	}
	$fullEmakePath .= 'emake';
	my $emakeResponse = `$fullEmakePath --version` or die "Could not get local emake version; is emake installed?\n";
	my $version = "";
	if ($emakeResponse =~ /Electric Make version (\d+\.\d+\.\d+)/) {
		$version = $1;
	} else {
		print STDERR "Version not found in 'emake --version' response.\n"
	}
	return $version;
}