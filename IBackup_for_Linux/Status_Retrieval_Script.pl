#!/usr/bin/perl
require 'header.pl';
use FileHandle;

use constant false => 0;
use constant true => 1;

my $pathSeparator = "/";
my $carriageReturn = "\r";
my $percent = "%";
my $assignment = "=";

#########################
#Configuration File path#
#########################
my $confFilePath = "./CONFIGURATION_FILE";

################################
#File name of file which stores#
#backup progress information   #
################################ 
my $ProgressDetailsFileName = "PROGRESS_DETAILS";

################################
#File path of file which stores#
#backup progress information   #
################################
my $ProgressDetailsFilePath = undef;

################################
#Percentage of backup completed#
#for a particular file         #
################################
my $percentageComplete = undef;

my $lineFeedPrint = false;
my $lineFeedPrinted = false;

##############################################
#Subroutine that processes SIGINT and SIGTERM#
#signal received by the script               #
##############################################
$SIG{INT} = \&process_term;
$SIG{TERM} = \&process_term;

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

constructProgressDetailsFilePath();

my $ProgressDetailsFileSize = -s $ProgressDetailsFilePath;

############################################
#While Progress Details file does not exist#
#or is empty, perform wait operation       #
############################################
while($ProgressDetailsFileSize == 0)
{
  sleep 5;

  $ProgressDetailsFileSize = -s $ProgressDetailsFilePath;
}

###############################################
#When Progress Details file is non-empty, read#
#backup progress and display in terminal      #
###############################################
if($ProgressDetailsFileSize > 0)
{
  system("clear");

  print "================BACKUP PROGRESS================ \n";

  do
  {
    do
    {
      my $lastLine = readProgressDetailsFile();

      if($lastLine ne "")
      {
        my $indexLastSpace = rindex $lastLine, $whiteSpace;

        my @params = ();
  
        push @params, substr($lastLine, 0, $indexLastSpace);
        push @params, substr($lastLine, $indexLastSpace + 1);

        $percentageComplete = $params[1];

        displayProgressBar(@params);
      }

      select undef, undef, undef, 0.001;
    }
    while(defined $percentageComplete and $percentageComplete < 100);
  }
  while(1);
}

#####################################################
#This subroutine frames the path of Progress Details#
#file.                                              # 
#####################################################
sub constructProgressDetailsFilePath()
{
    my $wrokginDir = $currentDir;
    $wrokginDir =~ s/ /\ /g;
    
    $ProgressDetailsFilePath = $wrokginDir.$pathSeparator.$userName.$pathSeparator.
                               "LOGS".$pathSeparator.
                               $ProgressDetailsFileName;
}

#########################################################
#This subroutine reads the last line of Progress Details#
#file. It then parses the line to extract the filename  #
#and the backup progress for that file.                 #
######################################################### 
sub readProgressDetailsFile()
{
  open PROGRESS_DETAILS_FILE, "<", $ProgressDetailsFilePath or (print $tHandle "$lineFeed ProgressDetails File does not exist :$! $lineFeed" or die);

  my $lastLine = undef;
  
  my @linesProgressDetailsFile = <PROGRESS_DETAILS_FILE>;
  $lastLine = $linesProgressDetailsFile[$#linesProgressDetailsFile];

  close PROGRESS_DETAILS_FILE;

  my @lastLineArray = ();
  my @fileNameArray = ();
  
  my $indexLastSpace = rindex $lastLine, $whiteSpace;
  
  push @lastLineArray, substr($lastLine, 0, $indexLastSpace);
  push @lastLineArray, substr($lastLine, $indexLastSpace + 1);

  my $indexFirstAssignment = index $lastLineArray[0], $assignment;
  
  push @fileNameArray, substr($lastLineArray[0], 0, $indexFirstAssignment);
  push @fileNameArray, substr($lastLineArray[0], $indexFirstAssignment + 1); 

  my @percentCompleteArray = split /=/, $lastLineArray[1];
 
  chomp $fileNameArray[1];
  chomp $percentCompleteArray[1];

  if($percentCompleteArray[1] eq "")
  {
    return "";
  }
  else
  { 
    return $fileNameArray[1].$whiteSpace.$percentCompleteArray[1];
  }
}

###############################################
#This subroutine contains the logic to display#
#the filename and the progress bar in the     #
#terminal window.                             #
###############################################
sub displayProgressBar()
{
  my $fileName = $_[0];
  my $percentComplete = $_[1];

  if(!$lineFeedPrinted)
  {
    autoflush STDOUT;

    print $fileName;
    print $whiteSpace;
    print $percentComplete;
  }

  if($percentComplete eq "100")
  {
    if(!$lineFeedPrinted)
    {
      autoflush STDOUT;

      print $percent;

      $lineFeedPrint = true;
    }
  }

  if(!$lineFeedPrinted)
  {
    autoflush STDOUT;

    print "[";

    for(my $index = 0; $index < $percentComplete; $index+=4)
    {
      print $assignment;
    }

    print "]";
  }

  if($percentComplete eq "100")
  {
    if($lineFeedPrint and !$lineFeedPrinted)
    {
      autoflush STDOUT;

      print $lineFeed;

      $lineFeedPrinted = true;
    }
  }
  else
  {
    autoflush STDOUT;

    print $carriageReturn;

    $lineFeedPrint = false;
    $lineFeedPrinted = false;
  }
}

#######################################################
#In case the script execution is canceled by the user,#
#the script should exit                               #
#######################################################
sub process_term()
{
  exit 0;
}
