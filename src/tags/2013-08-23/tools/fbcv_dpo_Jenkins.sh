#!/bin/sh 

# Aims: In ideal world, this would generate all the regular OBO and OWL versions complete with autodefs.  Achieving this will require a native way to work with the OWL version of the ontology - coming soon.  Until then, we're stuck with a perl script that requires an obo file that includes terms from which definitions need to be imported.  In this scenario, only the relaxed and --simple versions can have full definitions.

## Strategy
# Generate dpo release by merging down imports closure and then running oort with hermit.  The results live in dpo_oort
# Use the resulting --relaxed obo file to generate defs with auto_def_sub.pl 
# Run oort on the resulting file to generate a new --simple. This lives in dpo_oort_ad
# UP TO THIS POINT NOW WORKS
# Merge this with fbcv.owl
# Run oort to generate a -simple file for fbcv release.
# Filter on properties to make a release version with part_of only
# Merge full dpo with FBcv
# Run oort to generate a full set of release files apart from -simple
# Dump all full release files + the two -simple files into one folder for generating release.


# dpo release
echo '*** DPO release ***'
echo ''
echo '*** Merging import chain for dpo ***'
echo ''
cd ontologies  # Necessary for catalog to work (?)
owltools --catalog-xml catalog-v001.xml dpo-edit.owl --merge-import-closure -o file://`pwd`/../dpo_imports_merged.owl
cd ..
echo ''
echo '*** dpo OORT ***'
echo ''
ontology-release-runner --reasoner hermit dpo_imports_merged.owl --relaxed --asserted --allow-overwrite --no-subsets --outdir dpo_oort_full
echo ''
echo '*** Importing third party defs for -simple only ***'
echo ''
auto_def_sub.pl  dpo_oort_full/dpo-relaxed.obo >  dpo_oort_full/dpo-relaxed_ad.obo  

# run dpo oort again to generate --simple with defs.  Can use elk for this, as Hermit has already done the heavy lifting.

ontology-release-runner --reasoner elk  dpo_oort_full/dpo-relaxed_ad.obo --simple --prefix fbcv --allow-overwrite --no-subsets --outdir dpo_oort_ad  # Note - prefix needs to be lower case to work!

# fbcv release
echo '*** fbcv release ***'
echo ''
echo '*** merging full dpo with fbcv  ***'
echo ''
owltools ontologies/fbcv-edit.obo --merge dpo_imports_merged.owl  -o file://`pwd`/fbcv-merged.owl # Note - file order important for determining URI of merge 'winner'
echo ''
echo '*** fbcv OORT ***'
echo ''
ontology-release-runner --reasoner hermit fbcv-merged.owl --allow-equivalent-pairs --relaxed --asserted --allow-overwrite --no-subsets --outdir fbcv_oort_full
echo '*** make version of fbcv with regular autodefs (for imported chebi terms)  + equivalent named classes stripped out ***'
echo ''
update_EC_defs.pl ontologies/fbcv-edit.obo | egrep -v "^equivalent_to: " > fbcv-ne.obo #  Strip out assertions of equivalence between named classes after using these to generate autodefs.  In future I hope that improvements to owltools will eliminate the need for this grep -v. 
echo ''
echo '*** Merging simplified dpo and fbcv versions containing autodefs ***'
echo ''
owltools fbcv-ne.obo --merge dpo_oort_ad/dpo-simple.obo -o file://`pwd`/fbcv-ad-merged.owl
echo ''
echo '*** generating fbcv-simple versions with autodefs ***'
echo '' 
ontology-release-runner --reasoner elk fbcv-ad-merged.owl --prefix fbcv --simple --allow-overwrite --no-subsets --outdir fbcv_oort_ad  # restriction on prefixes not working!

if [ ! -d "oort" ]; then
    mkdir oort;
fi

echo '' 
echo '*** Making FlyBase version - stripping all but essential relations'
echo ''
owltools fbcv_oort_ad/fbcv-simple.obo --make-subset-by-properties part_of // -o file://`pwd`/fbcv-flybase.owl
obolib-owl2obo fbcv-flybase.owl -o oort/fbcv-flybase.obo


cp dpo_oort_full/* oort/.
cp fbcv_oort_full/* oort/.

cp dpo_oort_ad/dpo-simple.obo oort/.
cp fbcv_oort_ad/fbcv-simple.obo oort/.

rm -r dpo*
rm -r fbcv*




