#!/usr/bin/perl
require 'header.pl';

#########################
#Configuration File Path#
#########################
my $confFilePath = "./CONFIGURATION_FILE";
$out = system("unlink $pwdPath 2> /dev/null");
if($out eq 0){
	unlink($pvtPath);
	clearFields();
	if(${ARGV[0]} ne 1){
		print "Account is Logged out Successfully\n";
	}
}
else{
	if(${ARGV[0]} ne 1){
		print "\nUnable to logout from account. Please try again\n";
	}
	else{
		unlink($pvtPath);
	        clearFields();
	}
}

sub clearFields()
{
	$dummyString = "";
        $confField = "PASSWORD";
        putParameterValue(\$confField, \$dummyString);
        $confField = "PVTKEY";
        putParameterValue(\$confField, \$dummyString);

        `sed -i '/ACCOUNT_CONFIG = SUCCESS/d' $confFilePath`;
}
