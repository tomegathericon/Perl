#!/usr/bin/perl
require 'header.pl';

####################
#Backup script name#
####################
my $backupScriptName = "Backup_Script.pl";

###############################
#If backup script is executing#
###############################
my $backupScriptRunning = "";

##############################
#Status Retrieval script name#
##############################
my $statusScriptName = "Status_Retrieval_Script.pl";

#########################################
#If status retrieval script is executing#
#########################################
my $statusScriptRunning = "";

#########################################
#A check if User has logged in or not   #
#########################################
my ($appTypeSupport,$appType) = getAppType();
my $encParam = "ENCTYPE";
getParameterValue(\$encParam, \$hashParameters{$encParam});
my $encType = $hashParameters{$encParam};
if(! -e $pwdPath or ($encType eq "PRIVATE" and ! -e $pvtPath)){
        print "Please login to your $appType account using login.pl and try again \n";
        system("/usr/bin/perl logout.pl 1");
        exit(1);
}

# Trace Log Entry #
my $curFile = basename(__FILE__);
print $tHandle "$lineFeed File: $curFile $lineFeed",
                "---------------------------------------- $lineFeed";

###################################
#Command to check if backup script#
#is executing                     #
###################################
my $backupScriptCmd = "ps -elf | grep \"$backupScriptName\" | grep -v cd | grep -v grep";

#############################################
#Command to check if status retrieval script#
#is executing                               #
############################################# 
my $statusScriptCmd = "ps -elf | grep $statusScriptName | grep -v grep";

$backupScriptRunning = `$backupScriptCmd`;
$statusScriptRunning = `$statusScriptCmd`;

###################################
#If backup script is running, then#
#terminate backup script          #
###################################
if($backupScriptRunning ne "")
{
  print "$backupScriptName is running \n";
  
  my @processValues = split /[\s\t]+/, $backupScriptRunning;

  my $pid = $processValues[3];  
 
  my $backupScriptTerm = kill SIGTERM, $pid;
  
  if($backupScriptTerm == 0)
  {
    print "Failed to kill $backupScriptName \n";
  }
  else
  {
    print "Successfully killed $backupScriptName \n";
  }
}
else
{
  print "$backupScriptName is not running \n";
}

#############################################
#If status retrieval script is running, then#
#terminate status retrieval script          #
#############################################
if($statusScriptRunning ne "")
{
  print "$statusScriptName is running \n";
  
  my @processValues = split /[\s\t]+/, $statusScriptRunning;

  my $pid = $processValues[3];  
 
  my $statusScriptTerm = kill SIGTERM, $pid;
  
  if($statusScriptTerm == 0)
  {
    print "Failed to kill $statusScriptName \n";
  }
  else
  {
    print "Successfully killed $statusScriptName \n";
  }
}
else
{
  print "$statusScriptName is not running \n";
}

