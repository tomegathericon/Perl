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
my $outputFileName = "RESTORE";

#################
#Error File Name#
#################
my $errorFileName = "RESTORE_ERRORFILE";

##################
#Output File Path#
##################
my $outputFilePath = undef;

#################
#Error File Path#
#################
my $errorFilePath = undef;

my $outputThread = undef;

#################################
#Indicates whether child process#
#has started/completed          #
#################################
my $childProcessStatus : shared;
$childProcessStatus = undef;

my $errorFilePresent = false;

#####################################
#Indicates whether the script should#
#retry the restore operation        #
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
                        "RESTORESETFILEPATH",
                        "NOTIFICATIONFLAG",
                        "EMAILADDRESS",
                        "RESTORELOCATION",
			"RESTOREFROM",
			"RETAINLOGS"
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
                       "RESTORESETFILEPATH" => undef,
                       "NOTIFICATIONFLAG" => undef,
                       "EMAILADDRESS" => undef,
                       "RESTORELOCATION" => undef,
    		       "RESTOREFROM" => undef,
		       "RETAINLOGS" => undef
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
                          "--properties",
                          "--enc-type",
                          "--pvt-key",
                          "--user",
                          "--files-from",
                          "--type",
			  "--utf8-cmd",
			  "--encode",
			  "--proxy"
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

#############################################
#Errors encountered during restore operation#
#for which the script should retry the      #
#restore operation                          #
#############################################
my @ErrorArgumentsRetry = ("idevs error",
                           "io timeout",
                           "Operation timed out",
                           "nodename nor servname provided, or not known",
                           "failed to connect",
                           "Connection refused"
                          );

#############################################
#Errors encountered during restore operation#
#for which the script should not retry the  #
#restore operation                          #
#############################################  
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

#############################################
#Total count of files considered for restore#
#############################################
my $filesConsideredRestoreCount = 0;

#####################################################
#Hash containing file names which have been restored#
#####################################################
my %fileRestoreHash : shared;
%fileRestoreHash = ();

##############################################
#Hash containing file names which are in sync#
##############################################
my %fileSyncHash : shared;
%fileSyncHash = ();

####################################################
#Hash containing file names which encountered error#
#during restore                                    #
####################################################
my %fileErrorHash : shared;
%fileErrorHash = ();

#########################################
#Count of files which have been restored#
#########################################
my $numEntriesFileRestoreHash = 0;

##################################
#Count of files which are in sync#
##################################
my $numEntriesFileSyncHash = 0;

###################################
#Count of files which could not be# 
#restored due to specified errors #
###################################
my $numEntriesFileErrorHash = 0;

####################################
#Count of files which could not be #
#restored due to unspecified errors#
####################################
my $countOtherErrors = 0;

######################################
#Total count of files which could not#
#be restored                         #
######################################
my $countTotalErrors = 0;

################################
#Temporary directory created by# 
#idevsutil binary              #
################################
my $evsTempDirPath = "./evs_temp";

#########################################
#Maximum number of times the script     #
#should try to restore in case of errors#
#########################################
my $maxNumRetryAttempts = 5;

##############################################
#Subroutine that processes SIGINT and SIGTERM#
#signal received by the script during restore#
##############################################
$SIG{INT} = \&process_term;
$SIG{TERM} = \&process_term;

getParameterValue(\$arrayParameters[3], \$hashParameters{$arrayParameters[3]});
my $encType = $hashParameters{$arrayParameters[3]};
my ($appTypeSupport,$appType) = getAppType();

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
my $restoreUtf8File = "$currentDir/$userName/.restoreUtf8.txt";

open FILE, "<", $serverfile or (print $tHandle "$lineFeed Could not open file $serverfile , Reason:$! $lineFeed" and die);
$serverAddress = <FILE>;
chomp($serverAddress);

getParameterValue(\$arrayParameters[9],\$hashParameters{$arrayParameters[9]});
my $host = $hashParameters{$arrayParameters[9]};
if($host eq ""){
        $host = hostname;
}

createLogFiles();
getParameterValue(\$arrayParameters[4], \$hashParameters{$arrayParameters[4]});

getParameterValue(\$arrayParameters[5], \$hashParameters{$arrayParameters[5]});
getParameterValue(\$arrayParameters[8], \$hashParameters{$arrayParameters[8]});

getCountFilesConsideredRestore(\$hashParameters{$arrayParameters[5]});

doRestoreOperation(\$hashParameters{$arrayParameters[5]},
                   \$hashParameters{$arrayParameters[8]});

###############################################
#In case of error, retry the restore operation#
###############################################
if($retryAttempt)
{
  $errorFilePresent = false;
  $retryAttempt = false;

  for($index = 1; $index <= $maxNumRetryAttempts; $index++)
  {
    sleep 120;

    if(open(OUTFILE, "> $outputFilePath")){
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

    doRestoreOperation(\$hashParameters{$arrayParameters[5]},
                       \$hashParameters{$arrayParameters[8]});

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

writeRestoreSummary();
appendErrorFileContents();   
restoreRestoresetFileConfiguration();

##########################################################
#This subroutine creates the Log Directory if not present#
#It also creates the Error Log and Output Log files      #
#                                                        #
#The Error Log and Output Log files are created based on #
#the timestamp when the restore operation was started    #  
##########################################################
sub createLogFiles()
{
    my $workingDir = $currentDir;
    $workingDir =~ s/ /\ /g;

    $logDir = "$workingDir/$userName/LOGS";

# Check RETAINLOG field of CONFIG file 
  getParameterValue(\$arrayParameters[10], \$hashParameters{$arrayParameters[10]});
  if($hashParameters{$arrayParameters[10]} eq "NO"){
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
}


#########################################################
#This subroutine reads the entries in RestoresetFile and#
#counts the number of files which have to be restored   #
#########################################################
sub getCountFilesConsideredRestore()
{
  ${$_[0]} =~ s/ /\ /g;
 
  if(defined ${$_[0]} and
             ${$_[0]} ne "")
  {
    if(-e ${$_[0]})
    {
      my $RestoresetOriginalFile = ${$_[0]}.".org";
      my $RestoresetTempFile = ${$_[0]}.".tmp";

      if (sysopen(RESTORESET_TEMP_FILE_HANDLE, $RestoresetTempFile, O_RDWR|O_EXCL|O_CREAT, 0666)) {
	if(open(RESTORESETFILE_HANDLE, ${$_[0]})){
      		while(my $entry = <RESTORESETFILE_HANDLE>)
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

		          print RESTORESET_TEMP_FILE_HANDLE $entry;
		        }         
	        }
		close RESTORESETFILE_HANDLE;
	}  
      	else{
	  	print $tHandle "Could not open file ${$_[0]}, Reason:$! $lineFeed";
      	}
      	close RESTORESET_TEMP_FILE_HANDLE;
      }
     else{
        print $tHandle "Could not create $RestoresetTempFile, Reason:$! $lineFeed";
     }

      rename ${$_[0]}, $RestoresetOriginalFile;
      rename $RestoresetTempFile, ${$_[0]};   

      if(open(RESTORESETFILE_HANDLE, ${$_[0]})){
      	while(my $entry = <RESTORESETFILE_HANDLE>)
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

	  	  open UTF8FILE, ">", $restoreUtf8File or (print $tHandle "$lineFeed Could not open file $restoreUtf8File for properties cmd, reason:$! $lineFeed" and die);

	          print UTF8FILE $idevsutilArguments[0].$assignmentOperator.$pwdPath.$lineFeed,
		  	         $idevsutilArguments[1].$lineFeed,
	   		 	 $idevsutilArguments[9].$assignmentOperator.$proxyStr.$lineFeed,
	                         $idevsutilArguments[8].$lineFeed,
			         $userName.$serverAddressOperator.
	                         $serverAddress.$serverNameOperator.
	                         $serverName.$pathSeparator.$host.$entry.$lineFeed;
		  close UTF8FILE;
		  open TEMPHANDLE, "<", $restoreUtf8File or (print $tHandle "Could not open file $restoreUtf8File for Trace $lineFeed");
	  	  @fileContent = <TEMPHANDLE>;
		  close TEMPHANDLE;
		  print $tHandle "$lineFeed @fileContent $lineFeed";
	 	  $idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArguments[7].$assignmentOperator."\"$restoreUtf8File\"".$whiteSpace.$errorRedirection;
	          my $commandOutput = `$idevsutilCommandLine`;
	
		  unlink $restoreUtf8File;

	          my $fileString = "last access time";
        	  my $dirString = "contain files";

	          if($commandOutput =~ m/$fileString/i)
        	  {
	            $filesConsideredRestoreCount++;
        	  }
	          elsif($commandOutput =~ m/$dirString/i)
        	  {
	            my $matchedString = $';
             
        	    $matchedString =~ s/^\s+//;
	            $matchedString =~ s/\s+$//;

        	    my $fieldExtractorLeft = "\\[";
	            my $fieldExtractorRight = "\\]";

        	    if($matchedString =~ m/$fieldExtractorLeft/)
	            {
        	      $matchedString = $';
	            }

        	    if($matchedString =~ m/$fieldExtractorRight/)
	            {
        	      $matchedString = $`;
	            }
            
        	    if($matchedString =~ m/^\d+$/)
	            {
        	      $filesConsideredRestoreCount += $matchedString; 
	            }
        	  }
	          else
        	  {
	          }
        	}
      	 } #end of while
         close RESTORESETFILE_HANDLE;
      }
      else{
	  print $tHandle "$lineFeed Could not open ${$_[0]} $lineFeed";
      }	
    }
    else
    {
      if (open(ERRORFILE, ">> $errorFilePath")){
      	autoflush ERRORFILE;

	print ERRORFILE "Restore set file not found, verify the config file parameters.";
      	print ERRORFILE "Read \"ReadMe.txt\" for details. \n";
      	close ERRORFILE;
      }
      else
      {
          print $tHandle "$lineFeed Could not open file $errorFilePath, Reason:$! $lineFeed";
      }
      appendErrorFileContents();
 
      exit 1;
    }
  }
  else
  {
    if (open(ERRORFILE, ">> $errorFilePath")){
    	autoflush ERRORFILE;

    	print ERRORFILE "Restore set file path is missing in config file.";
    	print ERRORFILE "Read \"ReadMe.txt\" for details. \n";
    	close ERRORFILE;
    }
    else
    {
          print $tHandle "$lineFeed Could not open file $errorFilePath, Reason:$! $lineFeed";
    }
    appendErrorFileContents();
 
    exit 1;
  }
}

#################################################################
#This subroutine performs the actual task of restoring files    #
#It creates a child process which executes the restore command  #
#                                                               # 
#It also creates an output thread which continuously monitors   #
#the temporary output file                                      #
#                                                               #
#At the end of restore, it inspects the temporary error file    #
#if present                                                     #   
#                                                               #  
#It then deletes the temporary output file, temporary error file#
#and the temporary directory created by idevsutil binary        #
################################################################# 
sub doRestoreOperation()
{
  if(defined ${$_[0]} and
             ${$_[0]} ne "")
  {
    if(-e ${$_[0]})
    {
	
      verifyRestoreLocation(\${$_[1]});

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
 
	open UTF8FILE, ">", $restoreUtf8File or (print $tHandle "Could not open file $restoreUtf8File for restore, reason:$! $lineFeed" and die);
	print UTF8FILE $idevsutilArguments[5].$assignmentOperator.${$_[0]}.$lineFeed,
	      	       $idevsutilArguments[6].$lineFeed,
		       $idevsutilArguments[0].$assignmentOperator.$pwdPath.$lineFeed;
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
		       $userName.$serverAddressOperator.
                       $serverAddress.$serverNameOperator.
                       $serverName.$pathSeparator.$host.$pathSeparator.$lineFeed,
                       ${$_[1]}.$lineFeed;
	close UTF8FILE;

 	open TEMPHANDLE, "<", $restoreUtf8File or (print $tHandle "Could not open file $restoreUtf8File for Trace $lineFeed");
	@fileContent = <TEMPHANDLE>;
	close TEMPHANDLE;
	print $tHandle "$lineFeed @fileContent $lineFeed";
$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArguments[7].$assignmentOperator."\"$restoreUtf8File\"".$whiteSpace.$errorRedirection;

      $pid = fork();

      if(!defined $pid)
      {
        die "Cannot fork() child process : $!";
      }
      elsif($pid == 0)
      {
        exec($idevsutilCommandLine);
	if (open(ERRORFILE, ">> $errorFilePath")){
        	autoflush ERRORFILE;

	        print ERRORFILE "Unable to proceed the restore operation";
        	print ERRORFILE "Reason : Child process launch failed. \n";
	        close ERRORFILE;
	}
	else{
		print $tHandle "$lineFeed Could not open file $errorFilePath, Reason:$! $lineFeed";
	}
        appendErrorFileContents();

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
	#if ($outputThread->is_joinable()) {
	        $outputThread->join;
	#}
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
                tie my @array, 'Tie::File', $OutErrorFilePaths[1] or (print $tHandle "Could not tie with $OutErrorFilePaths[1], Reason:$! $lineFeed" and die);
                my $size =  $#array + 1;
                for(my $index = 0; $index < $size; $index++)
                {
                        if($array[$index] =~ m/$errorPatternServerAddr/)
                        {
                                getServerAddr();
                                last;
                        }
			if($array[$index] =~ m/$errorPatternPwd/)
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
      if (open(ERRORFILE, ">> $errorFilePath")){
      	autoflush ERRORFILE;

      	print ERRORFILE "Restore set file not found, verify the config file parameters.";
      	print ERRORFILE "Read \"ReadMe.txt\" for details. \n";
      	close ERRORFILE;
      }
      else{
        print $tHandle "$lineFeed Could not open file $errorFilePath, Reason:$! $lineFeed";
      }
      appendErrorFileContents();
      
      exit 1;
    }
  }
  else
  {
    if (open(ERRORFILE, ">> $errorFilePath")){
    	autoflush ERRORFILE;

	print ERRORFILE "Restore set file path is missing in config file.";
    	print ERRORFILE "Read \"ReadMe.txt\" for details. \n";
    	close ERRORFILE;
    }
    else{
	print $tHandle "$lineFeed Could not open file $errorFilePath, Reason:$! $lineFeed";
    }
 
    appendErrorFileContents();
 
    exit 1;
  }
}

#######################################################
#This subroutine verifies if the directory where files#
#are to be restored exists. In case the directory does#
#not exist, it sets the restore location to the       #
#current directory                                    #
#######################################################
sub verifyRestoreLocation()
{
  my $restoreLocationPath = ${$_[0]};
  $restoreLocationPath =~ s/ /\ /g;

  if(!defined $restoreLocationPath or
              $restoreLocationPath eq "")
  {
    ${$_[0]} = $currentDir;
    ${$_[0]} =~ s/ /\ /g;
  }

  my $posLastSlash = rindex $restoreLocationPath, $pathSeparator;
  my $dirPath = substr $restoreLocationPath, 0, $posLastSlash + 1;
  my $dirName = substr $restoreLocationPath, $posLastSlash + 1;

  if(-d $dirPath)
  { 
    foreach my $char (@invalidCharsDirName)
    {
      my $posInvalidChar = index $dirName, $char;

      if($posInvalidChar != -1)
      {    
        ${$_[0]} = $currentDir;
        ${$_[0]} =~ s/ /\ /g;

        last;
      }
    }
  }
  else
  {
    ${$_[0]} = $currentDir;
    ${$_[0]} =~ s/ /\ /g;
  }
}

#########################################################
#The output thread calls this subroutine to continuously#
#monitor the temporary output file and append entries to# 
#the output file once a file is fully restored.         #
#                                                       # 
#Also file names are added to the hashes representing   #
#file restore/sync                                      #
#########################################################
sub subOutputThread()
{
  # Flags to determine the status of OUTFILE
  my $Oflag = 0;

  $lineCount = undef;
  $prevLineCount = undef;

  my $fieldSeparator = "\\] \\[";

  my $iterationCount = 0;
  if(open(OUTFILE, ">> $outputFilePath"))
  {  
  	autoflush OUTFILE;

	print OUTFILE $lineFeed;
  	print OUTFILE "Restore Start Time :";
  	print OUTFILE $whiteSpace.localtime;
  	print OUTFILE $lineFeed.$lineFeed;
  }
  else
  {
    $Oflag = 1;
    print $tHandle "Could not open file $outputFilePath, Reason:$! $lineFeed";
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
        	        if(exists $fileRestoreHash{$keyString})
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
        	        $fileRestoreHash{$keyString} = 1;

                	if(exists $fileErrorHash{$keyString})
	                {
        	          delete $fileErrorHash{$keyString};
	                }
        	      }
	              else
        	      {
	              }

        	      my $restoreFinishTime = localtime;

	              my $fileSize = convertFileSize($fields[0]);              
		      if(!$Oflag){
	        	      print OUTFILE "[$restoreFinishTime][SUCCESS]",
		              		    "[$pathSeparator$fields[6]][$fileSize]".$lineFeed;
		      }
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
                if(exists $fileRestoreHash{$keyString})
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
                $fileRestoreHash{$keyString} = 1;

                if(exists $fileErrorHash{$keyString})
                {
                  delete $fileErrorHash{$keyString};
                } 
              }
              else
              {
              }

              my $restoreFinishTime = localtime;

              my $fileSize = convertFileSize($fields[0]);              
              if(!$Oflag){  
	              print OUTFILE "[$restoreFinishTime][SUCCESS]",
        	      		    "[$pathSeparator$fields[6]][$fileSize]".$lineFeed;
	      }
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
}

##########################################################
#Once the restore ends, this subroutine is called to read#
#the temporary output file for the last time and append  #
#entries to the output file.                             # 
#                                                        #
#Also file names are added to the hashes representing    #
#file restore/sync                                       #
##########################################################
sub subOutputRoutine()
{
  # Flags to determine the status of OUTFILE and PROGRESSFILE respectively
  my $Oflag = 0;

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
        	      if(exists $fileRestoreHash{$keyString})
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
        	      $fileRestoreHash{$keyString} = 1;

	              if(exists $fileErrorHash{$keyString})
        	      {
	                delete $fileErrorHash{$keyString};
        	      } 
	            }
        	    else
	            {
        	    }

	            my $restoreFinishTime = localtime;

        	    my $fileSize = convertFileSize($fields[0]);              
        	    if(!$Oflag){       
		            print OUTFILE "[$restoreFinishTime][SUCCESS]",
		            		  "[$pathSeparator$fields[6]][$fileSize]".$lineFeed;
		    }
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
}

###########################################################
#This subroutine checks if the temporary error file       # 
#is present. If present, it scans the temporary error file#
#                                                         #
#In case the account is under maintenance / has expired / #
#has been canceled, it exits the restore operation        #
#                                                         #
#Also file names are added to the hash representing error #
#in file restore in case errors are encountered while     #
#restore is in progress                                   # 
#                                                         #
#Also the subroutine checks for errors for which it should# 
#retry the restore operation                              # 
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

        unlink($OutErrorFilePaths[0]);
        unlink($OutErrorFilePaths[1]);
        rmtree($evsTempDirPath);
      
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

        unlink($OutErrorFilePaths[0]);
        unlink($OutErrorFilePaths[1]);
        rmtree($evsTempDirPath);
        
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

        unlink($OutErrorFilePaths[0]);
        unlink($OutErrorFilePaths[1]);
        rmtree($evsTempDirPath);
          
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

####################################################
#This subroutine converts the file size of a file  #
#which has been restored into human readable format#
####################################################
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
#It should then generate the restore summary report,  #
#append the contents of the error file to the output  #
#file and delete the error file.                      #
#######################################################
sub cancelSubRoutine()
{
  `killall $idevsutilBinaryName`;

  copyTempErrorFile();

  unlink($OutErrorFilePaths[0]);
  unlink($OutErrorFilePaths[1]);
  rmtree($evsTempDirPath);
  
  writeRestoreSummary();
  appendErrorFileContents();
  restoreRestoresetFileConfiguration();

  exit 0;
}

###############################################
#This subroutine writes the restore summary to#
#the output file                              #
###############################################
sub writeRestoreSummary()
{
	unlink $restoreUtf8File;
  $numEntriesFileRestoreHash = scalar keys %fileRestoreHash; 
  $numEntriesFileSyncHash = scalar keys %fileSyncHash;
  $numEntriesFileErrorHash = scalar keys %fileErrorHash;
   
    
  $countOtherErrors = $filesConsideredRestoreCount - $numEntriesFileRestoreHash -
                      $numEntriesFileSyncHash - $numEntriesFileErrorHash;

  $countTotalErrors = $numEntriesFileErrorHash + $countOtherErrors; 
  if (open(OUTFILE, ">> $outputFilePath"))
  {
	  print OUTFILE $lineFeed,
	  		"Summary : ".$lineFeed.$lineFeed;

	  print OUTFILE "Total files considered for restore : ",
	  		 $filesConsideredRestoreCount.$lineFeed;

	  print OUTFILE "Total files restored : ",
	 		 $numEntriesFileRestoreHash.$lineFeed;

	  print OUTFILE "Total files in sync : ",
	  		 $numEntriesFileSyncHash.$lineFeed;

	  print OUTFILE "Total files failed to restore : ",
	  		 $countTotalErrors.$lineFeed;

	  print OUTFILE $lineFeed,
	  		 "Restore End Time :",
	  		 $whiteSpace.localtime,
			 $lineFeed;

  	  if($cancelFlag){
	    print OUTFILE "Restore failed. Reason: Operation cancelled by user.".$lineFeed;
	  }
	  close OUTFILE;
  }
  else
  {
    print $tHandle "Could not open file $outputFilePath, Reason:$! $lineFeed";
  }
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

##########################################
#This subroutine moves the RestoresetFile#
#to the original configuration           #
##########################################
sub restoreRestoresetFileConfiguration()
{
  my $RestoresetOriginalFile = $hashParameters{$arrayParameters[5]}.".org";
  my $RestoresetFile = $hashParameters{$arrayParameters[5]};
  
  unlink $RestoresetFile;
  rename $RestoresetOriginalFile, $RestoresetFile;
}

