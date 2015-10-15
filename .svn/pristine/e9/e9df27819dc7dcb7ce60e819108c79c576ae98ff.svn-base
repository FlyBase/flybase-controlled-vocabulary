#!/usr/bin/perl -w
require OboModel;
use strict;

my ($obo_stag, $obo_mtag, $obo_stanza, $relations, $obo_header) = OboModel::obo_parse($ARGV[0]);

my ($new_def) = &pc_def ($obo_stag, $obo_mtag);
my ($new_union_def) = &union_def ($obo_stag, $obo_mtag);

my ($id, $stanza) = '';
print "$$obo_header\n\n";
while (($id, $stanza) = each %$obo_stanza) {
  if (exists ($new_def->{$id})) {
    if (!($stanza =~ m/def\: "..+"/)) {
      if ($stanza =~ m/def\: "\." \[.*\]\n/) {
	$stanza =~ s/def\: "\." \[.*\]\n/$new_def->{$id}\n/ 
      } else {
	$stanza .= "\n".$new_def->{$id}
      }
    }
  } elsif (exists ($new_union_def->{$id})) {
    if (!($stanza =~ m/def\: "..+"/)) {
      if ($stanza =~ m/def\: "\." \[.*\]\n/) {
	$stanza =~ s/def\: "\." \[.*\]\n/$new_union_def->{$id}\n/ 
      } else {
	$stanza .= "\n".$new_union_def->{$id}
      }
    }
  }
  print "\[Term\]\n$stanza\n\n";
}
print "\[Typedef\]\n$_\n\n", foreach (@{$relations});


# phenotypic class defs from GO for terms defined by the pattern

# intersection_of: quality
# intersection_of: qualifier abnormal
# intersection_of: inheres_in GO:...

 sub pc_def {
  my $obo_stag = $_[0];
  my $obo_mtag = $_[1];
  my %pc_stat;
  my %pc_new_def;
  my $key;
  my $value;
  while (($key, $value) = each %$obo_stag) {
    $pc_stat{$key}=1, if (($value->{namespace})&&($value->{namespace} eq 'phenotypic_class'))
  }
  while (($key, $value) = each %pc_stat) {
    my ($GO_id_4_def, $GO_name_4_def, $GO_def, $new_dbxref, $new_def, $new_def_w_dbxref) = '';
    my $n = 0;
    my $m = 0;
    foreach (@{$obo_mtag->{$key}}) {
      if (($_->{estat})&&($_->{estat} eq 'int')) {
	if (($_->{rel} eq 'is_a')&&($_->{obj} eq 'PATO:0000001')) {
	  $n += 1;
	}
	if (($_->{rel} eq 'qualifier')&&($_->{obj} eq 'PATO:0000460')) {
	  $n += 1;
	}
	if ($_->{rel} eq 'inheres_in') {
	  $n += 1;
	  $m += 1;
	  $GO_id_4_def = $_->{obj};
	  $GO_name_4_def = $obo_stag->{$GO_id_4_def}->{name};
	  $GO_def = $obo_stag->{$GO_id_4_def}->{def};
	  $new_dbxref = $obo_stag->{$GO_id_4_def}->{def_dbxref}
	}
	if (($_->{rel} eq 'qualifier')&&($_->{obj} eq 'PATO:0000462')) {
	  $m += 1
	}
	if ($n == 3) { 
	 # print $obo_stag->{$GO_id_4_def}->{is_anonymous};
	  if ($obo_stag->{$GO_id_4_def}->{is_anonymous}) {
	    $new_def = "Phenotype that is a defect in $GO_def";
	  } else {
	    $new_def = "Phenotype that is a defect in $GO_name_4_def ($GO_id_4_def). \'$GO_name_4_def\' is defined as: \'$GO_def\'"
	  }
      $pc_new_def{$key}="def\: \"$new_def\" \[$new_dbxref\]";
	}
	if ($m == 2) { 
	#  print $obo_stag->{$GO_id_4_def}->{is_anonymous};
	  if ($obo_stag->{$GO_id_4_def}->{is_anonymous}) {
	    $new_def = "Phenotype that is the absence of $GO_def";
	  } else {
	    $new_def = "Phenotype that is the absence of $GO_name_4_def ($GO_id_4_def). \'$GO_name_4_def\' is defined as: \'$GO_def\'"
	  }
      $pc_new_def{$key}="def\: \"$new_def\" \[$new_dbxref\]";
	}
      }
    }
  }
return (\%pc_new_def)
}

sub union_def {
  my $obo_stag = $_[0];
  my $obo_mtag = $_[1];
  my $key;
  my $value;
  my %union;
  my %def;
  while (($key, $value) = each %$obo_mtag) {
    my @U;
    for (@{$value}) {
      if ($_->{estat} eq 'union_of') {
	push @U, $_->{obj}
      }
    }
    $union{$key}= \@U, if (@U);
  }
  my $id;
  my $ulist;
  while (($id, $ulist) = each %union) {
    $def{$id} = "def: \"EITHER: \'";
    my $i=1;
    for (@{$ulist}) {
      $def{$id} .= $obo_stag->{$_}->{def};
      $def{$id} .= "\' OR: \'", if ($i < @{$ulist});
      $def{$id} .= "\'\" \[".$obo_stag->{$_}->{def_dbxref}."\]", if ($i == @{$ulist});
      $i++;
    }
  }
  return (\%def)
}
