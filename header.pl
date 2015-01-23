#!/usr/bin/perl

use Cwd;
use Tie::File;
use File::Copy;
use File::Basename;
our $tHandle;
our $whiteSpace = " ";
our $lineFeed = "\n";
our $assignmentOperator = "=";

#######################################################################
# APP_TYPE_SUPPORT should be ibackup for ibackup and idrive for idrive#
# APP_TYPE should be IBackup for ibackup and IDrive for idrive        #
#######################################################################
#use constant APP_TYPE_SUPPORT => "ibackup";
#use constant APPTYPE => "IBackup";

#########################
#Configuration File Path#
#########################
my $confFilePath = "./CONFIGURATION_FILE";
#################################
#Array containing the lines read#
#from Configuration File        #
#################################
my @linesConfFile = ();
###############################
#Configuration File Parameters#
###############################
my @arrayParameters = ( 
                        "USERNAME",
			"PROXY"
                      );
###############################
#Hash to hold the values of   #
#Configuration File Parameters#
###############################
my %hashParameters = ( 
                       "USERNAME" => undef,
		       "PROXY" => undef
                     );

############################################
#Arguments to be passed to idevsutil binary# 
############################################
my @idevsutilArguments = (
                          "--password-file",
                          "--utf8-cmd",
			  "--encode",
			  "--getServerAddress",
			  "--proxy"
                         );
##########################
#Path of idevsutil binary#
##########################
my $idevsutilBinaryPath = "./idevsutil";

readConfigurationFile();
getParameterValue(\$arrayParameters[0],\$hashParameters{$arrayParameters[0]});
getParameterValue(\$arrayParameters[1],\$hashParameters{$arrayParameters[1]});

our $userName = $hashParameters{$arrayParameters[0]};
my $proxy = $hashParameters{$arrayParameters[1]};
our $proxyStr = getProxy();
our $currentDir = getcwd;
our $pwdPath = "$currentDir/$userName/.IDPWD";
our $pvtPath = "$currentDir/$userName/.IDPVT";
our $utf8File = "$currentDir/$userName/.utf8File.txt";
our $serverfile = "$currentDir/$userName/.serverAddress.txt";

#****************************************************************************************************
# Subroutine Name         : getAppType.
# Objective               : Get application type like ibackup/IDrive. 
# Added By                : Avinash Kumar.
#*****************************************************************************************************/

sub getAppType()
{
	$appTypeSupport = "ibackup";
	$appType = "IBackup";
	return ($appTypeSupport,$appType);
}


#****************************************************************************************************
# Subroutine Name         : createPwdFile.
# Objective               : Create password or private encrypted file.
# Added By                : Avinash Kumar.
#*****************************************************************************************************/
sub createEncodeFile()
{
	
	my $data = $_[0];
	my $path = $_[1];
	my $utfFile = "";
	$utfFile = getUtf8File($data, $path);
	
	$idevsutilCommandLine = $idevsutilBinaryPath.
			        $whiteSpace.$idevsutilArguments[1].$assignmentOperator."\"$utfFile\"";

	my $commandOutput = `$idevsutilCommandLine`;
	print $tHandle "$linFeed createEncodeFile: $commandOutput $lineFeed";
	unlink $utfFile;
}
#****************************************************************************************************
# Subroutine Name         : getUtf8File.
# Objective               : Create utf8 file.
# Added By                : Avinash Kumar.
#*****************************************************************************************************/

sub getUtf8File()
{
	my ($getVal, $encPath) = @_;
	#create utf8 file.
 	open FILE, ">", "utf8.txt" or (print $tHandle "$lineFeed utf8.txt file creation failed reason:$! $lineFeed" and die);
  	print FILE "--string-encode=$getVal\n",
  		   "--out-file=$encPath\n";
  	close(FILE);
	return "utf8.txt";
	
}

#****************************************************************************************************
# Subroutine Name         : updateServerAddr.
# Objective               : Construction of get-server address evs command and execution.
#			    Parse the output and update same in Account Setting File.
# Added By                : Avinash Kumar.
#*****************************************************************************************************/

sub getServerAddr()
{
	open UTF8FILE, ">", $utf8File or (print $tHandle "$lineFeed Could not open file $utf8File for getServerAddress, reason:$! $lineFeed" and die);
	print UTF8FILE $idevsutilArguments[3].$lineFeed,
		       $userName.$lineFeed,
		       $idevsutilArguments[0].$assignmentOperator.$pwdPath.$lineFeed,
		       $idevsutilArguments[4].$assignmentOperator.$proxyStr.$lineFeed,
		       $idevsutilArguments[2].$lineFeed;

	close UTF8FILE;
	$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArguments[1].$assignmentOperator."\"$utf8File\"";
        my $commandOutput = `$idevsutilCommandLine`;
	print $tHandle "$lineFeed getServerAddr: $commandOutput $lineFeed";
	unlink($utf8File);
	
        my $serverAddr = undef;
        parseServerXMLOutput(\$commandOutput, \$serverAddr, \"cmdUtilityServerIP");
	
	if(0 < length($serverAddr))
	{
		open FILE, ">", $serverfile or (print $tHandle "$lineFeed Could not open file $serverfile for getServerAddress, Reason:$! $lineFeed" and die);
		print FILE $serverAddr;
		close FILE;
	}
	else
	{
		print $tHandle "$lineFeed Failed to execute getServerAddress. Please check the credentials \n";
		unlink($pwdPath);
		exit;
	}
	
}
#####################################################
#This subroutine reads the entire Configuration File#
#####################################################
sub readConfigurationFile()
{
  open CONF_FILE, "<", $confFilePath or (print $tHandle "$lineFeed Configuration File does not exist :$! $lineFeed" and die);
  @linesConfFile = <CONF_FILE>;  
  close CONF_FILE;
}

############################################################
#This subroutine fetches the value of individual parameters#
#which are specified in the configuration file             #
############################################################
sub getParameterValue()
{
  foreach my $line (@linesConfFile)
  { 
    if($line =~ m/${$_[0]}/)
    {
      my @keyValuePair = split /= /, $line;
      ${$_[1]} = $keyValuePair[1];
      chomp ${$_[1]};

      ${$_[1]} =~ s/^\s+//;
      ${$_[1]} =~ s/\s+$//;
	
      last;
    }
  }
}

############################################################
#This subroutine fetches the value of individual parameters#
#which are specified in the configuration file             #
############################################################
sub putParameterValue()
{
  readConfigurationFile();
  open CONF_FILE, ">", $confFilePath or (print $tHandle "$lineFeed Configuration File does not exist :$! $lineFeed" and die);
  foreach my $line (@linesConfFile)
  {
    if($line =~ m/${$_[0]}/)
    {
      $line = "${$_[0]} = ${$_[1]}\n";
    }
    print CONF_FILE $line;
  }
  close CONF_FILE;
}

#****************************************************************************************************
# Subroutine Name         : parseServerXMLOutput.
# Objective               : Parse evs command output.
# Added By                : Arnab Gupta.
#*****************************************************************************************************/

sub parseServerXMLOutput()
{
  if(defined ${$_[0]} and ${$_[0]} ne "")
  {
    if(${$_[0]} =~ m/${$_[2]}/)
    {
      if($' =~ m/"[^"]+"/)
      {
        my $paramVal = $&;
        $paramVal =~ s/^.//;
        $paramVal =~ s/.$//;

        ${$_[1]} = $paramVal;
      }
    }
  }
}

sub getProxy()
{
	$proxyStr = "";
	my($proxyIP) = $proxy =~ /@(.*)\:/; 
	if($proxyIP ne ""){
		return $proxy;
	}
	return $proxyStr;
}


my $traceDir = "$userName/.trace";
our $traceFileName = "$traceDir/traceLog.txt";
if(-d $traceDir){
}
else {
   mkdir($traceDir);
}
if((-s $traceFileName) >= (2*1024*1024)){
   my $date = localtime();
   my $tempTrace = $traceFileName . "_" . $date;
   move($traceFileName, $tempTrace);
}
open(TRACE_HANDLE, ">> $traceFileName");
$tHandle =TRACE_HANDLE;      
