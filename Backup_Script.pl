#!/usr/bin/perl
require 'header.pl';
use Fcntl;
use Tie::File;
use threads;
use threads::shared;
use File::Path;
use FileHandle;
use Sys::Hostname;

use constant false => 0;
use constant true => 1;

use constant CHILD_PROCESS_STARTED => 1;
use constant CHILD_PROCESS_COMPLETED => 2;

use constant FILE_COUNT_THREAD_STARTED => 1;
use constant FILE_COUNT_THREAD_COMPLETED => 2;

#######################################################################
# $appTypeSupport should be ibackup for ibackup and idrive for idrive#
# $appType should be IBackup for ibackup and IDrive for idrive        #
#######################################################################
my ($appTypeSupport,$appType) = getAppType();

my $periodOperator = ".";
my $pathSeparator = "/";
my $serverAddressOperator = "@";
my $serverNameOperator = "::";

my $operationComplete = "100";

my $errorRedirection = "2>&1";

my $serverName = "home";

##################
#Output File Name#
##################
my $outputFileName = "BACKUP";

#################
#Error File Name#
#################
my $errorFileName = "BACKUP_ERRORFILE";

##################
#Output File Path#
##################
my $outputFilePath = undef;

#################
#Error File Path#
#################
my $errorFilePath = undef;

my $outputThread = undef;

my $fileCountThread = undef;

#################################
#Indicates whether child process#
#has started/completed          #
#################################
my $childProcessStatus : shared;
$childProcessStatus = undef;

#######################################
#Indicates whether the thread counting#
#the number of files to be backed up  #
#has started/completed                #
#######################################
my $fileCountThreadStatus : shared;
$fileCountThreadStatus = undef;

my $errorFilePresent = false;

#####################################
#Indicates whether the script should#
#retry the backup operation         #
#####################################
my $retryAttempt = false;

my $defaultEncryptionKey = "DEFAULT";
my $privateEncryptionKey = "PRIVATE";

###########################################
#Array containing the characters which    #
#should not be present in a Directory name#
###########################################
my @invalidCharsDirName = ("/",">","<","|",":","&");

my $invalidCharPresent = false;

###############################
#Configuration File Parameters#
###############################
my @arrayParameters = ( 
                        "USERNAME",
                        "PASSWORD",
                        "LOGDIR",
                        "ENCTYPE",
                        "PVTKEY",
                        "BACKUPSETFILEPATH",
                        "NOTIFICATIONFLAG",
                        "EMAILADDRESS",
                        "ACCOUNT_CONFIG",
                        "EXCLUDELISTFILEPATH",
			"BACKUPLOCATION",
			"RETAINLOGS",
			"BWTHROTTLE"
                      );

###############################
#Hash to hold the values of   #
#Configuration File Parameters#
###############################
my %hashParameters = ( 
                       "USERNAME" => undef,
                       "PASSWORD" => undef,
                       "LOGDIR" => undef,
                       "ENCTYPE" => undef,
                       "PVTKEY" => undef,
                       "BACKUPSETFILEPATH" => undef,
                       "NOTIFICATIONFLAG" => undef,
                       "EMAILADDRESS" => undef,
                       "ACCOUNT_CONFIG" => undef,
                       "EXCLUDELISTFILEPATH" => undef,
		       "BACKUPLOCATION" => undef,
		       "RETAINLOGS" => undef,
		       "BWTHROTTLE" => undef
                     );

##########################
#Name of idevsutil binary#
##########################
my $idevsutilBinaryName = "idevsutil";

##########################
#Path of idevsutil binary#
##########################
my $idevsutilBinaryPath = "./idevsutil";

##########################################
#Command to be passed to idevsutil binary#
##########################################
my $idevsutilCommandLine = undef;

############################################
#Arguments to be passed to idevsutil binary# 
############################################
my @idevsutilArguments = (
                          "--password-file",
                          "--config-account",
                          "--enc-type",
                          "--pvt-key",
                          "--user",
                          "--files-from",
                          "--type",
                          "--utf8-cmd",
			  "--encode",
			  "--proxy",
			  "--bw-file"
                         );

##########################################
#Arguments to be passed for generation of# 
#temporary output file and temporary     #
#error file                              #
##########################################
my @OutErrorArguments = ("--o",
                         "--e"
                        );

##########################################
#Array to hold temporary output file path#
#and temporary error file path           #
##########################################
my @OutErrorFilePaths = ("./output.txt",
                         "./error.txt"
                        );

############################################
#Errors encountered during backup operation# 
#for which the script should retry the     #
#backup operation                          #
############################################
my @ErrorArgumentsRetry = ("idevs error",
                           "io timeout",
                           "Operation timed out",
                           "nodename nor servname provided, or not known",
                           "failed to connect",
                           "Connection refused"
                          );
  
############################################
#Errors encountered during backup operation#
#for which the script should not retry the #
#backup operation                          #
############################################
my @ErrorArgumentsNoRetry = ("failed: No such file or directory",
                             "File name too long",
                             "SFERROR",
                             "IOERROR",
                             "mkstemp",
                             "encryption verification failed",
                             "some files could not be transferred due to quota over limit",
                             "skipped-over limit",
                             "account is under maintenance",
                             "account has been cancelled",
                             "account has been expired",
                             "protocol version mismatch",
                             "password mismatch",
                             "out of memory",
                             "failed verification -- update"
                            );

#############################
#Process ID of child process#
#############################
my $pid = undef;

my $lineCount;
my $prevLineCount;

my $cancelFlag = false;

###############################################
#Hash containing items present in Exclude List#
###############################################
%backupExcludeHash = ();

##################################################
#Array containing items present in Backupset File#
##################################################
@backupIncludeArray = ();

#################################################################################
#Array containing Backupset File items enumerated by comparing with Exclude List#
#################################################################################
@outputBackupsetDerivedList = ();

###################################################
#Array containing directory names which have to be#
#traversed for obtaining the count of files to be #
#considered for backup                            #
###################################################
my @dirArray : shared;
@dirArray = ();

############################################
#Total count of files considered for backup#
############################################
my $filesConsideredBackupCount : shared;
$filesConsideredBackupCount = 0;

######################################################
#Hash containing file names which have been backed up#
######################################################
my %fileBackupHash : shared;
%fileBackupHash = ();

##############################################
#Hash containing file names which are in sync#
##############################################
my %fileSyncHash : shared;
%fileSyncHash = ();

####################################################
#Hash containing file names which encountered error# 
#during backup                                     #
####################################################
my %fileErrorHash : shared;
%fileErrorHash = ();

##########################################
#Count of files which have been backed up#
##########################################
my $numEntriesFileBackupHash = 0;

##################################
#Count of files which are in sync#
##################################
my $numEntriesFileSyncHash = 0;

###################################
#Count of files which could not be# 
#backed up/synced due to          # 
#specified errors                 #
###################################
my $numEntriesFileErrorHash = 0;

###################################
#Count of files which could not be#
#backed up/synced due to          #
#unspecified errors               #
###################################
my $countOtherErrors = 0;

######################################
#Total count of files which could not#
#be backed up/synced                 #
######################################
my $countTotalErrors = 0;

################################
#Temporary directory created by#
#idevsutil binary              #
################################
my $evsTempDirPath = "./evs_temp";

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

########################################
#Maximum number of times the script    #
#should try to backup in case of errors#
########################################
my $maxNumRetryAttempts = 5;

##############################################
#Subroutine that processes SIGINT and SIGTERM#
#signal received by the script during backup #
##############################################
$SIG{INT} = \&process_term;
$SIG{TERM} = \&process_term;
getParameterValue(\$arrayParameters[3], \$hashParameters{$arrayParameters[3]});
my $encType = $hashParameters{$arrayParameters[3]};

if(${ARGV[0]} eq 1){
	$pwdPath = $pwdPath."_SCH";
	$pvtPath = $pvtPath."_SCH";
	print $tHandle "Backup_Script.pl: Scheduler job is running. $lineFeed";
}

if(! -e $pwdPath or ($encType eq "PRIVATE" and ! -e $pvtPath)){
	print "Please login to your $appType account using login.pl and try again \n";
	system("/usr/bin/perl logout.pl 1"); 
	exit(1);
}

# Trace Log Entry #
my $curFile = basename(__FILE__);
print $tHandle "$lineFeed File: $curFile $lineFeed",
                "---------------------------------------- $lineFeed";

getParameterValue(\$arrayParameters[7], \$hashParameters{$arrayParameters[7]});
getParameterValue(\$arrayParameters[1],\$hashParameters{$arrayParameters[1]});

my $backupUtf8File = "$currentDir/$userName/.backupUtf8.txt";

my $bwPath = "$currentDir/$userName/.bw.txt";
getParameterValue(\$arrayParameters[12], \$hashParameters{$arrayParameters[12]});
createRemoveBWFile();

getParameterValue(\$arrayParameters[10],\$hashParameters{$arrayParameters[10]});
my $host = $hashParameters{$arrayParameters[10]};
if($host eq ""){
	$host = hostname;
}

open FILE, "<", $serverfile or (print $tHandle "$lineFeed Could not open file $serverfile , Reason:$! $lineFeed" and die);
$serverAddress = <FILE>;
chomp($serverAddress);
createLogFiles();
getParameterValue(\$arrayParameters[4], \$hashParameters{$arrayParameters[4]});

getParameterValue(\$arrayParameters[5], \$hashParameters{$arrayParameters[5]});
getParameterValue(\$arrayParameters[9], \$hashParameters{$arrayParameters[9]});

getCountFilesConsideredBackup(\$hashParameters{$arrayParameters[5]}, \$hashParameters{$arrayParameters[9]});

doBackupOperation(\$hashParameters{$arrayParameters[5]});

##############################################
#In case of error, retry the backup operation#
##############################################
if($retryAttempt)
{
  $errorFilePresent = false;
  $retryAttempt = false;

  for($index = 1; $index <= $maxNumRetryAttempts; $index++)
  {
    sleep 120;

    if(open(OUTFILE, "> $outputFilePath"))    {
      close OUTFILE;
    }
    else{
      print $tHandle "Could not open $outputFilePath, Reason:$! $lineFeed";
    }

    if(open(ERRORFILE, "> $errorFilePath")){
      close ERRORFILE;
    }
    else{
      print $tHandle "Could not open $errorFilePath, Reason:$! $lineFeed";
    } 
    doBackupOperation(\$hashParameters{$arrayParameters[5]});

    if(!$retryAttempt)
    {
      last;
    }
    else
    {
      $errorFilePresent = false;
      $retryAttempt = false;
    }
  }
}

writeBackupSummary();
appendErrorFileContents();   
cleanProgressFile();
restoreBackupsetFileConfiguration();
sendMail("BACKUP");

terminateStatusRetrievalScript();

#****************************************************************************************************
# Subroutine Name         : createRemoveBWFile.
# Objective               : Create bandwidth throttle value file(.bw.txt). 
# Added By                : Avinash Kumar.
#*****************************************************************************************************/
sub createRemoveBWFile()
{
	if(defined $hashParameters{$arrayParameters[12]} and $hashParameters{$arrayParameters[12]} =~ m/^\d+$/ and 0 <= $hashParameters{$arrayParameters[12]} and 100 > $hashParameters{$arrayParameters[12]})
	{
        	open BWFH, ">", $bwPath or (print $tHandle "$lineFeed Could not open file $bwPath , Reason:$! $lineFeed" and die);
        	print BWFH $hashParameters{$arrayParameters[12]};
        	close BWFH;
	}
	elsif(-e $bwPath)
	{
        	unlink $bwPath;
	}
}

##############################################################
#This subroutine creates the Log Directory if not present    #
#It also creates the Error Log and  Output Log files         #
#It also clears the content of the Progress Details file     #
#                                                            #
#The Error Log and Output Log files are created based on     #
#the timestamp when the backup operation was started         #
##############################################################
sub createLogFiles()
{
    $workingDir = $currentDir;
    $workingDir =~ s/ /\ /g;

    $logDir = "$workingDir/$userName/LOGS";

# Check RETAINLOG field of CONFIG file
  getParameterValue(\$arrayParameters[11], \$hashParameters{$arrayParameters[11]});
  if($hashParameters{$arrayParameters[11]} eq "NO"){
	`rm -rf ${$_[0]}`;
  }

  if(-d $logDir)
  {
  }
  else
  {
    mkdir $logDir;
  }
    
  my $currentTime = localtime;
  my $outputFile = $logDir.$pathSeparator.$outputFileName.$whiteSpace.$currentTime; 
  my $errorFile = $logDir.$pathSeparator.$errorFileName.$whiteSpace.$currentTime;

  $outputFilePath = $outputFile; 
  $errorFilePath = $errorFile;

  if (sysopen(OUTFILE, $outputFile, O_RDWR|O_EXCL|O_CREAT, 0666)){
  	close OUTFILE;
  }

  if (sysopen(ERRORFILE, $errorFile, O_RDWR|O_EXCL|O_CREAT, 0666)){
  	close ERRORFILE;
  }

  $ProgressDetailsFilePath = $logDir.$pathSeparator.
                             $ProgressDetailsFileName;

  if (open(PROGRESSFILE, "> $ProgressDetailsFilePath")){
  	close PROGRESSFILE;
  }
}


########################################################
#This subroutine reads the entries in BackupsetFile and# 
#counts the number of files which have to be backed up #
########################################################
sub getCountFilesConsideredBackup()
{
  ${$_[0]} =~ s/ /\ /g;
  ${$_[1]} =~ s/ /\ /g;
 
  if(defined ${$_[0]} and
             ${$_[0]} ne "")
  {
    if(-e ${$_[0]})
    {
      my $BackupsetOriginalFile = ${$_[0]}.".org";
      my $BackupsetTempFile = ${$_[0]}.".tmp";

      if (sysopen(BACKUPSET_TEMP_FILE_HANDLE, $BackupsetTempFile, O_RDWR|O_EXCL|O_CREAT, 0666)) {  
	     if(open(BACKUPSETFILE_HANDLE, ${$_[0]})){
	      	while(my $entry = <BACKUPSETFILE_HANDLE>)
      	      	{
	        	if($entry =~ m/^$/)
        		{
        		}
		        elsif($entry =~ m/^[\s\t]+$/)
        		{
	        	}
	        	else
        		{
	        	  $entry =~ s/^\s+//;
	        	  $entry =~ s/\s+$/\n/;

		          my $firstChar = substr($entry, 0, 1);
        		  my $secondChar = substr($entry, 1, 1); 

		          if($firstChar eq $periodOperator)
        		  {
	        	    if($secondChar eq $periodOperator)
        	    	    {
		              my $parentDir = Cwd::realpath('..');
        		      $entry = $parentDir . substr($entry, 2);
            		    }
	            	    else
        	    	    {
		              $entry = $currentDir . substr($entry, 1);
        		    }
          		  }

		          print BACKUPSET_TEMP_FILE_HANDLE $entry;
			}
                }#end of while
	
	      	close BACKUPSETFILE_HANDLE;
             }  
             else
             {
	  	print $tHandle "Could not open file $BackupsetFile, Reason:$! $lineFeed";
             }
	     close BACKUPSET_TEMP_FILE_HANDLE;
      }
      else
      {
        print $tHandle "Could not create $BackupsetTempFile, Reason:$! $lineFeed";
      }

      rename ${$_[0]}, $BackupsetOriginalFile;
      rename $BackupsetTempFile, ${$_[0]};

      if(defined ${$_[1]} and
                 ${$_[1]} ne "")
      {
        if(-e ${$_[1]} and -s ${$_[1]} > 0)
        {
	  if(open(EXCLUDE_FILE_HANDLE, ${$_[1]})){          
          	while (my $item = <EXCLUDE_FILE_HANDLE>) 
          	{
	            if($item =~ m/^$/)
        	    {
            	    }
	            elsif($item =~ m/^[\s\t]+$/)
        	    {
            	    }
	            else
        	    {
		      chomp $item;
		      $item =~ s/^\s+//;   
		      $item =~ s/\s+$//;  
	
		      $backupExcludeHash{$item} = 1;
            	    }
          	}
          
          	close(EXCLUDE_FILE_HANDLE);
	  }
	  else
	  {
		print $tHandle "$lineFeed Could not open ${$_[1]}, Reason:$! $lineFeed"; 
	  }

	  if(open(BACKUPSETFILE_HANDLE, ${$_[0]}))
	  {
          	while(my $entry = <BACKUPSETFILE_HANDLE>)
          	{
	            chomp $entry;
        	    $entry =~ s/ /\ /g;
 
	            if($entry =~ m/^$/)
        	    {
            	    }
	            else
        	    {
	              my $firstChar = substr($entry, 0, 1);

        	      if($firstChar ne $pathSeparator)
              	      {
	                $entry = $pathSeparator.$entry;
                      }

	              if(-l $entry or -p $entry or -S $entry or -b $entry or -c $entry or -t $entry)
        	      {
              	      }
	              else
        	      {
                	push @backupIncludeArray, $entry;
	              }
        	    }
          	}
          	close(BACKUPSETFILE_HANDLE);
	  }
	  else
	  {
		print $tHandle "$lineFeed Could not open ${$_[0]}, Reason:$! $lineFeed";
  	  }

          foreach my $file (@backupIncludeArray) 
          {
	    if ( -d $file ) 
	    {
	      if(exists $backupExcludeHash{$file})
              {
	        next;
	      }
	
              listFiles($file);
	    }
	    else 
	    {
	      if(exists $backupExcludeHash{$file})
              {
	        next;
	      }
	  
              push(@outputBackupsetDerivedList,$file);
	    }
          }

          my $BackupsetBaseFile = ${$_[0]}.".base";
          my $BackupsetDerivedFile = ${$_[0]}.".derived";

  	  if(open(FILEHANDLE, ">", "$BackupsetDerivedFile"))  
	  {
          	foreach my $itemList (@outputBackupsetDerivedList)
          	{
		    chomp $itemList;
        	    $itemList = $itemList . $lineFeed;

		    print FILEHANDLE $itemList; 
        	}
	        close FILEHANDLE;
	  }
	  else
	  {
		print $tHandle "$lineFeed Could not open $BackupsetDerivedFile, Reason:$! $lineFeed";
 	  }

          rename ${$_[0]}, $BackupsetBaseFile;
          rename $BackupsetDerivedFile, ${$_[0]};
        }
      }     
      
      $fileCountThread = threads->create('subFileCountThread', $_[0]);
    }
    else
    {
      if (open(ERRORFILE, ">> $errorFilePath"))
      {
      	autoflush ERRORFILE;

	print ERRORFILE "Backup set file not found, verify the config file parameters.";
      	print ERRORFILE "Read \"ReadMe.txt\" for details. \n";
      	close ERRORFILE;
      }
      else
      {
	print $tHandle "$lineFeed Could not open file $errorFilePath, Reason:$! $lineFeed";
      }
      	appendErrorFileContents();
      sendMail("Backup set file not found, verify the config file parameters.".
               "Read \"ReadMe.txt\" for details.");
 
      exit 1;
    }
  }
  else
  {
    if (open(ERRORFILE, ">> $errorFilePath"))
    {
    	autoflush ERRORFILE;

	print ERRORFILE "Backup set file path is missing in config file.";
    	print ERRORFILE "Read \"ReadMe.txt\" for details. \n";
    	close ERRORFILE;
    }
    else
    {
	print $tHandle "$lineFeed Could not open file $errorFilePath, Reason:$! $lineFeed";
    }
    appendErrorFileContents();
    sendMail("Backup set file path is missing in config file.".
             "Read \"ReadMe.txt\" for details.");
 
    exit 1;
  }
}

#####################################################
#The fileCount thread calls this subroutine to count# 
#the number of files which have to be backed up     #
#####################################################
sub subFileCountThread()
{
  {
    lock $fileCountThreadStatus;
    $fileCountThreadStatus = FILE_COUNT_THREAD_STARTED;
  }

  if(open(BACKUPSETFILE_HANDLE, ${$_[0]}))
  {
  	while(my $entry = <BACKUPSETFILE_HANDLE>)
  	{
	    chomp $entry;
 
	    $entry =~ s/ /\ /g;
 
	    if($entry =~ m/^$/)
    	    {
    	    }
	    else
	    {
	      my $firstChar = substr($entry, 0, 1);

	      if($firstChar ne $pathSeparator)
      	      {
	        $entry = $pathSeparator.$entry;
       	      }

	      if(-l $entry or -p $entry or -S $entry or -b $entry or -c $entry or -t $entry)
      	      {
      	      }
	      else
      	      {
	        if(-d $entry)
        	{
	          push @dirArray, $entry;
        	}  
	        else
        	{
	          $filesConsideredBackupCount++;
        	}
      	      }
    	    }
  	}

	close BACKUPSETFILE_HANDLE;
  }
  else{
	print $tHandle "$lineFeed Could not open file ${$_[0]}, Reason:$! $lineFeed";
  }

  my $iterationCount = 0;

  while(scalar @dirArray != 0)
  {
    if($iterationCount == 20)
    {
      $iterationCount = 0;

      select undef, undef, undef, 0.001;
    }
    else
    {
      $iterationCount++;
    }

    my $dirName = pop @dirArray;
    
    if(opendir DIR, $dirName)
    {
      while(my $dirEntry = readdir(DIR))
      { 
        $dirEntry =~ s/ /\ /g;
        my $dirPath = "$dirName/$dirEntry";   
  
        if($dirEntry eq "." or
           $dirEntry eq "..")
        {
        }
        else
        {
          if(-l $dirPath or -p $dirPath or -S $dirPath or
             -b $dirPath or -c $dirPath or -t $dirPath)
          {
          }
          else
          {
            if(-f $dirPath)
            { 
              $filesConsideredBackupCount++;
            }
            elsif(-d $dirPath)
            { 
              push @dirArray, $dirPath;
            }
            else
            {
            }
          }
        }
      }

      closedir DIR;
    }
  }

  {
    lock $fileCountThreadStatus;
    $fileCountThreadStatus = FILE_COUNT_THREAD_COMPLETED;
  }
}

#################################################################
#This subroutine performs the actual task of backing up files   #
#It creates a child process which executes the backup command   #
#                                                               #
#It also creates an output thread which continuously monitors   #
#the temporary output file.                                     # 
#                                                               #   
#At the end of backup, it inspects the temporary error file     #
#if present.                                                    # 
#                                                               #
#It then deletes the temporary output file, temporary error file#
#and the temporary directory created by idevsutil binary        # 
################################################################# 
sub doBackupOperation()
{
  if(defined ${$_[0]} and
             ${$_[0]} ne "")
  {
    if(-e ${$_[0]})
    {

      if(!defined $hashParameters{$arrayParameters[3]} or 
                  $hashParameters{$arrayParameters[3]} eq "")
      {
        $hashParameters{$arrayParameters[3]} = $defaultEncryptionKey;
      }

      if($hashParameters{$arrayParameters[3]} !~ m/^$defaultEncryptionKey$/i and
         $hashParameters{$arrayParameters[3]} !~ m/^$privateEncryptionKey$/i)
      {
        $hashParameters{$arrayParameters[3]} = $defaultEncryptionKey;
      }
 
	open UTF8FILE, ">", $backupUtf8File or (print $tHandle "Could not open file $backupUtf8File for backup cmd, Reason:$! $lineFeed" and die);
	print UTF8FILE $idevsutilArguments[5].$assignmentOperator.${$_[0]}.$lineFeed,
		       $idevsutilArguments[6].$lineFeed,
		       $idevsutilArguments[0].$assignmentOperator.$pwdPath.$lineFeed;
	if(-e $bwPath)
        {
		print UTF8FILE $idevsutilArguments[10].$assignmentOperator.$bwPath.$lineFeed;
        }
	if($hashParameters{$arrayParameters[3]} =~ m/^$privateEncryptionKey$/i)
	{
		if(! -f $pvtPath)
		{
			createEncodeFile($hashParameters{$arrayParameters[4]}, $pvtPath);
		}
		print UTF8FILE $idevsutilArguments[3].$assignmentOperator.$pvtPath.$lineFeed;
	}
	print UTF8FILE $idevsutilArguments[9].$assignmentOperator.$proxyStr.$lineFeed,
		       $idevsutilArguments[8].$lineFeed,
		       $OutErrorArguments[0].$assignmentOperator.$OutErrorFilePaths[0].$lineFeed,
		       $OutErrorArguments[1].$assignmentOperator.$OutErrorFilePaths[1].$lineFeed,
		       $pathSeparator.$lineFeed,
		       $userName.$serverAddressOperator.
                       $serverAddress.$serverNameOperator.
                       $serverName.$pathSeparator.$host.$pathSeparator.$lineFeed;

	close UTF8FILE;
	open TEMPHANDLE, "<", $backupUtf8File or (print $tHandle "Could not open file $backupUtf8File for Trace $lineFeed");
	@fileContent = <TEMPHANDLE>;
	close TEMPHANDLE;
	print $tHandle "$lineFeed @fileContent $lineFeed";
	$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArguments[7].$assignmentOperator."\"$backupUtf8File\"".$whiteSpace.$errorRedirection;

      $pid = fork();

      if(!defined $pid)
      {
        die "Cannot fork() child process : $!";
      }
      elsif($pid == 0)
      {
        exec($idevsutilCommandLine);

	if (open(ERRORFILE, ">> $errorFilePath"))
	{
        	autoflush ERRORFILE;

	        print ERRORFILE "Unable to proceed the backup operation";
        	print ERRORFILE "Reason : Child process launch failed. \n";
	        close ERRORFILE;
	}
	else
	{
	  print $tHandle "$lineFeed Could not open file $errorFilePath, Reason:$! $lineFeed";
	}
        appendErrorFileContents();
        sendMail("Unable to proceed the backup operation".
                 "Reason : Child process launch failed.");

        exit 1;
      }
      else
      {
        $childProcessStatus = CHILD_PROCESS_STARTED;        

        $outputThread = threads->create('subOutputThread');
          
        waitpid($pid,0);

        {
          lock $childProcessStatus; 
          $childProcessStatus = CHILD_PROCESS_COMPLETED;
        }

	my @joinable = threads->list(threads::joinable);
	my @running = threads->list(threads::running);
	while((scalar @joinable != 0) or (scalar @running != 0)){
		foreach my $thr (@joinable) {
			$thr->join();
		}
		@joinable = threads->list(threads::joinable);
		@running = threads->list(threads::running);
	}
        
	subOutputRoutine();
        subErrorRoutine();

        unlink($OutErrorFilePaths[0]);
	###########################################
        # handling wrong server address error msg #
  	##########################################
	$tempErrorFileSize = -s $OutErrorFilePaths[1];
	if($tempErrorFileSize > 0)
    	{
		my $errorPatternServerAddr = "unauthorized user";
		my $errorPatternPwd = "password mismatch";
                my $errorPatternConfigPwd = "Required param 'password' not passed";

		tie my @array, 'Tie::File', $OutErrorFilePaths[1] or (print $tHandle "$lineFeed Could not open file $OutErrorFilePaths[1], Reason:$! $lineFeed" and die);
	        my $size =  $#array + 1;
        	for(my $index = 0; $index < $size; $index++)
        	{
                	if($array[$index] =~ m/$errorPatternServerAddr/)
                	{
				getServerAddr();
                        	last;
                	}
			if($array[$index] =~ m/$errorPatternPwd/ or $array[$index] =~ m/$errorPatternServerAddr/)
			{
				createEncodeFile($hashParameters{$arrayParameters[1]}, $pwdPath);
				last;
			}
                        
        	}

	}
        unlink($OutErrorFilePaths[1]);
        rmtree($evsTempDirPath);
      }
    }
    else
    {
      if (open(ERRORFILE, ">> $errorFilePath"))
      {
      	autoflush ERRORFILE;

      	print ERRORFILE "Backup set file not found, verify the config file parameters.";
      	print ERRORFILE "Read \"ReadMe.txt\" for details. \n";
      	close ERRORFILE;
      }
      else
      {
          print $tHandle "$lineFeed Could not open file $errorFilePath, Reason:$! $lineFeed";
      }

      appendErrorFileContents();
      sendMail("Backup set file not found, verify the config file parameters.".
               "Read \"ReadMe.txt\" for details.");
 
      exit 1;
    }
  }
  else
  {
    if (open(ERRORFILE, ">> $errorFilePath"))
    {
    	autoflush ERRORFILE;

	print ERRORFILE "Backup set file path is missing in config file.";
    	print ERRORFILE "Read \"ReadMe.txt\" for details. \n";
    	close ERRORFILE;
    }
    else
    {
          print $tHandle "$lineFeed Could not open file $errorFilePath, Reason:$! $lineFeed";
    }
    appendErrorFileContents();
    sendMail("Backup set file path is missing in config file.".
             "Read \"ReadMe.txt\" for details.");
 
    exit 1;
  }
}

################################################################
#The output thread calls this subroutine to continuously       #
#monitor the temporary output file and append entries to       #
#the output file once a file is fully backed up/synced.        #
#                                                              #
#Also entries are added to the progress details file           #
#representing the progress of backup/sync of a particular      # 
#file.                                                         #
#                                                              #
#Also file names are added to the corresponding hashes         #
#representing file backup/sync                                 #
################################################################
sub subOutputThread()
{
  # Flags to determine the status of OUTFILE and PROGRESSFILE respectively
  my $Oflag = 0;
  my $Pflag = 0;

  $lineCount = undef;
  $prevLineCount = undef;

  my $fieldSeparator = "\\] \\[";

  my $iterationCount = 0;
  my $workingDir = $currentDir;
  $workingDir =~ s/ /\ /g;
  $logDir = "$workingDir/$userName/LOGS";

  $ProgressDetailsFilePath = $logDir.$pathSeparator.
                             $ProgressDetailsFileName;

  if(open(OUTFILE, ">> $outputFilePath"))
  {
    autoflush OUTFILE;
    print OUTFILE $lineFeed;
    print OUTFILE "Backup Start Time :";
    print OUTFILE $whiteSpace.localtime;
    print OUTFILE $lineFeed.$lineFeed;
  }
  else
  {
    $Oflag = 1;
    print $tHandle "Could not open file2 $outputFilePath, Reason:$! $lineFeed";
  }
 
  if(open(PROGRESSFILE, ">> $ProgressDetailsFilePath"))
  {    
    autoflush PROGRESSFILE;
  }
  else
  {
    $Pflag = 1;
    print $tHandle "Could not open file $ProgressDetailsFilePath. Reason:$! $lineFeed";
  }

  while($childProcessStatus != CHILD_PROCESS_COMPLETED)
  {
    if($iterationCount == 20)
    {
      $iterationCount = 0;

      select undef, undef, undef, 0.001;
    }
    else
    {
      $iterationCount++;
    }

    if(open(TEMPOUTPUTFILE, "< $OutErrorFilePaths[0]"))
    {
    	my @linesTempOutputFile = <TEMPOUTPUTFILE>;

	$prevLineCount = $lineCount;
    	$lineCount = @linesTempOutputFile;

    	if(defined $lineCount and !defined $prevLineCount)
    	{
      		for(my $cnt = 0; $cnt < $lineCount; $cnt++) 
      		{
		        my $tmpLine = $linesTempOutputFile[$cnt];

		        if($cnt > 4)
		        {
		          if($tmpLine =~ m/^\W/ and $tmpLine !~ m/^$lineFeed/) 
          		  {
		            my @fields = split $fieldSeparator, $tmpLine;

		            for(my $index = 0; $index < $#fields + 1; $index++)
            		    {
		              if($fields[$index] =~ m/^\W/)
              		      {
		                $fields[$index] =~ s/^.//;
              		      }
		              elsif($fields[$index] =~ m/\W$/)
              		      {
		                $fields[$index] =~ s/.$//;
              		      }
		              else
              		      {
		              }

		              $fields[$index] =~ s/^\s+//;
		              $fields[$index] =~ s/\s+$//;
		            }
            
            		    if($fields[3] =~ m/$operationComplete/)
            		    {
		              my $keyString = "$pathSeparator$fields[6]";
              
		              if($fields[5] =~ m/SYNC/)
		              { 
		                if(exists $fileBackupHash{$keyString})
		                {
                		}
		                else
                		{
		                  $fileSyncHash{$keyString} = 1;
                		}
              		      }
		              elsif($fields[5] =~ m/FULL/ or
                		    $fields[5] =~ m/INCREMENTAL/)
		              { 
                		$fileBackupHash{$keyString} = 1;

		                if(exists $fileErrorHash{$keyString})
                		{
		                  delete $fileErrorHash{$keyString};
                		}
		              }	
		              else
		              {
		              }

              		      my $backupFinishTime = localtime;

		              my $fileSize = convertFileSize($fields[0]);              
			      if(!$Oflag){
			              print OUTFILE "[$backupFinishTime][SUCCESS]",
			              		    "[$pathSeparator$fields[6]][$fileSize]".$lineFeed;
			      }
		            }
          		    if(!$Pflag){
			            print PROGRESSFILE "FileName=$pathSeparator$fields[6]".$whiteSpace.
        	        		               "PercentComplete=$fields[3]".$lineFeed; 
			    }
   
          		}
        	}
      	}
    } 
    elsif(defined $lineCount and defined $prevLineCount and $lineCount > $prevLineCount)
    {
      for(my $cnt = $prevLineCount; $cnt < $lineCount; $cnt++)
      {
        my $tmpLine = $linesTempOutputFile[$cnt];

        if($cnt > 4)
        {
          if($tmpLine =~ m/^\W/ and $tmpLine !~ m/^$lineFeed/)
          { 
            my @fields = split $fieldSeparator, $tmpLine;

            for(my $index = 0; $index < $#fields + 1; $index++)
            {
              if($fields[$index] =~ m/^\W/)
              {
                $fields[$index] =~ s/^.//;
              }
              elsif($fields[$index] =~ m/\W$/)
              {
                $fields[$index] =~ s/.$//;
              }
              else
              {
              }

              $fields[$index] =~ s/^\s+//;
              $fields[$index] =~ s/\s+$//;       
            }
           
            if($fields[3] =~ m/$operationComplete/)
            {
              my $keyString = "$pathSeparator$fields[6]";

              if($fields[5] =~ m/SYNC/)
              { 
                if(exists $fileBackupHash{$keyString})
                {
                }
                else
                { 
                  $fileSyncHash{$keyString} = 1;
                }
              }
              elsif($fields[5] =~ m/FULL/ or
                    $fields[5] =~ m/INCREMENTAL/)
              { 
                $fileBackupHash{$keyString} = 1;

                if(exists $fileErrorHash{$keyString})
                {
                  delete $fileErrorHash{$keyString};
                } 
              }
              else
              {
              }

              my $backupFinishTime = localtime;

              my $fileSize = convertFileSize($fields[0]);              
              if(!$Oflag){ 
	              print OUTFILE "[$backupFinishTime][SUCCESS]",
              			    "[$pathSeparator$fields[6]][$fileSize]".$lineFeed;
	      }
            }
	    if(!$Pflag){
	            print PROGRESSFILE "FileName=$pathSeparator$fields[6]".$whiteSpace.
        	                       "PercentComplete=$fields[3]".$lineFeed; 
	    }
          }
        }
      }
    }
    else
    {
    }

    close TEMPOUTPUTFILE;
    }
  }

  close OUTFILE;
  close PROGRESSFILE;
}

#########################################################
#Once the backup ends, this subroutine is called to read# 
#the temporary output file for the last time and append # 
#entries to the output file and progress details file.  #
#                                                       #
#Also file names are added to the corresponding hashes  #
#representing file backup/sync                          #
#########################################################
sub subOutputRoutine()
{
  # Flags to determine the status of OUTFILE and PROGRESSFILE respectively
  my $Oflag = 0;
  my $Pflag = 0;

  my $fieldSeparator = "\\] \\[";

  sleep 5;

  if(open(OUTFILE, ">> $outputFilePath"))
  {
    autoflush OUTFILE;
  }
  else
  {
    $Oflag = 1;
    print $tHandle "$lineFeed Could not open file $outputFilePath, Reason:$! $lineFeed";
  }

  if(open(PROGRESSFILE, ">> $ProgressDetailsFilePath"))
  {    
    autoflush PROGRESSFILE;
  }
  else
  {
    $Pflag = 1;
    print $tHandle "$lineFeed Could not open file $ProgressDetailsFilePath. Reason:$! $lineFeed";
  }  

  if(open(TEMPOUTPUTFILE, "< $OutErrorFilePaths[0]"))
  {
  	my @linesTempOutputFile = <TEMPOUTPUTFILE>;

	$prevLineCount = $lineCount;
	$lineCount = @linesTempOutputFile;

	if(defined $lineCount and defined $prevLineCount and $lineCount > $prevLineCount)
  	{
	    for(my $cnt = $prevLineCount; $cnt < $lineCount; $cnt++) 
    	    {
	      my $tmpLine = $linesTempOutputFile[$cnt];

	      if($cnt > 4)
	      {
        	if($tmpLine =~ m/^\W/ and $tmpLine !~ m/^$lineFeed/)
	        { 
        	  my @fields = split $fieldSeparator, $tmpLine;

	          for(my $index = 0; $index < $#fields + 1; $index++)
        	  {
	            if($fields[$index] =~ m/^\W/)
        	    {
	              $fields[$index] =~ s/^.//;
        	    }
	            elsif($fields[$index] =~ m/\W$/)
        	    {
	              $fields[$index] =~ s/.$//;
        	    }
	            else
        	    {
	            }

        	    $fields[$index] =~ s/^\s+//;
	            $fields[$index] =~ s/\s+$//;       
        	  }
           
	          if($fields[3] =~ m/$operationComplete/)
          	  {
	            my $keyString = "$pathSeparator$fields[6]";

        	    if($fields[5] =~ m/SYNC/)
	            { 
        	      if(exists $fileBackupHash{$keyString})
	              {
        	      }
	              else
        	      { 
                	$fileSyncHash{$keyString} = 1;
	              }
        	    }
	            elsif($fields[5] =~ m/FULL/ or
        	          $fields[5] =~ m/INCREMENTAL/)
	            { 
        	      $fileBackupHash{$keyString} = 1;

	              if(exists $fileErrorHash{$keyString})
        	      {
                	delete $fileErrorHash{$keyString};
	              } 
        	    }
	            else
        	    {
	            }

        	    my $backupFinishTime = localtime;

	            my $fileSize = convertFileSize($fields[0]);              
             	    if(!$Oflag){ 
	        	    print OUTFILE "[$backupFinishTime][SUCCESS]",
	            			  "[$pathSeparator$fields[6]][$fileSize]".$lineFeed;
	            }
	          }
		  if(!$Pflag){
	       		  print PROGRESSFILE "FileName=$pathSeparator$fields[6]".$whiteSpace.
        	          	             "PercentComplete=$fields[3]".$lineFeed; 
		  }
	        }
      	      }
    	}
  }
  else
  {
  }
     close TEMPOUTPUTFILE;
  }
  else
  {
     print $tHandle "$lineFeed Could not open file $OutErrorFilePaths[0], Reason:$! $lineFeed";
  }
  if(!$Oflag)
  {
    close OUTFILE;
  }
  if(!$Pflag)
  {
    close PROGRESSFILE;
  }
}

###########################################################
#This subroutine checks if the temporary error file       #
#is present. If present, it scans the temporary error file#
#                                                         # 
#In case the account is under maintenance / has expired / # 
#has been canceled, the backup job is removed from cron   #
#                                                         # 
#Also file names are added to the hash representing error #
#in file backup/sync in case errors are encountered       #
#while the backup job is in progress                      #
#                                                         #
#Also the subroutine checks for errors for which it should#  
#retry the backup operation                               #
###########################################################
sub subErrorRoutine()
{
  # Flags to determine the status of ERRORFILE and TEMPERRORFILE respectively
  my $Eflag = 0;
  my $Tflag = 0;

  my $pattern = "\\[.+\\]";

  if(open(ERRORFILE, ">> $errorFilePath"))
  {  
    autoflush ERRORFILE;
  }
  else
  {
    $Eflag = 1;
    print $tHandle "Could not open file $errorFilePath, Reason:$! $lineFeed";
  }

  my $errorFileSize = -s $OutErrorFilePaths[1];

  if($errorFileSize > 0)
  {
    $errorFilePresent = true;
  }

  if($errorFilePresent)
  {
    if(open(TEMPERRORFILE, "< $OutErrorFilePaths[1]"))
    {
      @linesTempErrorFile = <TEMPERRORFILE>;
    }
    else
    {
      $Tflag = 1;
      print $tHandle "Could not open file $OutErrorFilePaths[1], Reason:$! $lineFeed";
    }
    
    print $tHandle "$lineFeed Error file content: $lineFeed @linesTempErrorFile $lineFeed";
    print "$lineFeed @linesTempErrorFile $lineFeed";

    for(my $tmpLineIndex = 0; $tmpLineIndex < $#linesTempErrorFile; $tmpLineIndex++) 
    {
      if(!$Eflag)
      {
        print ERRORFILE $linesTempErrorFile[$tmpLineIndex];
      }

      if($linesTempErrorFile[$tmpLineIndex] =~ m/$ErrorArgumentsNoRetry[8]/)
      {
	if(!$Eflag)
	{
         close ERRORFILE;
	}
	if(!$Tflag)
	{
          close TEMPERRORFILE;
	}

        appendErrorFileContents();
        sendMail("Unable to proceed the backup operation.".
                 "Reason : Account is under maintenance.".
                 "Contact $appType support for details.");

        unlink($OutErrorFilePaths[0]);
        unlink($OutErrorFilePaths[1]);
        rmtree($evsTempDirPath);
      
        `./Scheduler_Script.pl 3 y`;
    
        exit 1;
      }
      elsif($linesTempErrorFile[$tmpLineIndex] =~ m/$ErrorArgumentsNoRetry[9]/)
      {
	if(!$Eflag)
	{
         close ERRORFILE;
	}
	if(!$Tflag)
	{
          close TEMPERRORFILE;
	}

        appendErrorFileContents();
        sendMail("Unable to proceed the backup operation.".
                 "Reason : Account is cancelled.");

        unlink($OutErrorFilePaths[0]);
        unlink($OutErrorFilePaths[1]);
        rmtree($evsTempDirPath);
        
        `./Scheduler_Script.pl 3 y`;
    
        exit 1;
      }
      elsif($linesTempErrorFile[$tmpLineIndex] =~ m/$ErrorArgumentsNoRetry[10]/)
      {
	if(!$Eflag)
	{
         close ERRORFILE;
	}
	if(!$Tflag)
	{
          close TEMPERRORFILE;
	}

        appendErrorFileContents();
        sendMail("Unable to proceed the backup operation.".
                 "Reason : Account has expired.");

        unlink($OutErrorFilePaths[0]);
        unlink($OutErrorFilePaths[1]);
        rmtree($evsTempDirPath);
          
        `./Scheduler_Script.pl 3 y`;
    
        exit 1;
      }
      else
      {
      }

      foreach my $arrayEntry ($ErrorArgumentsNoRetry[0],
                              $ErrorArgumentsNoRetry[1],
                              $ErrorArgumentsNoRetry[2],
                              $ErrorArgumentsNoRetry[3],
                              $ErrorArgumentsNoRetry[4])
      {
        if($linesTempErrorFile[$tmpLineIndex] =~ m/$arrayEntry/i)
        {
          if($linesTempErrorFile[$tmpLineIndex] =~ m/$pattern/)
          {
            my $fileName = $&;
            $fileName =~ s/^.//;
            $fileName =~ s/.$//;

            if(exists $fileErrorHash{$fileName})
            {
            }
            else
            {
              $fileErrorHash{$fileName} = 1;
            }
          }

          last; 
        }
      }

      if(!$retryAttempt)
      { 
        foreach my $arrayEntry (@ErrorArgumentsRetry)
        {
          if($linesTempErrorFile[$tmpLineIndex] =~ m/$arrayEntry/i)
          { 
            $retryAttempt = true;
            last;
          }
        }
      }

    }

    if(!$Tflag)
    {
      close TEMPERRORFILE;
    }
    if(!open(TEMPERRORFILE, "< $OutErrorFilePaths[1]"))
    {
      print $tHandle "$lineFeed Could not open file $OutErrorFilePaths[1] $lineFeed";
    }
    else
    {
      $Tflag = 0;
    }

    if($retryAttempt)
    {
      for(my $tmpLineIndex = 0; $tmpLineIndex < $#linesTempErrorFile; $tmpLineIndex++) 
      {
        foreach my $arrayEntry (@ErrorArgumentsNoRetry)
        {
          if($linesTempErrorFile[$tmpLineIndex] =~ m/$arrayEntry/i)
          { 
            $retryAttempt = false;
            last;
          }
        }

        if($retryAttempt == false)
        {
          last;
        } 
      }
    }
    if(!$Tflag)
    {
      close TEMPERRORFILE;
    }
  }

  if(!$Eflag)
  {
    close ERRORFILE;
  }
}

##################################################
#This subroutine converts the file size of a file#
#which has been backed up/synced into human      #  
#readable format                                 #
##################################################
sub convertFileSize()
{
  my $fileSize = $_[0];
  my $fileSpec = "bytes";

  if($fileSize > 1023)
  {
    $fileSize /= 1024;
    $fileSpec = "KB";
  }

  if($fileSize > 1023)
  {
    $fileSize /= 1024;
    $fileSpec = "MB";
  }

  if($fileSize > 1023)
  {
    $fileSize /= 1024;
    $fileSpec = "GB";
  }

  if($fileSize > 1023)
  {
    $fileSize /= 1024;
    $fileSpec = "TB";
  }

  $fileSize = sprintf "%.2f", $fileSize;
  if(0 == ($fileSize - int($fileSize)))
  {
    $fileSize = sprintf("%.0f", $fileSize);
  }
  return $fileSize.$whiteSpace.$fileSpec;
}


###################################################
#The signal handler invoked when SIGINT or SIGTERM#
#signal is received by the script                 #
###################################################
sub process_term()
{
  $cancelFlag = true;

  cancelSubRoutine();
}

#######################################################
#In case the script execution is canceled by the user,#
#the script should terminate the execution of the     #
#binary and perform cleanup operation.                #
#                                                     #
#It should then generate the backup summary report,   #
#append the contents of the error file to the output  #
#file and delete the error file.                      #
#                                                     #
#It should also erase the contents of progress file   #
#and send a mail stating that the backup job has been # 
#canceled by the user                                 # 
#                                                     # 
#It should then terminate the execution of the        #
#Status Retrieval Script in case it is running        #
#######################################################
sub cancelSubRoutine()
{
  `killall $idevsutilBinaryName`;
 
  copyTempErrorFile();

  unlink($OutErrorFilePaths[0]);
  unlink($OutErrorFilePaths[1]);
  rmtree($evsTempDirPath);
  
  writeBackupSummary();
  appendErrorFileContents();
  cleanProgressFile(); 
  restoreBackupsetFileConfiguration();
  sendMail("BACKUP");

  terminateStatusRetrievalScript();

  exit 0;
}

##############################################
#This subroutine writes the backup summary to#
#the output file                             #
##############################################
sub writeBackupSummary()
{
  my $fileCountThreadStatusLocal = $fileCountThreadStatus;

  $numEntriesFileBackupHash = scalar keys %fileBackupHash; 
  $numEntriesFileSyncHash = scalar keys %fileSyncHash;
  $numEntriesFileErrorHash = scalar keys %fileErrorHash;

  if($fileCountThreadStatusLocal == FILE_COUNT_THREAD_COMPLETED)
  {
    $countOtherErrors = $filesConsideredBackupCount - $numEntriesFileBackupHash -
                        $numEntriesFileSyncHash - $numEntriesFileErrorHash;
  }

  $countTotalErrors = $numEntriesFileErrorHash + $countOtherErrors; 

  if($countTotalErrors < 0)
  {
    $countTotalErrors = 0;
  }

  if (open(OUTFILE, ">> $outputFilePath"))
  {
  	print OUTFILE $lineFeed,
  		      "Summary : ",
		      $lineFeed.$lineFeed;

  if($fileCountThreadStatusLocal == FILE_COUNT_THREAD_COMPLETED)
  {
    print OUTFILE "Total files considered for backup : ",
    		   $filesConsideredBackupCount.$lineFeed;
  }

  print OUTFILE "Total files backed up : ",
  		 $numEntriesFileBackupHash.$lineFeed;

  print OUTFILE "Total files in sync : ",
  		 $numEntriesFileSyncHash.$lineFeed;

  print OUTFILE "Total files failed to backup : ",
		 $countTotalErrors.$lineFeed;

  print OUTFILE $lineFeed,
  		"Backup End Time :",
  		$whiteSpace.localtime,
		$lineFeed;
#signal msg handling.
  if($cancelFlag)
  {
    print OUTFILE "Backup failed. Reason: Operation cancelled by user.".$lineFeed;
  }
  close OUTFILE;
  }
  else
  {
    print $tHandle "Could not open file $outputFilePath, Reason:$! $lineFeed";
  }
  unlink($backupUtf8File);
}

#####################################
#This subroutine copies the contents#
#of the temporary error file to the #
#Error File                         #
#####################################
sub copyTempErrorFile()
{
  my $errorFileSize;
  my $tempErrorFileSize;

  my @tempErrorFileContents = ();

  $errorFileSize = -s $errorFilePath;

  if($errorFileSize > 0)
  {
  }
  else
  {
    $tempErrorFileSize = -s $OutErrorFilePaths[1];
 
    if($tempErrorFileSize > 0)
    {
      if (open(TEMP_ERRORFILE, "< $OutErrorFilePaths[1]"))
      {
        @tempErrorFileContents = <TEMP_ERRORFILE>;
        close TEMP_ERRORFILE; 
      }
      else
      {
	print $tHandle "Could not open file $OutErrorFilePaths[1], Reason:$! $lineFeed";
      }

      if (open(ERRORFILE, "> $errorFilePath"))
      {      
      	for(my $index = 0; $index < $#tempErrorFileContents; $index++)
      	{
        	print ERRORFILE $tempErrorFileContents[$index];
      	}

      	close ERRORFILE;
      }
      else
      {
	print $tHandle "Could not open file $errorFilePath, Reason:$! $lineFeed";
      }
    }
  }
}

#############################################
#This subroutine appends the contents of the#
#error file to the output file, in case the #
#error file exists.                         #
#                                           #  
#It then deletes the error file.            #
#############################################
sub appendErrorFileContents()
{
  my $errorFileSize = -s $errorFilePath;

  if($errorFileSize > 0)
  {
    if (open(ERRORFILE, "< $errorFilePath"))
    {
      if (open(OUTFILE, ">> $outputFilePath"))
      {
    	autoflush OUTFILE;

	print OUTFILE $lineFeed,
	              $lineFeed,  
		      "================ERROR REPORT================",
	    	      $lineFeed,
	    	      $lineFeed;

	 while(my $line = <ERRORFILE>)
	 {
	      print OUTFILE $line;
    	 }
	 close OUTFILE;
      }
      else
      {
	print $tHandle "Could not open file $outputFilePath, Reason:$! $lineFeed";
      }
    close ERRORFILE;
    }
    else
    {
      print $tHandle "Could not open file $errorFilePath, Reason:$! $lineFeed";
    }
  }
  
  unlink $errorFilePath;
}



#####################################
#This subroutine erases the contents# 
#of the progress file               #
#####################################
sub cleanProgressFile()
{
  if (open(PROGRESSFILE, "> $ProgressDetailsFilePath"))
  {
    close PROGRESSFILE;
  }
  else
  {
    print $tHandle "Could not open file $ProgressDetailsFilePath, Reason:$! $lineFeed";
  }
}

#################################################
#This subroutine will return all directory/files# 
#in given directory                             #
#################################################
sub listFiles() 
{
  $fileName = $_[0];
  
  if (substr($fileName, -1, 1) ne "/") 
  {
    $fileName .= "/";
  }

  if(opendir(DIR, $fileName))
  {
    foreach my $file (readdir(DIR)) 
    {
      if ( $file eq "." or $file eq ".." or substr( $file, 0, 1 ) eq "." ) 
      {
      }
      else 
      {
	push @backupIncludeArray, $fileName.$file;
      }
    }
	
    closedir(DIR);
  }
}

#########################################
#This subroutine moves the BackupsetFile#
#to the original configuration          #
#########################################
sub restoreBackupsetFileConfiguration()
{
  my $BackupsetOriginalFile = $hashParameters{$arrayParameters[5]}.".org";
  my $BackupsetBaseFile = $hashParameters{$arrayParameters[5]}.".base";
  my $BackupsetDerivedFile = $hashParameters{$arrayParameters[5]}.".derived";

  my $BackupsetFile = $hashParameters{$arrayParameters[5]};
  
  unlink $BackupsetFile;
  unlink $BackupsetBaseFile;
  unlink $BackupsetDerivedFile;

  rename $BackupsetOriginalFile, $BackupsetFile;
}

#################################
#This subroutine terminates the #  
#Status Retrieval script in case# 
#it is running                  #
#################################
sub terminateStatusRetrievalScript()
{
  my $statusScriptName = "Status_Retrieval_Script.pl";
  my $statusScriptCmd = "ps -elf | grep $statusScriptName | grep -v grep";
 
  my $statusScriptRunning = `$statusScriptCmd`; 

  if($statusScriptRunning ne "")
  {
    my @processValues = split /[\s\t]+/, $statusScriptRunning;
    my $pid = $processValues[3];  
 
    kill SIGTERM, $pid;
  }
}

################################################
#This subroutine sends a mail to the user in   #
#case of successful / canceled / failed backup.#
#If Email field is empty in CONFIG file, mail  #
#notification will not be sent.                 #
###############################################
sub sendMail()
{
  my $configEmailAddress = $hashParameters{$arrayParameters[7]}; 
  if($configEmailAddress ne ""){ 
  	if(validEmailAddress(\$configEmailAddress))
  	{ 
	    my $successFlag = false;
	    my $partialSuccessFlag = false;
    
	    my $sender = "support\@$appTypeSupport.com";
	    my $recipient = $hashParameters{$arrayParameters[7]};

	    my $subjectLine = "";
	    my $content = "";

	    if($_[0] eq "BACKUP")
	    {
	      my $numFilesBackedup = $numEntriesFileBackupHash +
        	                     $numEntriesFileSyncHash;  
	

	      my $fileCountThreadStatusLocal = $fileCountThreadStatus;

	      if($fileCountThreadStatusLocal == FILE_COUNT_THREAD_COMPLETED)
	      {
        	$subjectLine = "Scheduled Backup Email Notification ".
                	       "[$userName]".
                       		"[Backed up files:$numFilesBackedup of $filesConsideredBackupCount]";
	      }
	      else
	      {
	        $subjectLine = "Scheduled Backup Email Notification ".
        	               "[$userName]".
                	       "[Backed up files:$numFilesBackedup]";
	      }

	      if($cancelFlag)
	      {
	        $subjectLine .= "[Failed Backup]";
	      }
	      else
	      {
	        if($countTotalErrors == 0)
	        {
        	  $subjectLine .= "[Successful Backup]";
	          $successFlag = true;
	        }
	        else
	        {
        	  if($fileCountThreadStatusLocal == FILE_COUNT_THREAD_COMPLETED)
	          {
        	    if(($countTotalErrors/$filesConsideredBackupCount)*100 <= 5) 
	            {
	              $subjectLine .= "[Successful Backup*]";
        	      $partialSuccessFlag = true;
	            }
        	    else
	            {
        	      $subjectLine .= "[Failed Backup]";
	            }
        	  }
	          else
        	  {
	            $subjectLine .= "[Successful Backup*]";
        	    $partialSuccessFlag = true;
	          }
	        }
	      }

	      $content = "Dear $appType User, \n\n";
	      $content .= "Ref : Username - $userName \n";
	      $content .= "Computer Name : $host \n\n"; 

	      $content .= "Your scheduled Backup has ";

	      if($successFlag or $partialSuccessFlag)
	      {
	        $content .= "succeeded \n\n";
	      }
	      else
	      {
        	$content .= "failed \n\n";
	      }

	      if($cancelFlag)
	      {
        	$content .= "Reason : Operation cancelled by user. \n\n";
	      }
	      else
	      {
        	$content .= "Please see the Log File at $outputFilePath \n\n";
	      }

	      open OUTFILE, "<", $outputFilePath;
           
	      my $pattern = "\\[";
 
	      while(my $line = <OUTFILE>)
	      {
	        if($line !~ m/ERROR REPORT/)
	        {
        	  if($line !~ m/$pattern/)
	          {
        	    $content .= $line;
	          }
        	}
	      }

	      close OUTFILE;

	      if($partialSuccessFlag)
	      {
        	$content .= "\n";
	        $content .= "Note: Successful Backup* denotes \'mostly success\' ";
        	$content .= "or \'majority of files are successfully backed up\'";
	        $content .= "\n\n";
	      } 
	    }
	    else
	    {
	      $subjectLine = "Subject: Scheduled Backup Email Notification ".
        	             "[$userName]".
                	     "[Failed Backup]";

	      $content = "Dear $appType User, \n\n";
	      $content .= "Ref : Username - $userName \n";
	      $content .= "Computer Name : $host \n\n"; 

	      $content .= "Your scheduled Backup has failed \n\n";
	      $content .= "as ";

	      $content .= $_[0];

	      $content .= "\n\n";
	    }

	    $content .= "Regards, \n";

	    $content .= "$appType Support.";

	    open MAIL, "|/usr/sbin/sendmail -t";

	    print MAIL "To: $recipient\n";
	    print MAIL "From: $sender\n";
	    print MAIL "Subject: $subjectLine\n\n";
	    print MAIL $content;

	    close MAIL;
	  }
	  else
	  {
	    open ERRORFILE, ">>", $errorFilePath;
	    autoflush ERRORFILE;

	    print ERRORFILE "INVALID EMAIL ADDRESS FORMAT \n";
	    close ERRORFILE;

	    appendErrorFileContents();
	  }
  }
}
################################################
#This subroutine validates the email address   #
#provided by the user in the configuration file#
################################################
sub validEmailAddress()
{
  my $emailAddress = ${$_[0]};

  if($emailAddress =~ /(@.*@)|(\.\.)|(@\.)|(\.@)|(^\.)/ or
     $emailAddress !~ /^.+\@(\[?)[a-zA-Z0-9\-\.]+\.([a-zA-Z]{2,3}|[0-9]{1,3})(\]?)$/)
  {
    return 0;
  } 
  else
  {
    return 1;
  }
}

