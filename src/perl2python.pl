#!/usr/bin/perl -w
# Mohammad Ghasembeigi
# Perl to Python syntax translator using regexp and perl
# Goal is to make manual translation of perl code easier
# Will read from stdin and output code at the end once all lines have been read

#Global Variables
%imports = (); #contains all required imports
@translatedLines = ();
@indentIndex = (0); #number of spaces for each line
$lineNum = 0; #current line number being analysed
$header = ""; #contains header line

$currentIndex = 0; #0 = no indent

#Temp vars and debugging
$printOutput = 1;

#Function Declarations
sub analyseLine($);
sub translatePrint($);
sub translateVar ($$);
sub translateloop($$);
sub translateLoopBreaks($);
sub translateChomp($);
sub translateJoin($$);
sub translateSplit($$);
sub translateForeach($$);

#Helper functions
sub conditionCheck($);
sub processVar($);

#***********************
# Main Loop
#***********************
while ($line = <>) {

    #initial steps
    $indentIndex[$lineNum] = $currentIndex;

    ### Main Line Read Loop ###
    $line = analyseLine($line);

    if (defined($line)) {
        if ($line =~ /^#!/ && $. == 1) {
            $header = "#!/usr/bin/python2.7 -u";
        } else {    #line has been translated, place in translated array
            $translatedLines[$lineNum] = $line;
        }
    }

	$lineNum++;
}

# Analyses line provided as argument and translates (using functions) appropriately
# Returns translated line or commented out orignal line if translation was not succesful
sub analyseLine($) {
    my $line = $_[0];

    if ($line =~ /^#!/ && $. == 1) {
		# translate #! line
		$line = "#!/usr/bin/python2.7 -u";
	} elsif ($line =~ /^\s*#/ || $line =~ /^\s*$/) {
		# Blank & comment lines can be passed unchanged
	} elsif ($line =~ /^\s*print\s*(.*)[\s;]*$/) { #print line detected
        $line = translatePrint($1);
    } elsif ($line =~ /^\s*[my]*\s*\$(.+)\s*=(\s*(\"?).*\"?)[\s;]*$/) { #basic variables, includes my $var case
        $line = translateVar($1, $2);
	} elsif ($line =~ /^\s*[my]*\s*\$(.+)\s*(\+\+)[\s;]*$/ || $line =~ /^\s*[my]*\s*\$(.+)\s*(--)[\s;]*$/) { #variable increment
        $line = translateVar($1, $2);
	} elsif ($line =~ /^\s*[my]*\s*\@(.+)\s*=(\s*(\"?).*\"?)[\s;]*$/) { #basic array
        $line = translateVar($1, $2);
	} elsif ($line =~ /^\s*(if)\s*\((.*)\)\s*{[\s;]*$/ || $line =~ /^\s*(while)\s*\((.*)\)\s*{[\s;]*$/ ||
            $line =~ /^\s*\s*(elsif)\s*\((.*)\)\s*{[\s;]*$/ || $line =~ /^\s*(else)\s*{[\s;]*$/) { #if/white statements, elsif with no end bracket
        $currentIndex++;
        $line = translateloop($2, $1);
	} elsif ($line =~ /^\s*}\s*(elsif)\s*\((.*)\)\s*{[\s;]*$/) { #elsif case with bracket
        $line = translateloop($2, $1);
        $indentIndex[$lineNum] = $indentIndex[$lineNum] - 1; #update indent for elseif (previous indent) to go back 1 indent
	} elsif ($line =~ /^\s*}\s*(else)\s*{[\s;]*$/) { #else case with bracket
        $condition = "";
        $line = translateloop($condition, $1);
        $indentIndex[$lineNum] = $indentIndex[$lineNum] - 1; #update indent for elseif (previous indent) to go back 1 indent
	} elsif ($line =~ /^\s*}[\s;]*$/) { #end if/while/elsif statements
        $currentIndex--;
        $line = undef $line;
	} elsif ($line =~ /^\s*chomp\s*\$(.*)[\s;]*$/) { #chomp
        $line = translateChomp($1);
	}  elsif ($line =~ /^\s*(last)[\s;]*$/ || $line =~ /^\s*(next)[\s;]*$/) { #next and last
        $line = translateLoopBreaks($1);
	} elsif ($line =~ /^\s*join\((.*)\s*,\s*(.*)\)[\s;]*$/) { #join
        $line = translateJoin($1, $2);
	} elsif ($line =~ /^\s*split\((.*)\s*,\s*(.*)\)[\s;]*$/) { #split
        $line = translateSplit($1, $2);
	} elsif ($line =~ /^\s*foreach\s+(.*)\s+\((.*)\)\s*{[\s]*$/) { #foreach
        $line = translateForeach($1, $2);
	} elsif ($line =~ /^\s*int\((.*)\)[\s]*$/) { #foreach
        my $varCheck = processVar($1);
        $line = "int(" . $varCheck . ")";
	} else {
        # Line was not translated, comment line out
        $line = "#$line";
	}

    return $line;
}

#***********************
#Printing Translated Code
#***********************

if ($printOutput) {

    # print header
    if (defined ($header)) {
        chomp($header);
        print "$header\n";   #print each converted line followed by single new line
    }

    # print any imports
    foreach $x (keys %imports) {
        print "import $imports{$x}\n";
    }

    # print main lines of code
    my $i = 0;
    foreach $x (@translatedLines) {
        if (defined($x)) {
            chomp($x); #remove any newlines that have been stored

            for $i (1..$indentIndex[$i]) {
                print "    "; #print 4 spaces for indenting
            }

            print "$x\n";   #print each converted line followed by single new line
        }

        $i++;
    }
}


#***********************
# Translating Functions
#***********************

# Python's print adds a new-line character by default
# so we need to delete it from the Perl print statement at times

# Print can translate singular statements; ie: print "$x\n"
# Print can translate comma seperated statements, ie: print "test\n", $variable, "$variable\n", "last\n";
#                                                   In this case, only new line at the end will be removed from last
# Print can handle concatenation; ie print "test" . "please" . "$var\n";
# Print can translate functions, ie; print function(1,2), if function is invalid/cant be translated, entire line will be commented out

sub translatePrint($) {
    my($line) = $_[0];

    my @chars = ();
    my $string = "";
    my $type = -1; #0 = variable, 1 = string (double quotes), 2 = function

    my $hasNewLine = 0;
    my $commentPrint = 0; #1 if entire print should be commented

    my @block = ();
    my @blockType = ();
    my $printString = "";

    #inital changes in case more than one end line added
    $line =~ s/;//g; #remove end of line character that may or may not be stored
    $line .= ";"; #add end of line character so only 1 exits at end
    chomp($line); #remove new lines that were carelessly stored

    if ($line =~ /^\s*"*(.*)[\n]*"*[\s;]*$/) {
        if ($line =~ /^(.*)\\n"[\s;]*$/) { #check to see if new line exists at end
            $hasNewLine = 1;
        }

        @chars = split("", $line); #review print statement character by character

        my $i = 0;

        #Loop through each character and assign blocks using comma seperator
        foreach $c (@chars) {

            #special checks
            if ($type == -1 && ($c eq ' '  || $c eq ',')) {
                next; #ignore these values if they come up
            }
            elsif ($c eq '"') {    #either string block started or ended
                if ($type == 1) {   #if already open block
                    $string .= '"'; #also store last quote
                    $block[$i] = $string;   #store string
                    $string = "";   #reset string
                    $type = -1; #end block
                    $i++; #increment counter
                }
                elsif($type == -1) {  #string block starting
                    $type = 1;
                    $blockType[$i] = 1;   #mark block as string
                }
            }
            elsif($c eq "(") { #have been reading function
                $type = 2;
                $blockType[$i] = 2;   #mark block as function
            }
            elsif ($c eq ")") { #function ended
                $string .= ')'; #also store last char
                $block[$i] = $string;   #store function
                $string = "";   #reset string
                $type = -1; #end block
                $i++; #increment counter
            }
            elsif ($type == -1 && ($c eq '$' ||  $c eq '@')) { #start variable block on $ vars and @lists
                $type = 0;
                $blockType[$i] = 0;   #mark block as function
            }
            elsif ($type == 0 && ($c eq ',' || $c eq ';') ) { #variable ended
                $block[$i] = $string;   #store var
                $blockType[$i] = 0;   #mark block as var
                $string = "";   #reset string
                $type = -1; #end block
                $i++; #increment counter
            }


            #storing of character
            if ($type != -1) { #if in active block, store all chars
                $string .= $c;
            }
            else { #else if not in active block
                if ($c ne ' ' && $c ne ',' && $c ne '"' && $c ne ')' && $c ne '.') { #dont store these characters for the function name
                    $string .= $c;
                }
            }

        }

        # Final formatting Steps
        if ($hasNewLine) {  #if new line exists at the end
            if ($block[$#block] =~ /^\W*\\n\W*$/) {   #if last element is just a new line with no words
                pop(@block); #remove it from the array
            }
            else {  #string or var exists as well as final new line
                 $block[$#block] =~ s/\\n"?$/"/g; #remove last newline in last element if it exists; python adds this in for us
            }
        }


        #Alter blocks into correct python format
        $i = 0;
        foreach $x (@block) {
            if ($blockType[$i] == 0) { #var
                $block[$i] = processVar($x);
            }
            elsif ($blockType[$i] == 1) { #string
                $block[$i] = processVar($x);
            }
            else { #$blockType[$i] == 2, function
                $block[$i] = analyseLine($x);

                if ($block[$i] =~ s/^#(.*)$/$1/) { #function was not translated
                    $commentPrint = 1;
                }
            }
            $i++
        }


    }

    $line = join(' + ', @block);

    #Only print if entire line translation was succesful
    if (!$hasNewLine) {
        if ($commentPrint) {
            $line = "#sys.stdout.write(" .  $line . ")"
        }
        else {
            $line = "sys.stdout.write(" .  $line . ")"
        }
    }
    else {
        if ($commentPrint) {
            $line = "#print " .  $line;
        }
        else {
            $line = "print " .  $line;
        }
    }

    return $line;
}

# Creates a variable in python file
sub translateVar ($$) {
    my(@args) = @_;
    my $line = "";

    $args[1] =~ s/;//g; #remove any ; stored for both functions and vars

    #if this string does not start with a $,@, ", ' or number, this is a function
    #if ($args[1] !~ /^\s*\$.*$/ && $args[1] !~ /^\s*\@.*$/ && $args[1] !~ /^\s*".*$/ && $args[1] !~ /^\s*'.*$/ && $args[1] !~ /^\s*[0-9].*$/) {
    if ($args[1] =~ /^\s*[A-Za-z].*$/) {
        $args[1] = analyseLine($args[1]);

        $line = $args[0] . "= " . $args[1];
    }
    else {
        $args[1] =~ s/\$//g; #remove any $ for variables

        #handle <STDIN>
        if ($args[1] =~ s/^(\s*)<STDIN>\s*$/$1sys\.stdin\.readline\(\)/g) {
            $imports{'sys'} = "sys"; #add sys import to hash table
        }

        #check for increment variable and translate if so
        if ($args[1] =~ /^\s*(\+)\+$/ || $args[1] =~ /^\s*(-)-$/) {
            $line = $args[0] . $1 . "=" . 1;
        }
        else {  #otherwise expression is provided
            $line = $args[0] . "=" . $args[1];
        }
    }


    return $line;
}

#translate simple if/elsif/else and while statements
sub translateloop($$) {
    my $condition = $_[0];
    my $type = $_[1];
    my $line = "";


    if ($type =~ /elsif/) {
        $type = "elif";
        $condition = conditionCheck($condition);
        $line = "$type $condition:";
    }
    elsif ($type =~ /else/) {
        $line = "else:";
    }
    else {
        $condition = conditionCheck($condition);
        $line = "$type $condition:";
    }

    return $line;
}

#translate chomp using rstrip()
sub translateChomp($) {
    my $line = $_[0]; #args[0] contains variable to chomp

    $line =~ s/\$//g;
    $line =~ s/;//g;

    return "$line = $line.rstrip()";
}

#translate next and last
# to break and continue
sub translateLoopBreaks($) {
    $type = $_[0];

    chomp($type);
    $type =~ s/\s//g; #remove any spaces

    if ($type eq "last") {
        return "break";
    }
    elsif ($type eq "next") {
        return "continue";
    }
}

# translates join
sub translateJoin($$) {
    my @args = @_;

    $args[1] = processVar($args[1]);
    $args[1] =~ s/\$//g; #remove any $ for variables

    return $args[0] . "." . "join(" . $args[1] . ")";
}

# translates split
sub translateSplit($$) {
    my @args = @_;

    $args[1] = processVar($args[1]);

    return $args[1] . "." . "split(" . $args[0] . ")";
}

# translates for each to for in
#handles both numerical ranges and variables
sub translateForeach($$) {
    my @args = @_;
    my $line = "";
    my ($upper, $lower) = "";

    $args[0] = processVar($args[0]);
    $args[1] = processVar($args[1]);

    if ($args[1] =~ /^(\w+)*\.\.(\w+)$/) { #check to see if range is included
        $lower = $1;
        $upper = $2;

        if ($2 =~ /\d/) {
            $upper++;
        }
        else {
            $upper .= "+1";
        }

        $line = "for " . $args[0] . " in xrange(" . $lower . ", " . $upper . "):";
    }
    else {  #otherwise use the list or variable
        $line = "for " . $args[0] . " in " . $args[1] . ":";
    }

    $currentIndex++; #increase indentation for following lines

    return $line;
}

#***********************
# Helper Functions
#***********************

#Processes variable or variable in string for use in python
sub processVar($) {
    my $var = $_[0];

    if ($var =~ /\$/) { #if variable inside string
        $var =~ s/^\s*"(.*)\s*"\s*$/$1/g; #remove quotes
        $var =~ s/\$//g;    #remove dollar signs
        if ($var =~ /\\n$/) { #if new line at end of variable, add it on as seperate new line
            $var =~ s/\\n$//g;    #remove new line at end
            $var .= " + \"\\n\"";
        }
    }

    if ($var =~ /\@/) { #if list inside string
         $var =~ s/\@//g;    #remove list signs
    }

    $var =~ s/;//g;    #remove any end of line chars

    if ($var =~ /ARGV/) {
        $imports{'sys'} = "sys"; #add sys import to hash table
        $var = "sys.argv[1:]";
    }

    return $var;
}

# Processes condition for use in python
sub conditionCheck($) {
    my $condition = $_[0];

    $condition =~ s/\$//g; #remove variable sign

    #change arithmetic operator
    #converts ! || &&
    $condition =~ s/\s*\&\&\s*/ and /g;
    $condition =~ s/\s*\|\|\s*/ or /g;
    $condition =~ s/\s*!\s*/ not /g;

    #change comparison operators
    #match at least one space to ensure a word is not replaced by mistake
    $condition =~ s/(\s+)eq(\s+)/$1==$2/g;
    $condition =~ s/(\s+)ne(\s+)/$1!=$2/g;
    $condition =~ s/(\s+)gt(\s+)/$1>$2/g;
    $condition =~ s/(\s+)lt(\s+)/$1<$2/g;
    $condition =~ s/(\s+)ge(\s+)/$1>=$2/g;
    $condition =~ s/(\s+)le(\s+)/$1<=$2/g;

    return $condition;
}
