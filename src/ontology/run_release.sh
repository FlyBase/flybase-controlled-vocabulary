# Running the FBCV release pipeline
# 0. This command ensures process stops if any error encountered.
set -e

# 1. Imports need to be updated separately for the preprocessing
# step to run normally
sh run.sh make all_imports -B

# 2. Now we can run the normal release pipeline
sh run.sh make IMP=false prepare_release -B
