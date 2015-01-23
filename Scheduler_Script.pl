#!/usr/bin/perl
require 'header.pl';

use constant false => 0;
use constant true => 1;

#################################
#Whether the Scheduler script is#
#invoked by the user or by the  #
#backup script                  #
#################################
my $invokedBackupScript = false;

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

if($#ARGV + 1 == 2)
{
  $invokedBackupScript = true;
}

my $workingDir = $currentDir;
$workingDir =~ s/ /\\ /g;

my $backupScriptName = "perl Backup_Script.pl";
my $backupScriptPath = "cd ".$workingDir."; ".$backupScriptName." 1";
my $crontabFilePath = "/etc/crontab";

my $superUser = "root";

my $mainMenuChoice = undef;
my $choice = undef;
my $confirmationChoice = undef;

my @options = ();
my $numArguments = undef;

##############################
#Hash containing the weekdays#
##############################
my %hashDays = ( 1 => "MON",
                 2 => "TUE",
                 3 => "WED",
                 4 => "THU",
                 5 => "FRI",
                 6 => "SAT",
                 7 => "SUN"
               );
 
my $hour = undef;
my $minute = undef;

my @linesCrontab = ();
my $entryCrontabString = undef;

my $crontabEntryExists = false;
my $crontabEntry = undef;

if($invokedBackupScript)
{
  $mainMenuChoice = $ARGV[0];
}
else
{
  printMainMenu();
  getMainMenuChoice();
}

#############################################
#If the backup job already exists in crontab#
#############################################
if(checkEntryExistsCrontab())
{
  $crontabEntryExists = true;

  print "\n You have an existing scheduled Backup Job.";

  if($mainMenuChoice == 1)
  {
    print "\n Would you like to create a new one ? (y/n) \n";
  }
  elsif($mainMenuChoice == 2)
  {
    print "\n Would you like to edit ? (y/n) \n";
  }
  elsif($mainMenuChoice == 3)
  {
    print "\n Would you like to delete ? (y/n) \n";
  }
  else
  {
  }

  if($invokedBackupScript)
  {
    $confirmationChoice = $ARGV[1];
  }
  else
  {
    getConfirmationChoice();
  }

  if($confirmationChoice eq "y" || $confirmationChoice eq "Y")
  {  
    ############################ 
    #Remove existing backup job#
    ############################
    removeEntryFromCrontab();

    print "\n Backup Job has been successfully removed. \n\n";
  }
  else
  {
    exit 0;
  }
}
###################################
#Otherwise create a new backup job#
###################################
else
{
  if($mainMenuChoice == 2)
  {
    print "\n There is no scheduled Backup Job.";
    print "\n Do you want to add a new one ? (y/n) \n";
    getConfirmationChoice();

    if($confirmationChoice eq "y" || $confirmationChoice eq "Y") 
    {
      my $dayOptionPresentCrontab = "";
      my $hourOptionPresentCrontab = "";
      my $minuteOptionPresentCrontab = "";
      
      printAddCrontabMenu();
      getDays(\$dayOptionPresentCrontab);
      getHour(\$hourOptionPresentCrontab);
      getMinute(\$minuteOptionPresentCrontab);
      createCrontabEntry();
      writeToCrontab();

      my @daysEntered = split /,/, $choice;

      print "\n Backup Job has been successfully scheduled on";

      foreach my $value (@daysEntered)
      {
        print " $hashDays{$value}";
      }

      print " at $hour:$minute. \n\n";

      exit 0;
    }
    else
    {
      exit 0;
    }
  }
  elsif($mainMenuChoice == 3)
  {
    print "\n There is no scheduled Backup Job. \n\n";
    exit 1;
  }
  else
  {
  }
}

###################################
#Create a new backup job /        #   
#modify an existing backup job    #
###################################
if($mainMenuChoice == 1 || $mainMenuChoice == 2)
{
  my $dayOptionPresentCrontab = "";
  my $hourOptionPresentCrontab = "";
  my $minuteOptionPresentCrontab = "";

  if(defined $crontabEntry)
  {
    my @optionsPresentCrontab = split / /, $crontabEntry;
    
    $dayOptionPresentCrontab = $optionsPresentCrontab[4];
    $hourOptionPresentCrontab = $optionsPresentCrontab[1];
    $minuteOptionPresentCrontab = $optionsPresentCrontab[0];

    my @dayOptionsPresentCrontab = split /,/, $dayOptionPresentCrontab;
    
    $dayOptionPresentCrontab = undef;
    
    %reverseHashDays = reverse %hashDays;

    for(my $index = 0; $index <= $#dayOptionsPresentCrontab; $index++)
    {
      $dayOptionsPresentCrontab[$index] = $reverseHashDays{$dayOptionsPresentCrontab[$index]};
    }

    $dayOptionPresentCrontab = join ",", @dayOptionsPresentCrontab;
  }

  printAddCrontabMenu();
  getDays(\$dayOptionPresentCrontab);
  getHour(\$hourOptionPresentCrontab);
  getMinute(\$minuteOptionPresentCrontab);
  createCrontabEntry();
  writeToCrontab();
 
  my @daysEntered = split /,/, $choice;
  
  if($mainMenuChoice == 1)
  {
    print "\n Backup Job has been successfully scheduled on";
      
    foreach my $value (@daysEntered)
    {
      print " $hashDays{$value}";
    }

    print " at $hour:$minute. \n\n";
  }
  elsif($mainMenuChoice == 2)
  { 
    my @daysEnteredCrontab = split /,/, $dayOptionPresentCrontab;

    print "\n Backup Job has been successfully modified from";
   
    foreach my $value (@daysEnteredCrontab)
    {
      print " $hashDays{$value}";
    }

    print " at $hourOptionPresentCrontab:$minuteOptionPresentCrontab to";
      
    foreach my $value (@daysEntered)
    {
      print " $hashDays{$value}";
    }

    print " at $hour:$minute. \n\n";
  }
  else
  {
  }
}

######################################
#Subroutine to print Main Menu choice#
######################################
sub printMainMenu()
{
  system("clear");

  print "\n Enter Option \n";
  print " \n";
  print " 1 -> SCHEDULE BACKUP JOB \n";
  print " 2 -> EDIT SCHEDULED BACKUP JOB \n";
  print " 3 -> DELETE SCHEDULED BACKUP JOB \n";
  print " \n";
}

#############################
#Subroutine to get Main Menu#
#choice from user           #
#############################
sub getMainMenuChoice()
{
  while(!defined $mainMenuChoice)
  {
    print " Enter your choice : ";
    $mainMenuChoice = <>;
    chop $mainMenuChoice;

    $mainMenuChoice =~ s/^\s+//;
    $mainMenuChoice =~ s/\s+$//;

    if($mainMenuChoice =~ m/^\d$/)
    {
      if($mainMenuChoice < 1 || $mainMenuChoice > 3)
      {
        $mainMenuChoice = undef;
      } 
    }
    else
    {
      $mainMenuChoice = undef;
    }
  }
}

################################
#Subroutine to get confirmation# 
#choice from user              #
################################
sub getConfirmationChoice()
{
  while(!defined $confirmationChoice)
  {
    print " Enter your choice : ";
    $confirmationChoice = <>;
    chop $confirmationChoice;

    $confirmationChoice =~ s/^\s+//;
    $confirmationChoice =~ s/\s+$//;

    if($confirmationChoice =~ m/^\w$/ && $confirmationChoice !~ m/^\d$/)
    {
      if($confirmationChoice eq "y" ||
         $confirmationChoice eq "Y" ||
         $confirmationChoice eq "n" ||
         $confirmationChoice eq "N")
      {
      }
      else
      {
        $confirmationChoice = undef;
      } 
    }
    else
    {
      $confirmationChoice = undef;
    }
  }
  
  print "\n";
}

##################################
#Subroutine to print the menu for#
#adding an entry to crontab      #
##################################
sub printAddCrontabMenu()
{
  system("clear");

  print "\n Enter the Day(s) of Week for the Scheduled Backup Job \n";
  print " Note: Use comma separation for selecting multiple days (E.g. 1,3,5) \n";
  print " \n";
  print " 1 -> MON \n";
  print " 2 -> TUE \n";
  print " 3 -> WED \n";
  print " 4 -> THU \n";
  print " 5 -> FRI \n";
  print " 6 -> SAT \n";
  print " 7 -> SUN \n";
  print " \n";
}

####################################
#Subroutine to get the days of week#
#when the backup job should be     #
#executed                          #
####################################
sub getDays()
{
  if(${$_[0]} ne "")
  {
    print " Previous choice : ${$_[0]} \n";
  }

  while(!defined $choice)
  {
    print " Enter your choice : ";
    
    $choice = <>;
    chop $choice;

    $choice =~ s/^\s+//;
    $choice =~ s/\s+$//;

    if($choice =~ m/^(\d,)*\d$/)
    {
      @options = split /,/, $choice;

      $numArguments = $#options + 1;

      if($numArguments > 7)
      {
        $choice = undef;
        @options = ();
      }
      else
      {
        my $duplicateExists = checkDuplicatesArray(\@options);

        if($duplicateExists)
        {
          $choice = undef;
          @options = ();
        }
        else
        {
          my $entry;

          foreach $entry (@options)
          {
            if($entry < 1 || $entry > 7)
            {
              $choice = undef;
              @options = ();
              last;
            }
          } 
        }
      } 
    }
    else
    {
      $choice = undef;
    }
  }
}

####################################
#Subroutine to get the hour        #
#when the backup job should be     #
#executed                          #
####################################
sub getHour()
{
  print "\n Enter Time of Day when Backup Script is supposed to be run \n\n";

  if(${$_[0]} ne "")
  {
    print " Previously entered Hour : ${$_[0]} \n";
  }

  while(!defined $hour)
  { 
    print " Enter Hour (0-23) : ";

    $hour = <>;

    chop $hour;

    $hour =~ s/^\s+//;
    $hour =~ s/\s+$//;
  
    if($hour eq "")
    {
      $hour = undef;
    }
    elsif($hour =~ m/\D/)
    {
      $hour = undef;
    }
    elsif(length $hour > 2)
    {
      $hour = undef;
    }
    elsif($hour < 0 || $hour > 23)
    {
      $hour = undef;
    }
    else
    {
      if(length $hour > 1 && $hour =~ m/^0/)
      {
        $hour = substr $hour, 1;  
        last;         
      }
    }
  }
}

####################################
#Subroutine to get the minute      #
#when the backup job should be     #
#executed                          #
####################################
sub getMinute()
{
  print "\n";

  if(${$_[0]} ne "")
  {
    print " Previously entered Minute : ${$_[0]} \n";
  }

  while(!defined $minute)
  { 
    print " Enter Minute (0-59) : ";

    $minute = <>;

    chop $minute;

    $minute =~ s/^\s+//;
    $minute =~ s/\s+$//;
  
    if($minute eq "")
    {
      $minute = undef;
    }
    elsif($minute =~ m/\D/)
    {
      $minute = undef;
    }
    elsif(length $minute > 2)
    {
      $minute = undef;
    }
    elsif($minute < 0 || $minute > 59)
    {
      $minute = undef;
    }
    else
    {
      if(length $minute == 1)
      {
        $minute = "0".$minute;  
        last;         
      }
    }
  }

  print "\n";
}

#####################################
#Subroutine to check if the same day#
#has been entered more than once by #
#the user                           #
#####################################
sub checkDuplicatesArray()
{
  my $retVal = false;
  my @originalArray = @{$_[0]};  
  my %optionsHash = ();

  foreach $var (@originalArray)
  {
    if(exists $optionsHash{$var}) 
    {
       $optionsHash{$var}++;
    }
    else
    {
       $optionsHash{$var} = 1;
    }
  }  

  while(($key,$value) = each(%optionsHash))
  {
    if($value > 1) 
    {
       $retVal = true;
       last;
    }
  }

  return $retVal;
}

##########################
#Subroutine to create the# 
#string to be entered    #
#into crontab            #
##########################
sub createCrontabEntry()
{
  $entryCrontabString  = $minute;
  $entryCrontabString .= " ";
  $entryCrontabString .= $hour;
  $entryCrontabString .= " ";
  $entryCrontabString .= "*";
  $entryCrontabString .= " ";
  $entryCrontabString .= "*";
  $entryCrontabString .= " ";

  if($numArguments == 1)
  {
    $entryCrontabString .= $hashDays{$options[$numArguments - 1]};
  }
  else
  {
    for(my $index=0; $index<$numArguments - 1; $index++)
    {
      $entryCrontabString .= $hashDays{$options[$index]};
      $entryCrontabString .= ",";
    }

    $entryCrontabString .= $hashDays{$options[$numArguments - 1]};
  }  

  $entryCrontabString .= " ";
  $entryCrontabString .= $superUser;

  $entryCrontabString .= " ";
  $entryCrontabString .= $backupScriptPath;

  $entryCrontabString .= "\n";
	print $entryCrontabString;
}

#######################################
#Subroutine to check if crontab has an# 
#existing backup job corresponding to #
#the backup script                    #
#######################################
sub checkEntryExistsCrontab()
{
  @linesCrontab = ();
  readFromCrontab();

  foreach my $line (@linesCrontab)
  {
    if($line =~ m/$backupScriptName/)
    {
      $crontabEntry = $line;
      return true;
    }
  }

  return false;
}

#######################################
#Subroutine to remove an existing     # 
#backup job from crontab corresponding# 
#to the backup script                 #
#######################################
sub removeEntryFromCrontab()
{
  @linesCrontab = grep !/$backupScriptName/, @linesCrontab;

  open CRONTABFILE, ">", $crontabFilePath or (print $tHandle "$lineFeed Crontab File does not exist :$! $lineFeed" and die);
  print CRONTABFILE @linesCrontab;
  close CRONTABFILE;
}

##########################
#Read entire crontab file#
##########################
sub readFromCrontab()
{
  open CRONTABFILE, "<", $crontabFilePath or (print $tHandle "$lineFeed Crontab File does not exist :$! $lineFeed" and die);
  @linesCrontab = <CRONTABFILE>;  
  close CRONTABFILE;
}

#################################
#Append an entry to crontab file#
#################################
sub writeToCrontab()
{
  open CRONTABFILE, ">>", $crontabFilePath or (print $tHandle "$lineFeed Crontab File does not exist :$! $lineFeed" and die);
  print CRONTABFILE $entryCrontabString;
  close CRONTABFILE;
}
