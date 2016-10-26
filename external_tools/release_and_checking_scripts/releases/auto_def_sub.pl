#!/usr/bin/env perl

use warnings;
require OboModel;
use strict;

my ($obo_stag, $obo_mtag, $obo_stanza, $relations, $obo_header) = OboModel::obo_parse($ARGV[0]);

# New dumb version imports def but not references from GO, but avoids OboModel::obo_print.
# Since perl 5.18, this sub causes errors for stanzas with consider in => random truncation of output (!)
#this hack was solved instead by changes to OboMOdel.pm

#print $$obo_header."\n";

#while (my ($id, $stanza) = each %$obo_stanza) {
#  if ($stanza =~ m/def: \".+\$sub_(\w+\:\d+)/) {
#    my $sub_term_id = $1;
#    if (exists $obo_stag->{$sub_term_id}->{def}) {
#      $stanza =~ s/\$sub_(\w+\:\d+)/$obo_stag->{$sub_term_id}->{def}/;
#      print "\n[Term]\n$stanza\n";
#    } else {
#      warn "No def for $sub_term_id in source file"
#    }
#  } else {
#    print "\n[Term]\n$stanza\n";  
#  }
#}

#for (@{$relations}) {
#  print '

#[Typedef]
#'.$_
#    }
#print "\n";

# Should probably write a simple stanza printer for OboModel.pm
 

##  Current version: 

 while (my ($id, $tag) = each %$obo_stag) {
   if ($tag->{def} =~ m/\$sub_(\w+\:\d+)/) {
     my $sub_term_id = $1;
     if (exists $obo_stag->{$sub_term_id}->{def}) {
       $tag->{def} =~ s/\$sub_(\w+\:\d+)/$obo_stag->{$sub_term_id}->{def}/;
       $tag->{def_dbxref} = "$tag->{def_dbxref}, $obo_stag->{$sub_term_id}->{def_dbxref}"
     } else {
       warn "No def for $sub_term_id in source file"
     }
   }
 }
 OboModel::obo_print($obo_stag, $obo_mtag, $obo_stanza, $relations, $obo_header);


