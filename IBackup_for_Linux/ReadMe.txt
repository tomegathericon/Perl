README FILE
===========

				IBackup for Linux
				=================

I. INTRODUCTION
================

This is a script-based approach for providing automatic online backup and restore capabilities for
Linux based systems.

II. Perform below steps, to proceed with script execution for backup / restore
==============================================================================

    1. Create an IBackup online account via www.ibackup.com

    2. Download the script bundle  (zip format)
      
      i.  The archive needs to be downloaded and extracted into a particular folder on your 
          Linux box.
   
      ii. Download the idevsutil command line utility (32 bit / 64 bit) from 
          http://evs.ibackup.com/download.htm and place it inside the script folder (extracted folder)

          After extraction of the zip archive, you will find following files in the folder:

	    a. login.pl
          b. Backup_Script.pl
          c. Restore_Script.pl
          d. Scheduler_Script.pl
          e. Job_Termination_Script.pl
          f. Status_Retrieval_Script.pl
	    g. header.pl
	    h. logout.pl
          i. CONFIGURATION_FILE
          j. BackupsetFile.txt
          k. RestoresetFile.txt
          l. ExcludeList.txt

    3. Provide appropriate permissions (executable permission) to the scripts and command line 
       utility

       Example:  chmod a+x *.pl and chmod a+x idevsutil
      
    4. Configuration file settings for backup / restore

       We have provided "CONFIGURATION_FILE" along with the download bundle. 
       Following are the parameters that you need to set.

       USERNAME : Your IBackup account username. (This is a mandatory field)

                  Example:  USERNAME = <your account username>

       PASSWORD : Your IBackup account password. (This is a mandatory field)
  
                  Example:  PASSWORD = <your account password>

       ENCTYPE  : The Encryption type to be used for the initial account configuration.          
                  This field can be set to either DEFAULT or PRIVATE. 
                  By default your account will be set to DEFAULT encryption if the 
                  encryption type is not mentioned.

                  Example:  ENCTYPE = DEFAULT
  
       PVTKEY   : Enter your private encryption key.
       
                  Example:  PVTKEY = <myprivate-encryption-key>

       EMAILADDRESS : Enter your valid email-address to receive the backup job status 
                      (email notification)

                      Example:  EMAILADDRESS = sample@test.com
                      
                      If the scheduled backup email notification is identified as spam then add  
                      IBackup as a safe sender (link: https://www.ibackup.com/white_list.htm).

       BACKUPSETFILEPATH : Enter the backup set file path.
    
                           Note: Enter file / folder paths that you wish to backup into 
                                 backup set file.

                           Example:  BACKUPSETFILEPATH = ./BackupsetFile.txt

       RESTORESETFILEPATH : Enter the restore set file path. 
    
                            Note: Enter file / folder paths that you wish to restore into 
                                  restore set file.

                            Example:  RESTORESETFILEPATH = ./RestoresetFile.txt

       EXCLUDELISTFILEPATH : Enter the exclude list file path.

                             Note: Enter file / folder paths that you wish to exclude from
                                   getting backed up, into exclude list file

                                   For example, if you provide a folder path in backup set file
                                   but you wish that certain sub-folders / files be excluded
                                   from backup, you can provide the path of those
                                   sub-folders / files in exclude list file

                                   Please note that you have to provide absolute path of the
                                   sub-folders / files that you wish to exclude
 
                                   Please leave the exclude list file blank in case you don't
                                   need to exclude folders / files from getting backed up

                             Example:  EXCLUDELISTFILEPATH = ./ExcludeList.txt

       RESTORELOCATION : The location on the local computer where the files / folders will
                         be restored.

                         Example:  RESTORELOCATION = /root/Desktop
       
       BACKUPLOCATION : The hostname of local machine will be considered by default for this field. 
				User can customize this field to backup data. All the backed up files/folders 
				in the server will be under this name. If the machine/account is changed, 
				this field can also be changed to continue to use the same previous 
				BACKUPLOCATION of the backup in User's account.
				
				Note: In case this field left empty then machine name will be considered.

	RESTOREFROM : The hostname of local machine will be considered by default for this field.    
                    User can customize this field to restore data. Any files/folders that are 
		     	  to be restored from the server to local machine should be under this name.
				  
				  Note: In case this field left empty then machine name will be considered.

	RETAINLOGS : Enter YES/NO for this field. If YES, then all the LOGS generated will be 
		     	 retained as-is. If NO, then all the LOGS that were generated so far will be
		     	 cleared except the current running job. The deletion of LOGS is done automatically when
		     	 a new job runs. YES is considered if this field is left empty.
	
	PROXY : Provide your proxy details,if your machine is behind proxy server. 
		  PROXY = <Username>:<Password>@<IPAddress>:<Port>
		  Provide all field Username, Password, IPAddress and Port empty in case no proxy is set 
		  in your machine. For Ex: PROXY = :@: 
	
	BWTHROTTLE : Provide the bandwidth percentage in number between 1 to 100. If you want to restrict the 
				 bandwidth usage for backup operation.

      Note: For more information, verify the sample configuration and other supported files  
             provided along with the download bundle.

    5. Login to your IBackup Account

	Once after setting the configuration file (as detailed above), run the below command
	$./login.pl

	This perl will create a logged in session for the IBackup Account mentioned in configuration file.
	Also it will replace your IBackup password and private key values in configuration file with dummy values
	after successful login.

    6. Schedule the backup job

       Once after setting the configuration file (as detailed above), run the below command
       $./Scheduler_Script.pl

       Choose the desired scheduled date/time for the backup job. 
       The backup job will automatically start at the scheduled time.

    7. View the backup progress 

       To view the progress details during backup, run the below command 
       $./Status_Retrieval_Script.pl

    8. Restore

       Run the restore script using the below command 
       $./Restore_Script.pl

    9. View the backup / restore logs
 
       You can view the backup / restore log files that are present in the ./<UserName>/LOGS folder.

   10. Logout from your IBackup Account
	
	 Run $./logout.pl
	 In case you want to keep your IBackup account more safe then you can use this script to log out from 
	 your logged in session. 
	
	 Once you log out, your IBackup account password and private key values will become empty in configuration file.
	 This will make your account more secure as no one can see your credantials and no one can access your account even 
	 using scripts. 

	For accessing IBackup account again, password and private key needs to mention in configuration file and need to run login.pl.
    
    11. For mail notification sendmail should be installed with enable and running state.

III. Script file details
========================

     a. login.pl
	
	  Mandatory script to be executed before performing any other operations to login to your IBackup account.

     b. Scheduler_Script.pl

        Scheduler_Script.pl is used to schedule the backup job periodically. The backup job
        will automatically start at the scheduled time.
          
        Using this script, you can also edit and delete the existing backup job.

     c. Backup_Script.pl

        The script will be automatically executed during backup operation.

     d. Status_Retrieval_Script.pl

        Run/execute this script to view the progress details of the current backup job which is underway. 

     e. Job_Termination_Script.pl

        Run/execute this script to stop / terminate the backup job which is underway.

     f. Restore_Script.pl

        Run/execute this script to restore files / folders to your local computer. Ensure that the restore set file path is configured in the CONFIGURATION_FILE (refer the above section (4) for more details on configuration file settings)

     g. header.pl

	The script will be automatically executed during backup and restore operation.

     h. logout.pl
	
	Optional script when executed will log out from logged in IBackup account and clear PASSWORD and PVTKEY fields in CONFIGURATION_FILE. 
	
	User has to run login.pl again to create a logged in session and to run scripts for any other operations.
	
	Note: Scheduled jobs will run even after logging out from IBackup account using logout.pl.


IV. SYSTEM REQUIREMENTS
=======================
    Linux(CentOS/Ubuntu/Fedora) - 32-bit/64-bit

V. SOFTWARE/PLUG-IN DOWNLOADS
=============================
   Perl v10.0.0 or later
   Get the Perl version details using the command : $perl -v 

VI. RELEASES
=============
	Build 1.0:
		N/A
	
	Build 1.1:
	
		1.	Fixed the backup/restore issue for password having special characters.
		2.	Fixed the backup/restore issue for encryption key having special characters.
		3.	Fixed the backup/restore issue for user name having special characters.
		4.	Fixed the backup/restore issue for backup/restore location name having special characters.
		5.	Moved LOGS folder inside user name folder for better management.
		6.      Avoided unnecessary calls to server at the time of backup as well as restore. 
			Like create directory call, get server call and config account call. As before these calls 
			was taking place with each backup and restore operation.
		7.	New file named header.pl has been created. It contains all common functionalities. 

	Build 1.2:
		
		1.	Avoided error in the log when email is not specified in CONFIGURATION_FILE after backup 
			operation.
		2.	A new BACKUPLOCATION field has been introduced in CONFIGURATION_FILE. All the backed up 
			files/folders will be stored in the server under this name.  
		3.	A new RESTOREFROM field has been introduced in CONFIGURATION_FILE.  Any files/folders 
			that exist under this name can be restored from server to local machine.

	Build 1.3:

		1.	A new field RETAINLOGS has been introduced in CONFIGURATION_FILE. This field is used to 
			determine if all the logs in LOGS folder have to be maintained or not.
		2.	Fixed Retry attempt issue if backup/restore is interrupted for certain reasons.  

	Build 1.4:

		1. 	A new field PROXY has been introduced in CONFIGURATION_FILE. This field if enabled will 
			perform operations such as Backup/Restore via specified Proxy IP address.
		2. 	A new file login.pl has been introduced which reads required parameters from CONFIGURATION_FILE
			and validates IBackup credentials and create a logged in session. 
		3. 	A new file logout.pl has been introduced which allow to log out from logged in session for IBackup account.
		      It also clears PASSWORD and PVTKEY fields in configuration file.
	Build 1.5:
		1. A new field BWTHROTTLE has been introduced in CONFIGURATION_FILE. To restrict the bandwidth usage
		   for backup operation.
		2. 	Changes has been made to make script work on perl ver 5.8 as well.

	Build 1.6:
		1.	Schuedule backup issue has been fixed in user logged out mode.

	======================================================================================
