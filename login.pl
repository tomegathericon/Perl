#!/usr/bin/perl
require 'header.pl';
use File::Path;
use File::Copy;

#########################
#Configuration File Path#
#########################
my $confFilePath = "./CONFIGURATION_FILE";

##########################
#Name of idevsutil binary#
##########################
my $idevsutilBinaryName = "idevsutil";

##########################
#Path of idevsutil binary#
##########################
my $idevsutilBinaryPath = "./idevsutil";

###############################
#Configuration File Parameters#
###############################
my @arrayParameters = ( 
			"PASSWORD",
			"ENCTYPE",
			"PVTKEY",
			"ACCOUNT_CONFIG"
                      );
###############################
#Hash to hold the values of   #
#Configuration File Parameters#
###############################
my %hashParameters = ( 
		       "PASSWORD" => undef,
		       "ENCTYPE" => undef,
		       "PVTKEY" => undef,
		       "ACCOUNT_CONFIG" => undef
                     );

############################################
#Arguments to be passed to idevsutil binary# 
############################################
my @idevsutilArguments = (
                          "--password-file",
                          "--config-account",
                          "--enc-type",
                          "--pvt-key",
                          "--user",        
			  "--utf8-cmd",                  
			  "--encode",
			  "--proxy"
                         );

my $errorRedirection = "2>&1";
my $isPrivate = 0;

checkBinaryExists();
if(! -d $userName){
	$ret = system("mkdir $userName");
	if($ret ne 0){
		print "Unable to create user directory : $userName\n";
		exit 1;
	}
}

# Trace Log Entry #
my $curFile = basename(__FILE__);
print $tHandle "$lineFeed File: $curFile $lineFeed",
		"---------------------------------------- $lineFeed";

unless(-e $pwdPath){
	getParameterValue(\$arrayParameters[0], \$hashParameters{$arrayParameters[0]});
	createEncodeFile($hashParameters{$arrayParameters[0]}, $pwdPath);
}

unless(-e $serverfile){
	getServerAddr();
}

getParameterValue(\$arrayParameters[3], \$hashParameters{$arrayParameters[3]});
if("SUCCESS" ne $hashParameters{$arrayParameters[3]})
{
	configureAccount();
}
else{
	print "Account is already logged in \n";
}

#####################################################################
#This subroutine checks for the existence of idevsutil binary in the#
#current directory and also if the binary has executable permission #
#####################################################################
sub checkBinaryExists()
{
  $workingDir = $currentDir;
  $workingDir =~ s/ /\ /g;
 
  my $binaryPath = $workingDir."/idevsutil";

  if(-f $binaryPath and !-x $binaryPath)
  {
    print "idevsutil file does not have executable permission. Please give it executable permission \n";

    exit 1;
  }
  elsif(!-f $binaryPath)
  {
    print "idevsutil file does not exist in current directory. Please copy idevsutil file to current directory \n";

    exit 1;
  }
  else
  {
  }
}

######################################################
#This subroutine configures an user account if the   #
#account is not already configured                   #
######################################################
sub configureAccount()
{
  my $configUtf8File = "$currentDir/$userName/.configUtf8.txt";
  my $defaultEncryptionKey = "DEFAULT";
  my $privateEncryptionKey = "PRIVATE";
  if(defined $hashParameters{$arrayParameters[3]} and
             $hashParameters{$arrayParameters[3]} ne "" and
             $hashParameters{$arrayParameters[3]} =~ m/^SUCCESS$/i)
  {
  }
  else
  {
    getParameterValue(\$arrayParameters[1], \$hashParameters{$arrayParameters[1]});
    getParameterValue(\$arrayParameters[2], \$hashParameters{$arrayParameters[2]});
    if(!defined $hashParameters{$arrayParameters[1]} or 
                $hashParameters{$arrayParameters[1]} eq "")
    {
      $hashParameters{$arrayParameters[1]} = $defaultEncryptionKey;
    }
 
    if($hashParameters{$arrayParameters[1]} !~ m/^$defaultEncryptionKey$/i and
       $hashParameters{$arrayParameters[1]} !~ m/^$privateEncryptionKey$/i)
    {
      $hashParameters{$arrayParameters[1]} = $defaultEncryptionKey;
    } 
    
    if($hashParameters{$arrayParameters[1]} =~ m/^$privateEncryptionKey$/i)
    {
      if(!defined $hashParameters{$arrayParameters[2]} or 
                  $hashParameters{$arrayParameters[2]} eq "")
      {
        $hashParameters{$arrayParameters[1]} = $defaultEncryptionKey;
      }
    }
	
	open UTF8FILE, ">", $configUtf8File or (print $tHandle "Could not open file $configUtf8File for config cmd, Reason:$!" and die);
	print UTF8FILE $idevsutilArguments[1].$lineFeed;
	if($hashParameters{$arrayParameters[1]} =~ m/^$defaultEncryptionKey$/i)
	{
		print UTF8FILE $idevsutilArguments[2].$assignmentOperator.$defaultEncryptionKey.$lineFeed;
	}
	elsif($hashParameters{$arrayParameters[1]} =~ m/^$privateEncryptionKey$/i)
	{
		$isPrivate = 1;
		print UTF8FILE $idevsutilArguments[2].$assignmentOperator.$privateEncryptionKey.$lineFeed;
		if(! -f $pvtPath)
            	{
			createEncodeFile($hashParameters{$arrayParameters[2]}, $pvtPath);
            	}
            	print UTF8FILE $idevsutilArguments[3].$assignmentOperator.$pvtPath.$lineFeed;
	}
		       
	print UTF8FILE $idevsutilArguments[4].$assignmentOperator.$userName.$lineFeed,
		       $idevsutilArguments[0].$assignmentOperator.$pwdPath.$lineFeed,
		       $idevsutilArguments[7].$assignmentOperator.$proxyStr.$lineFeed;

	print UTF8FILE $idevsutilArguments[6].$lineFeed;
	close UTF8FILE;

	$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArguments[5].$assignmentOperator."\"$configUtf8File\"".$whiteSpace.$errorRedirection;

      print $tHandle "$lineFeed configureAccount: ";
      open TEMPHANDLE, "<", $configUtf8File or (print $tHandle "Could not open file $configUtf8File for Trace $lineFeed");
      @fileContent = <TEMPHANDLE>;
      close TEMPHANDLE;
      print $tHandle "$lineFeed @fileContent $lineFeed";
      my $commandOutput = `$idevsutilCommandLine`;
      print $tHandle "$lineFeed $commandOutput $lineFeed";
      unlink $configUtf8File;
	
      my $descOutput = undef;
      parseXMLOutput(\$commandOutput,\$descOutput,\"desc"); 
  }
}

################################################
#This subroutine parses the XML output obtained#
#while trying to fetch the server address and  #
#configuring the user account                  #
################################################ 
sub parseXMLOutput()
{ 
  my $successMsgString = "message=\"SUCCESS\"";
  my $errorMsgString = "message=\"ERROR\"";

  my $validationErrorMsgString = "Unable to proceed;";

  my $accountConfiguredSuccessMsgString = "YOUR ACCOUNT IS CONFIGURED SUCCESSFULLY";
  my $accountConfiguredErrorMsgString = "YOUR ACCOUNT IS ALREADY CONFIGURED";

  my $descString = "desc";
  my $serverIPString = "cmdUtilityServerIP";

  if(defined ${$_[0]} and
             ${$_[0]} ne "") 
  {
    if(${$_[0]} =~ m/$successMsgString/)
    {
      if(${$_[0]} =~ m/${$_[2]}/)
      {
        if($' =~ m/"[^"]+"/)
        {
          my $paramVal = $&;
          $paramVal =~ s/^.//;
          $paramVal =~ s/.$//;

          ${$_[1]} = $paramVal;

          if(${$_[2]} eq $serverIPString)
          {
          }
          elsif(${$_[1]} eq $accountConfiguredSuccessMsgString)
          {
            open CONF_FILE, ">>", $confFilePath;

            print CONF_FILE $lineFeed;
            print CONF_FILE $arrayParameters[3]." ";
            print CONF_FILE $assignmentOperator." ";
            print CONF_FILE "SUCCESS";
              
            close CONF_FILE;
	    print "\n Account is logged in Successfully \n";	
	    updateConf();
          } 
          else
          {
		unlink($pwdPath);
          }
        }
      }
    } 
    elsif(${$_[0]} =~ m/$errorMsgString/)
    {
      if(${$_[0]} =~ m/$descString/)
      {
        if($' =~ m/"[^"]+"/)
        {
          my $errorMsg = $&;
          $errorMsg =~ s/^.//;
          $errorMsg =~ s/.$//;

          if($errorMsg =~ m/$accountConfiguredErrorMsgString/i)
          {
            open CONF_FILE, ">>", $confFilePath;

            print CONF_FILE $lineFeed;
            print CONF_FILE $arrayParameters[3]." ";
            print CONF_FILE $assignmentOperator." ";
            print CONF_FILE "SUCCESS";
              
            close CONF_FILE;
	    print "\n Account is logged in Successfully \n";
	    updateConf();
          }
          else
          {
            print "$errorMsg \n";
	    unlink($pwdPath);

            exit 1;
          }
        }
      }
    }
    elsif(${$_[0]} =~ m/$validationErrorMsgString/i)
    {
      my $errorMsg = $';
      $errorMsg =~ s/^.//;
      $errorMsg =~ s/.$//;

      print "$errorMsg \n";
      unlink($pwdPath);
      exit 1;
    }
    else
    {
    }
  } 
}

sub updateConf()
{
	$dummyString = "XXXXX";
	$schPwdPath = $pwdPath."_SCH";
	copy($pwdPath, $schPwdPath);
	putParameterValue(\$arrayParameters[0], \$dummyString);
	if($isPrivate){
		$schPvtPath = $pvtPath."_SCH";
		copy($pvtPath, $schPvtPath);
		putParameterValue(\$arrayParameters[2], \$dummyString);	
	}
}
