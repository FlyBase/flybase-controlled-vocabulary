## Customize Makefile settings for fbcv
## 
## If you need to customize your Makefile, make
## changes here rather than in the main Makefile

DPO=https://raw.githubusercontent.com/FlyBase/drosophila-phenotype-ontology/master/dpo-simple.obo

components/dpo-simple.obo:
	echo "CHANGE DPO PURL!"
	@if [ $(MIR) = true ] && [ $(IMP) = true ]; then $(ROBOT) convert -I $(DPO) -o $@.tmp.owl && mv $@.tmp.owl $@; fi
